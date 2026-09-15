-- Maki configuration, projected read-only from this flake.
--
-- The shape encodes one operating contract: explicit reasoning effort,
-- bounded fan-out, one writer, and no blanket permission bypass. The
-- discovery funnel is `index` -> `grep`/`glob` -> `read`, and anchored edits
-- are `edit_lines` and `insert_lines`.
--
-- The `require` lines for the roles and rv plugins are appended by the Home
-- Manager module, so a disabled plugin is never required into a missing file.

maki.setup({
  -- Reasoning effort is worth more than the tokens it costs on this work.
  -- Default to max instead of paying for a picker interaction at the start of
  -- every session.
  always_thinking = "max",

  -- Deliberately not enabled: `always_yolo`. Protected actions go through
  -- explicit permits, and permissions.toml carries the allowlist. Toggle per
  -- session with `/yolo` when a sandbox already is the boundary.
  always_yolo = false,

  -- `code_execution` calling `task` turns one sandbox script into a fan-out
  -- tree. Keep delegation one level deep; leave the unbounded shape to
  -- `/workflow` for the sessions that actually want it.
  always_workflow = false,

  ui = {
    theme = "gruvbox-night",
    -- Quiet startup: no animation between invocation and prompt.
    splash_animation = false,
    -- Reasoning stays visible.
    show_thinking = true,
    scrollbar = true,
    inline_images = true,
    -- tmux needs `allow-passthrough all` for OSC 9 to survive a window switch.
    notifications = "auto",
    mouse_scroll_lines = 5,
    max_input_lines = 30,

    -- Maki collapses tool output. Raise the ceilings that matter for review
    -- (bash, sandbox scripts, indexes) and leave the rest.
    tool_output_lines = {
      bash = 12,
      code_execution = 12,
      task = 8,
      index = 10,
      grep = 6,
      read = 5,
      write = 10,
      web = 5,
      other = 5,
    },
  },

  agent = {
    -- rtk is on PATH through the Home Manager module, so bash output is
    -- filtered before it reaches the context window.
    rtk = true,

    -- Re-read a file that changed on disk before editing it. An anchored edit
    -- against a stale read lands silently in the wrong place.
    stale_read_check = true,

    max_output_lines = 3000,
    max_output_bytes = 131072,
    max_continuation_turns = 5,
    compaction_buffer = "20%",

    compaction_instructions = table.concat({
      "Preserve: the accepted objective and its mandatory requirements, the",
      "writable roots in play, exact commands already run and their observed",
      "outcomes, absolute artifact paths, and unresolved blockers. Drop",
      "superseded plans and narration. Never mark an obligation satisfied in",
      "the summary that was not satisfied in the transcript.",
    }, " "),

    post_compaction_instructions = table.concat({
      "The summary is a lead, not authority over current source. Re-read the",
      "instruction files for the working directory and re-`index` any file you",
      "are about to change before acting on a recalled detail.",
    }, " "),
  },

  provider = {
    -- Maki's `openai` provider is the Codex backend once `maki auth login
    -- openai` signs in with the ChatGPT subscription.
    default_model = "openai/gpt-6-astra",

    -- Deliberately no `allowed_models`. In Maki that list is hard policy, not
    -- a picker convenience: it also blocks delegation, `--model`, and every
    -- provider you later add.
    -- Curate with tiers in `/model` (`!` strong, `@` medium, `#` weak,
    -- `$` compaction) instead, which steers cost without locking the door.
    -- To ban something specific, list it in `excluded_models`; exclusions win.
    excluded_models = { },

    -- max-effort turns on astra stream well past maki's 300s default.
    stream_timeout_secs = 900,
    low_speed_timeout_secs = 300,
    max_timeout_retries = 10,
  },

  storage = {
    max_log_files = 20,
    max_log_bytes_mb = 500,
    input_history_size = 500,
  },

  -- Ask before trusting a project, with no `paths` entries: a cloned repo
  -- should not get to run its own `.maki/init.lua` before you have read it.
  trust = {
    prompt = true,
    paths = {},
  },

  -- No install telemetry.
  telemetry = {
    enabled = false,
  },

  -- Local services the agent may reach. Empty on purpose: the model picks
  -- these URLs, so add a host only while you are actually testing it, e.g.
  -- `allowed_private_hosts = { "localhost:5173" }` for a dev server.
  net = {
    allowed_private_hosts = {},
  },

  plugins = {
    -- Nix evaluations and Bazel builds outrun the 120s default.
    bash = { timeout_secs = 600 },

    code_execution = {
      timeout_secs = 120,
      max_memory_mb = 256,
    },

    -- The anchored-edit surface. `insert_lines` is opt-in upstream; the
    -- worker role needs it, so turn it on.
    edit = {
      edit_lines = true,
      insert_lines = true,
      multiedit = true,
    },

    -- Generated Rust and vendored TypeScript blow past the 2 MB default.
    index = { max_file_size_mb = 8 },

    glob = { search_result_limit = 200 },
    grep = { search_result_limit = 200 },

    -- Eight keeps a fan-out legible and the bill bounded. `allow_model` stays
    -- off so the tier ladder, not the model name, is what a delegating turn
    -- chooses.
    task = {
      max_concurrent = 8,
      allow_model = false,
    },

    -- Needs EXA_API_KEY. Switch to "youcom" for the keyless free profile.
    websearch = { provider = "exa" },
  },
})

