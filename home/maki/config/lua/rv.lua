-- rv: a local Jujutsu review as the agent's task list.
--
-- https://github.com/Firaenix/rv reviews the jj stack sitting on disk, before
-- it is a pull request or instead of ever becoming one. Its CLI is already an
-- agent interface, so this plugin is a thin, context-aware shell over it:
-- every rv command returns JSON, and shaping that JSON here is what keeps a
-- twelve-finding review from costing a whole context window.
--
-- Two decisions here are about what the plugin costs rather than what it does,
-- because a tool definition is paid on every request whether or not it is
-- used. Measured with `maki prompt --tools`:
--
--   one tool per rv subcommand   1060 tok/request
--   two action-dispatched tools    ~390 tok/request
--
-- So the read and write channels are one tool each, dispatched on `action`
-- the way the builtin `memory` tool does it. For scale, maki's own `index`
-- tool nets about 165 tokens saved per turn; the six-tool version cost six
-- times that on every request, used or not.
--
-- Registering only inside a jj workspace would drop the rest, but Luau's
-- sandbox has no synchronous filesystem access — `maki.fs` is async and a
-- loading plugin cannot yield, and `io` and `os.rename` are not exposed. So
-- the cost is paid everywhere; `cb.maki.enableRv = false` is the lever for a
-- machine that does not use jj.
--
-- None of these tools declares a permission scope, so they run without a
-- prompt. That is the right call for rv specifically: it opens the repository
-- read-only, never starts a jj transaction, and the only things it writes are
-- `.review/` and one line in `.git/info/exclude`. Resolving is reversible
-- (re-applying reopens), so the worst case is bookkeeping noise, not lost work.

local truncate = require("maki.truncate")
local ToolView = require("maki.tool_view")

local TIMEOUT_MS = 120000
local EXCERPT_LIMIT = 240

local RANGE_PROPERTIES = {
  from = { type = "string", description = "Review starts from this revision (default: trunk())" },
  to = { type = "string", description = "Review ends at this revision (default: @)" },
}

local function with_range(properties)
  local schema = {}
  for name, spec in pairs(RANGE_PROPERTIES) do
    schema[name] = spec
  end
  for name, spec in pairs(properties) do
    schema[name] = spec
  end
  return schema
end

local function limits(ctx)
  return ctx:config("max_output_lines", 2000), ctx:config("max_output_bytes", 51200)
end

local function view_opts(ctx)
  local tol = ctx:tool_output_lines()
  return { max_lines = (tol and tol.other) or 3, keep = "head" }
end

-- Renders the text into a collapsible body, so a long review is one click
-- away in the UI without being pasted into the transcript twice.
local function collapsible(text, ctx)
  local buf = maki.ui.buf()
  local view = ToolView.new(buf, view_opts(ctx))
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    view:append(line)
  end
  view:finish()
  buf:on("click", function()
    view:toggle()
  end)
  return buf
end

local function fail(message)
  return { llm_output = "error: " .. message, is_error = true }
end

