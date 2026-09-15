-- Named delegation roles.
--
-- Maki's `task` tool already enforces most of what a role table would
-- otherwise have to spell out. The write tools declare `audiences = { "main",
-- "general_sub", "interpreter" }`, so a `research` subagent cannot see them —
-- read-only enforcement, for free, with no per-role tool allowlist to
-- maintain. And `task` itself is `{ "main", "workflow" }`, so no subagent is
-- offered it: one level of delegation is structural here, not configured.
--
-- What the tool cannot supply is the part that has to be written down: a
-- charter per role, and a model and reasoning effort to match. That is what
-- this adds.
--
-- Concurrent writers are handled by shape rather than by a lease. `worker` is
-- the only role with a write surface and it holds a semaphore of one, so two
-- writers cannot overlap by construction. No ledger, no nonce, no recovery
-- path — the shape of the tool is the invariant.

local ToolView = require("maki.tool_view")
local output_limits = require("maki.output_limits")

local READ_ONLY_CONCURRENCY = 4
local SUMMARY_NUDGE = "You finished your work but did not summarize it. Reply with a concise summary of what you found, with file:line references."
local DEFAULT_OUTPUT_LINES = 5
local BODY_INDENT_COLS = 4
local MIN_MD_WIDTH = 20

local ROLES = {
  scout = {
    audience = "research_sub",
    prompt_id = "research",
    charter = "You are the scout: fast, read-only reconnaissance. Map the territory the task names — the entry points, the modules involved, and where the relevant behaviour actually lives — then stop. Return a map with file:line references and the open questions a writer would hit. Not an implementation plan, and not an opinion about what should change. Modify nothing.",
  },

  researcher = {
    audience = "research_sub",
    prompt_id = "research",
    -- `read` plus the web tools and nothing else. Keeping the surface that
    -- narrow is what stops it wandering into the codebase and answering from
    -- source instead of from the web.
    only = { "read", "websearch", "webfetch" },
    charter = "You are the researcher, working one assigned angle. Use `read` only for local evidence you were handed; everything else comes from the web. Prefer primary sources and open the most relevant ones rather than trusting a search snippet, and cite the final URL for every material claim. Return a conclusion, its supporting URLs, and the gap you could not close. On an authentication or provider failure, report the exact diagnostic — do not silently downgrade, and do not declare the question unanswerable. Modify nothing.",
  },

  reviewer = {
    audience = "research_sub",
    prompt_id = "research",
    charter = "You are an independent reviewer with no mutation surface and no stake in the implementation. Review what the change does against what it was meant to do. Report concrete located findings — file:line, what breaks, under which input — ranked by severity, and say plainly when something is fine. Do not propose a rewrite, do not fix anything, and do not pad the list to look thorough.",
  },

  oracle = {
    audience = "research_sub",
    prompt_id = "research",
    charter = "You are the oracle, a read-only decision-consistency challenger. Treat the task and evidence you were given as authoritative and do not presume decisions you were not told about. Inspect only the sources needed to evaluate the decision in front of you. Return narrow, actionable recommendations with concise evidence and the residual uncertainty you could not remove. Implement nothing.",
  },

  worker = {
    audience = "general_sub",
    prompt_id = "general",
    writer = true,
    charter = "You are the only role that writes, and no other writer runs while you hold this slot. Before editing, `index` each file and read the exact ranges you intend to change. Keep edits inside the assigned slice: `edit_lines`, `insert_lines` or `multiedit` against fresh line numbers, re-`index` when a change moves them. Run the project's own checks for every file you touched and report their real output, not your expectation of it. On a genuine blocker, preserve the work done so far and return the exact evidence and the remaining steps rather than working around the obstacle.",
  },
}