-- Names other agents trained into muscle memory. Aliasing adds a name, it
-- never hides the original.
for _, alias in ipairs({
  { name = "/clear", target = "/new", description = "Alias for /new" },
  { name = "/resume", target = "/sessions", description = "Alias for /sessions" },
  { name = "/models", target = "/model", description = "Alias for /model" },
}) do
  maki.api.register_command({
    name = alias.name,
    description = alias.description,
    handler = function()
      local ok, err = maki.api.run_command(alias.target)
      if not ok then
        maki.ui.flash("could not run " .. alias.target .. ": " .. tostring(err))
      end
    end,
  })
end

-- History-destroying VCS commands, blocked before the permission prompt.
--
-- permissions.toml can only match a scope prefix, so `git push origin main
-- --force` slips past a `git push --force*` deny while `git push --force
-- origin main` is caught. Matching on parsed words instead is order
-- independent, which is the whole reason this lives in Lua. The reason text
-- reaches the model as the tool result, so it learns the alternative rather
-- than retrying a variant.

local FORCE_PUSH = "Force pushing rewrites shared history. Use --force-with-lease, and ask before touching a branch someone else tracks."

local function split_words(segment)
  local words = {}
  for word in segment:gmatch("%S+") do
    words[#words + 1] = word
  end
  return words
end

local function has(words, from, value)
  for i = from, #words do
    if words[i] == value then
      return true
    end
  end
  return false
end

-- Returns a refusal reason, or nil when the segment is fine.
local function destructive_reason(words)
  local program, sub = words[1], words[2]
  if not program or not sub then
    return nil
  end

  if program == "git" then
    if sub == "push" then
      if has(words, 3, "--force-with-lease") then
        return nil
      end
      if has(words, 3, "--force") or has(words, 3, "-f") then
        return FORCE_PUSH
      end
    elseif sub == "reset" and has(words, 3, "--hard") then
      return "`git reset --hard` discards uncommitted user work. Stash it, commit it, or ask which changes may go."
    elseif sub == "clean" then
      for i = 3, #words do
        if words[i]:match("^%-%a*f") then
          return "`git clean -f` deletes untracked files that may be the user's. List them first and ask."
        end
      end
    end
    return nil
  end

  if program == "jj" then
    if sub == "abandon" then
      return "`jj abandon` drops a change. Ignore, untrack, and delete are distinct operations; say which one you mean and ask first."
    elseif sub == "undo" then
      return "`jj undo` is not cleanup. Describe the state you want and reach it forward, or ask."
    elseif sub == "op" and words[3] == "restore" then
      return "`jj op restore` rewinds the whole operation log, including the user's own work. Ask first."
    end
  end

  return nil
end

maki.api.set_slot("tool.bash.input", function(prev, input, ctx)
  local command = input.command
  if type(command) ~= "string" then
    return prev(input, ctx)
  end

  -- Check each segment so `cd repo && git reset --hard` is caught too. This
  -- guards against an over-eager agent; it is not a security boundary.
  -- Permissions and folder trust are what actually gate the call.
  for segment in command:gmatch("[^;&|]+") do
    local reason = destructive_reason(split_words(segment))
    if reason then
      return nil, reason
    end
  end

  return prev(input, ctx)
end)