-- Runs rv with the global range flags in front of the subcommand, which is
-- the order its CLI wants. Output is accumulated from the stream callbacks
-- rather than read off the job's tail, which is capped at 1024 lines.
local function rv(input, args)
  local argv = { "rv" }
  if input.from then
    argv[#argv + 1] = "--from"
    argv[#argv + 1] = input.from
  end
  if input.to then
    argv[#argv + 1] = "--to"
    argv[#argv + 1] = input.to
  end
  for _, arg in ipairs(args) do
    argv[#argv + 1] = arg
  end

  local stdout, stderr = {}, {}
  local ok, id = pcall(maki.fn.jobstart, argv, {
    on_stdout = function(_, line)
      stdout[#stdout + 1] = line
    end,
    on_stderr = function(_, line)
      stderr[#stderr + 1] = line
    end,
  })
  if not ok or not id then
    return nil, "could not start rv: " .. tostring(id)
  end

  local result = maki.fn.jobwait(id, TIMEOUT_MS)
  if not result then
    maki.fn.jobstop(id)
    return nil, "rv did not finish within " .. (TIMEOUT_MS / 1000) .. "s"
  end

  return {
    stdout = table.concat(stdout, "\n"),
    stderr = table.concat(stderr, "\n"),
    code = result.exit_code,
  }
end

-- rv exits 2 on bad arguments and 1 on execution failure, and says why on
-- stderr. Hand that through verbatim: "not a jj repository" is the whole
-- answer, and paraphrasing it would only cost the model a retry.
local function rv_json(input, args)
  local result, err = rv(input, args)
  if not result then
    return nil, err
  end
  if result.code ~= 0 then
    local message = result.stderr ~= "" and result.stderr or result.stdout
    return nil, message ~= "" and message or ("rv exited " .. tostring(result.code))
  end

  local decoded, decode_err = maki.json.decode(result.stdout)
  if not decoded then
    return nil, "could not parse rv output: " .. tostring(decode_err)
  end
  return decoded
end

local function rv_text(input, args)
  local result, err = rv(input, args)
  if not result then
    return nil, err
  end
  if result.code ~= 0 then
    local message = result.stderr ~= "" and result.stderr or result.stdout
    return nil, message ~= "" and message or ("rv exited " .. tostring(result.code))
  end
  local text = result.stdout
  if text == "" then
    text = result.stderr
  end
  return (text:gsub("%s+$", ""))
end

-- JSON null reaches a maki plugin as nil, but a decoder that uses a sentinel
-- would make every `if field then` guard below true. Normalise once here so
-- the shaping code never has to care which it got.
local function present(value)
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" or kind == "table" then
    return value
  end
  return nil
end

-- rv's line numbers may decode as floats, and `tostring(6.0)` is "6.0".
local function int(value)
  value = present(value)
  if type(value) ~= "number" then
    return nil
  end
  return string.format("%d", value)
end

local function clip(text, limit)
  text = tostring(text or ""):gsub("%s+", " "):gsub("^%s+", "")
  if #text <= limit then
    return text
  end
  return text:sub(1, limit - 1) .. "…"
end

local function shaped(text, ctx)
  local max_lines, max_bytes = limits(ctx)
  return {
    llm_output = truncate(text, max_lines, max_bytes),
    body = collapsible(text, ctx),
  }
end

local function render_status(input, ctx)
  local status, err = rv_json(input, { "status", "--json" })
  if not status then
    return fail(err)
  end

  local counts = present(status.comments) or {}
  local changes = present(status.changes) or {}
  local files = present(status.files) or {}
  local lines = {
    ("revset %s (%d change%s, %d file%s)"):format(
      present(status.revset) or "?",
      #changes,
      #changes == 1 and "" or "s",
      #files,
      #files == 1 and "" or "s"
    ),
    ("comments: %d open, %d awaiting-verification, %d outdated, %d resolved, %d abandoned"):format(
      counts.open or 0,
      counts.awaiting_verification or 0,
      counts.outdated or 0,
      counts.resolved or 0,
      counts.abandoned or 0
    ),
  }

  -- A degraded base means rv could not resolve the range's true merge base, so
  -- the diff may include changes that are not yours. Worth one line.
  if present(status.degraded_base) then
    lines[#lines + 1] = "warning: degraded base, the range may include changes from outside your stack"
  end

  if #changes > 0 then
    lines[#lines + 1] = "changes:"
    for _, change in ipairs(changes) do
      lines[#lines + 1] = ("  %s %s"):format(
        tostring(present(change.change_id) or "?"):sub(1, 12),
        clip(change.description, 80)
      )
    end
  end

  if #files > 0 then
    lines[#lines + 1] = "files:"
    for _, file in ipairs(files) do
      lines[#lines + 1] = ("  %-8s %s%s"):format(
        present(file.kind) or "?",
        present(file.path) or "?",
        present(file.binary) and " (binary)" or ""
      )
    end
  end

  return shaped(table.concat(lines, "\n"), ctx)
end

local function render_comments(input, ctx)
  local args = { "comments", "--json" }
  if input.state then
    args[#args + 1] = "--state"
    args[#args + 1] = input.state
  end

  local comments, err = rv_json(input, args)
  if not comments then
    return fail(err)
  end
  if #comments == 0 then
    return { llm_output = input.state and ("No " .. input.state .. " comments.") or "No comments." }
  end

  local lines = {}
  for _, comment in ipairs(comments) do
    local anchor_tbl = present(comment.anchor) or {}
    local anchor_line = present(anchor_tbl.line)
    local flags = {}
    if present(comment.outdated) then
      flags[#flags + 1] = "outdated"
    end
    -- "exact" is the uninteresting case; anything else means the comment was
    -- re-anchored after an edit and its line is a best guess.
    local confidence = present(comment.confidence)
    if confidence and confidence ~= "exact" then
      flags[#flags + 1] = "anchor:" .. tostring(confidence)
    end
    local settled_by = present(comment.settled_by)
    if settled_by then
      flags[#flags + 1] = "by:" .. tostring(settled_by)
    end

    lines[#lines + 1] = ("[%s] %s %s:%s (%s)%s"):format(
      present(comment.id) or "?",
      present(comment.state) or "?",
      present(anchor_tbl.file) or "?",
      int(comment.resolved_line) or int(anchor_line) or "?",
      present(anchor_tbl.side) or "right",
      #flags > 0 and (" " .. table.concat(flags, " ")) or ""
    )
    lines[#lines + 1] = "  " .. clip(comment.body, EXCERPT_LIMIT)

    -- One line of the anchored source is what makes a finding actionable
    -- without a second read call. The rest of rv's context array is not.
    local context = present(anchor_tbl.context)
    local start = present(anchor_tbl.context_start)
    if context and start and anchor_line then
      local excerpt = present(context[anchor_line - start + 1])
      if excerpt then
        lines[#lines + 1] = ("  %s| %s"):format(int(anchor_line), clip(excerpt, EXCERPT_LIMIT))
      end
    end

    local reply = present(comment.reply)
    if reply then
      lines[#lines + 1] = "  reply: " .. clip(reply, EXCERPT_LIMIT)
    end
  end

  return shaped(table.concat(lines, "\n"), ctx)
end

local function render_diff(input, ctx)
  local args = { "diff" }
  if input.file then
    args[#args + 1] = input.file
  end
  args[#args + 1] = "--json"

  local files, err = rv_json(input, args)
  if not files then
    return fail(err)
  end
  if #files == 0 then
    return { llm_output = "No changes in range." }
  end

  local lines = {}
  for _, file in ipairs(files) do
    local added, removed = 0, 0
    for _, line in ipairs(present(file.lines) or {}) do
      if line.kind == "added" then
        added = added + 1
      elseif line.kind == "removed" then
        removed = removed + 1
      end
    end

    lines[#lines + 1] = ("%s  %s/%s  +%d -%d%s%s"):format(
      present(file.file) or "?",
      present(file.language) or "?",
      present(file.engine) or "?",
      added,
      removed,
      present(file.binary) and "  binary" or "",
      present(file.suppressed) and "  suppressed" or ""
    )

    -- The whole point of naming one file is its line numbers, so only then is
    -- the body worth its tokens.
    if input.file then
      for _, line in ipairs(present(file.lines) or {}) do
        lines[#lines + 1] = ("  %-7s %4s %4s  %s"):format(
          present(line.kind) or "?",
          int(line.left) or "-",
          int(line.right) or "-",
          present(line.text) or ""
        )
      end
    end
  end

  if not input.file then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Pass file= for the line numbers rv_note wants."
  end

  return shaped(table.concat(lines, "\n"), ctx)
end

maki.api.register_tool({
  name = "rv_review",
  kind = "search",
  description = [[Read the local jj review (rv). Start with `status` in a Jujutsu repository.

- `status`: revset, changes, files, comment counts. Open above zero means findings are waiting.
- `comments`: the findings. `state=open` is what still waits on you.
- `diff`: per-file +/- summary; with `file`, the changed lines and the numbers rv_note wants.]],
  schema = {
    type = "object",
    required = { "action" },
    properties = with_range({
      action = {
        type = "string",
        enum = { "status", "comments", "diff" },
        description = "Which view to read",
      },
      state = {
        type = "string",
        enum = { "open", "awaiting-verification", "resolved", "abandoned", "outdated" },
        description = "comments: filter (default: all)",
      },
      file = { type = "string", description = "diff: one file, as status lists it" },
    }),
  },

  header = function(input)
    local buf = maki.ui.buf()
    buf:line({
      { "rv " .. tostring(input.action or "review"), "tool" },
      { input.file and (" " .. input.file) or (input.state and (" " .. input.state) or ""), "dim" },
    })
    return buf
  end,

  restore = function(_input, output, _is_error, ctx)
    return ToolView.restore(output, view_opts(ctx))
  end,

  handler = function(input, ctx)
    local action = input.action
    if action == "status" then
      return render_status(input, ctx)
    elseif action == "comments" then
      return render_comments(input, ctx)
    elseif action == "diff" then
      return render_diff(input, ctx)
    end
    return fail("unknown action: " .. tostring(action) .. " (status, comments, diff)")
  end,
})

maki.api.register_tool({
  name = "rv_note",
  kind = "edit",
  description = [[Write to the local jj review (rv).

- `comment` (file, line, message): record a finding. Take `line` from rv_review diff, not from the file on disk.
- `reply` (id, message): answer one. A second reply replaces the first.
- `resolve` (id): fixed. Reply first, so the record says what was done.
- `abandon` (id): dropped without a fix.

Re-applying resolve or abandon reopens it. Do not resolve what you did not fix.]],
  schema = {
    type = "object",
    required = { "action" },
    properties = with_range({
      action = {
        type = "string",
        enum = { "comment", "reply", "resolve", "abandon" },
        description = "What to write",
      },
      id = { type = "string", description = "Comment id from rv_review" },
      message = { type = "string", description = "The finding, or the answer" },
      file = { type = "string", description = "File to comment on" },
      line = { type = "integer", description = "1-based line in rv's coordinates" },
      side = {
        type = "string",
        enum = { "left", "right" },
        description = "Diff side; left is removed text (default: right)",
      },
    }),
  },

  header = function(input)
    local buf = maki.ui.buf()
    buf:line({
      { "rv " .. tostring(input.action or "note") .. " ", "tool" },
      { tostring(input.id or input.file or ""), "path" },
    })
    return buf
  end,

  handler = function(input)
    local action = input.action
    local args

    if action == "comment" then
      if not input.file or not input.line or not input.message then
        return fail("comment needs file, line and message")
      end
      args = { "comment", input.file, "--line", tostring(input.line), "-m", input.message }
      if input.side then
        args[#args + 1] = "--side"
        args[#args + 1] = input.side
      end
    elseif action == "reply" then
      if not input.id or not input.message then
        return fail("reply needs id and message")
      end
      args = { "reply", input.id, "-m", input.message }
    elseif action == "resolve" or action == "abandon" then
      if not input.id then
        return fail(action .. " needs id")
      end
      args = { action, input.id }
    else
      return fail("unknown action: " .. tostring(action) .. " (comment, reply, resolve, abandon)")
    end

    local text, err = rv_text(input, args)
    if not text then
      return fail(err)
    end
    return { llm_output = text }
  end,
})

maki.api.register_command({
  name = "/rv",
  description = "Show the rv review's range and comment counts",
  handler = function()
    local status, err = rv_json({}, { "status", "--json" })
    if not status then
      maki.ui.flash("rv: " .. clip(err, 120))
      return
    end
    local counts = present(status.comments) or {}
    maki.ui.flash(
      ("rv %s — %d open, %d awaiting, %d resolved, %d file(s)"):format(
        present(status.revset) or "?",
        counts.open or 0,
        counts.awaiting_verification or 0,
        counts.resolved or 0,
        #(present(status.files) or {})
      )
    )
  end,
})

if maki.fn.executable("rv") ~= 1 then
  maki.log.warn("rv is not on PATH; the rv_* tools will fail until it is installed")
end