-- Tiers rather than model names, so `/model` decides which model each tier
-- means and the table survives a provider change. A role may pin `spec`
-- instead, which is how you send the cheap roles to another provider
-- entirely:
--
--   scout = { spec = "hetzner/Qwen3.8-27B", thinking = "high" }
--
-- `tier` is clamped to the parent's tier so a role cannot escalate cost on its
-- own; `spec` is exact and deliberately escapes that clamp.
local PROFILES = {
  simple = {
    description = "Focused execution: every role at medium effort.",
    scout = { tier = "medium", thinking = "medium" },
    researcher = { tier = "medium", thinking = "medium" },
    reviewer = { tier = "medium", thinking = "medium" },
    oracle = { tier = "medium", thinking = "medium" },
    worker = { tier = "medium", thinking = "medium" },
  },
  complex = {
    description = "Subsystem execution: strong reasoning and review, medium discovery.",
    scout = { tier = "medium", thinking = "high" },
    researcher = { tier = "medium", thinking = "high" },
    reviewer = { tier = "strong", thinking = "high" },
    oracle = { tier = "strong", thinking = "high" },
    worker = { tier = "strong", thinking = "high" },
  },
  max = {
    description = "Deep execution: strong reasoning roles, medium scouting, maximum effort.",
    scout = { tier = "medium", thinking = "xhigh" },
    researcher = { tier = "strong", thinking = "max" },
    reviewer = { tier = "strong", thinking = "max" },
    oracle = { tier = "strong", thinking = "max" },
    worker = { tier = "strong", thinking = "xhigh" },
  },
}

local M = {}

local active_profile = "max"

local role_names = {}
for name in pairs(ROLES) do
  role_names[#role_names + 1] = name
end
table.sort(role_names)

local profile_names = {}
for name in pairs(PROFILES) do
  profile_names[#profile_names + 1] = name
end
table.sort(profile_names)

-- One slot for the writer is the whole one-writer guarantee. Read-only roles
-- share a wider pool; they cannot collide with anything.
local writer_slot = maki.async.semaphore(1)
local reader_slots = maki.async.semaphore(READ_ONLY_CONCURRENCY)

local description = [[Delegate to a named role, each with its own model, reasoning effort and tool surface. Prefer this over `task` when the work fits one.

- `scout`: read-only recon of unfamiliar code. Returns a map, not an opinion.
- `researcher`: one web question. read + websearch + webfetch only; cites final URLs.
- `reviewer`: independent review of a change. Finds problems, fixes none.
- `oracle`: challenges a decision already made, against evidence you supply.
- `worker`: the only role that writes. Serialised, so two never run at once.

Ask for a summary with file:line refs, not file contents. Batch independent read-only roles.]]

local schema = {
  type = "object",
  required = { "role", "description", "prompt" },
  additionalProperties = false,
  properties = {
    role = {
      type = "string",
      enum = role_names,
      description = "Which role to delegate to",
    },
    description = {
      type = "string",
      description = "Short (3-5 words) description of the task",
    },
    prompt = {
      type = "string",
      description = "Goal, constraints, the files and evidence that matter, and what to return. Starts fresh: inline what it needs.",
    },
    thinking = {
      type = "string",
      description = "Override the role's reasoning effort: off|adaptive|minimal|low|medium|high|xhigh|max. Capped at the parent's.",
    },
  },
}

local function settings_for(role_name)
  local profile = PROFILES[active_profile] or PROFILES.max
  return profile[role_name] or {}
end

local function handler(input, ctx)
  local role = ROLES[input.role]
  if not role then
    return { llm_output = "unknown role: " .. tostring(input.role), is_error = true }
  end

  local settings = settings_for(input.role)
  local model, model_err = maki.agent.resolve_model(ctx, {
    tier = settings.tier,
    spec = settings.spec,
  })
  if model_err then
    return { llm_output = model_err, is_error = true }
  end

  local base, prompt_err = maki.agent.system_prompt(ctx, {
    prompt_id = role.prompt_id,
    instructions = true,
  })
  if prompt_err then
    return { llm_output = prompt_err, is_error = true }
  end

  local tool_defs, tools_err = maki.agent.tools(ctx, {
    audience = role.audience,
    only = role.only,
    except = role.except,
    spec = model.spec,
  })
  if tools_err then
    return { llm_output = tools_err, is_error = true }
  end

  local slots = role.writer and writer_slot or reader_slots
  local permit = slots:acquire()
  local sess

  -- pcall so a raised error cannot leak the permit or the session; the writer
  -- slot never being released would wedge every later worker.
  local ok, out = pcall(function()
    local sess_err
    sess, sess_err = maki.agent.session(ctx, {
      model_spec = model.spec,
      system = base .. "\n\n" .. role.charter,
      tools = tool_defs,
      audience = role.audience,
      name = input.role .. ": " .. input.description,
      thinking = input.thinking or settings.thinking,
    })
    if sess_err then
      return { llm_output = sess_err, is_error = true }
    end

    local result, err = sess:prompt(input.prompt)
    -- A subagent that only called tools returns an empty string. One nudge is
    -- cheaper than handing the parent nothing and letting it re-delegate.
    if not err and result and result.text == "" then
      result, err = sess:prompt(SUMMARY_NUDGE)
    end

    if err then
      if result and result.text ~= "" then
        return {
          llm_output = input.role .. " interrupted (" .. err .. "). Partial output:\n" .. result.text,
          is_error = true,
        }
      end
      return { llm_output = input.role .. " error: " .. err, is_error = true }
    end
    if not result or result.text == "" then
      return { llm_output = input.role .. " finished without a summary", is_error = true }
    end
    return { llm_output = result.text, format = "markdown" }
  end)

  if sess then
    sess:close()
  end
  permit:release()
  if not ok then
    error(out, 0)
  end
  return out
end

local function header(input)
  local buf = maki.ui.buf()
  buf:line({
    { tostring(input.role or "role"), "tool" },
    { " " .. tostring(input.description or ""), "dim" },
  })
  return buf
end

local function restore(_input, output, is_error, ctx)
  local tol = ctx:tool_output_lines()
  return ToolView.restore_markdown(output, is_error, {
    max_lines = (tol and tol.task) or DEFAULT_OUTPUT_LINES,
    keep = "head",
    max_line_bytes = output_limits.DEFAULT_MAX_LINE_BYTES,
    width = math.max(maki.ui.terminal_size().cols - BODY_INDENT_COLS, MIN_MD_WIDTH),
  })
end

maki.api.register_tool({
  name = "role",
  description = description,
  kind = "execute",
  -- Same audiences as `task`: offered to the main agent and inside workflow
  -- mode, never to a subagent. That is what keeps delegation one level deep.
  audiences = { "main", "workflow" },
  schema = schema,
  handler = handler,
  header = header,
  restore = restore,
})

maki.api.register_command({
  name = "/profile",
  description = "Show or switch the delegation profile (" .. table.concat(profile_names, ", ") .. ")",
  nargs = "?",
  handler = function(opts)
    local wanted = opts.args and opts.args:match("^%s*(%S*)%s*$") or ""
    if wanted == "" then
      maki.ui.flash(
        ("profile %s — %s"):format(active_profile, PROFILES[active_profile].description)
      )
      return
    end
    if not PROFILES[wanted] then
      maki.ui.flash("unknown profile " .. wanted .. "; try " .. table.concat(profile_names, ", "))
      return
    end
    active_profile = wanted
    maki.ui.flash(("profile %s — %s"):format(wanted, PROFILES[wanted].description))
  end,
})

maki.api.register_command({
  name = "/roles",
  description = "List the delegation roles and what the active profile gives each one",
  handler = function()
    local parts = {}
    for _, name in ipairs(role_names) do
      local settings = settings_for(name)
      parts[#parts + 1] = ("%s %s/%s"):format(
        name,
        settings.spec or settings.tier or "inherit",
        settings.thinking or "inherit"
      )
    end
    maki.ui.flash(active_profile .. ": " .. table.concat(parts, "  "))
  end,
})

--- Set the delegation profile the session starts on. Called from init.lua,
--- which the Home Manager module generates; `/profile` overrides it live.
function M.setup(opts)
  opts = opts or {}
  if opts.profile then
    if not PROFILES[opts.profile] then
      maki.log.warn("unknown roles profile: " .. tostring(opts.profile))
    else
      active_profile = opts.profile
    end
  end
end

return M
