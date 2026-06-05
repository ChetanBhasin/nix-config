local M = {}

local state_path = vim.fs.joinpath(vim.fn.stdpath("data"), "rust-linked-projects.json")

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "Rust workspace" })
end

local function normalize(path)
    if not path or path == "" then
        return nil
    end
    return vim.fs.normalize(path)
end

local function join_path(root, rel)
    return vim.fs.joinpath(root, rel)
end

local function is_subpath(path, root)
    path = normalize(path)
    root = normalize(root)
    if not path or not root then
        return false
    end
    return path == root or vim.startswith(path, root .. "/")
end

local function relative_to(path, root)
    path = normalize(path)
    root = normalize(root)
    if not path or not root then
        return path
    end
    local prefix = root .. "/"
    if path == root then
        return "."
    end
    if vim.startswith(path, prefix) then
        return path:sub(#prefix + 1)
    end
    return path
end

local function sorted_keys(tbl)
    local keys = {}
    for key, enabled in pairs(tbl) do
        if enabled then
            table.insert(keys, key)
        end
    end
    table.sort(keys)
    return keys
end

local function list_to_set(list)
    local set = {}
    for _, item in ipairs(list or {}) do
        set[item] = true
    end
    return set
end

local function lists_equal(left, right)
    if #left ~= #right then
        return false
    end

    for i, item in ipairs(left) do
        if right[i] ~= item then
            return false
        end
    end

    return true
end

local function read_state()
    local ok, lines = pcall(vim.fn.readfile, state_path)
    if not ok or #lines == 0 then
        return {}
    end

    local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
    if not decoded_ok or type(decoded) ~= "table" then
        return {}
    end

    return decoded
end

local function write_state(state)
    vim.fn.mkdir(vim.fn.fnamemodify(state_path, ":h"), "p")
    vim.fn.writefile({ vim.json.encode(state) }, state_path)
end

local function current_start_path()
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname ~= "" then
        return vim.fn.isdirectory(bufname) == 1 and bufname or vim.fs.dirname(bufname)
    end
    return vim.uv.cwd()
end

function M.find_root(start)
    start = normalize(start or current_start_path()) or vim.uv.cwd()

    local vcs = vim.fs.find({ ".jj", ".git" }, {
        path = start,
        upward = true,
        type = "directory",
        limit = 1,
    })
    if vcs[1] then
        return normalize(vim.fs.dirname(vcs[1]))
    end

    local rust_project = vim.fs.find({ "Cargo.toml", "rust-project.json" }, {
        path = start,
        upward = true,
        type = "file",
        limit = 1,
    })
    if rust_project[1] then
        return normalize(vim.fs.dirname(rust_project[1]))
    end

    return normalize(vim.uv.cwd())
end

local function resolve_state_root(root, state)
    local normalized_root = normalize(root) or M.find_root()
    state = state or read_state()

    if state[normalized_root] then
        return normalized_root
    end

    local best_match = nil
    for candidate, entry in pairs(state) do
        if type(entry) == "table" and type(entry.linked_projects) == "table" and is_subpath(normalized_root, candidate) then
            if not best_match or #candidate > #best_match then
                best_match = candidate
            end
        end
    end

    return best_match or normalized_root
end

function M.discover_projects(root)
    root = normalize(root or M.find_root())
    if not root then
        return {}
    end

    local files = {}
    if vim.fn.executable("rg") == 1 then
        local result = vim.system({
            "rg",
            "--files",
            "--hidden",
            "-g",
            "Cargo.toml",
            "-g",
            "rust-project.json",
            "-g",
            "!target/**",
            "-g",
            "!.git/**",
            "-g",
            "!.jj/**",
        }, { cwd = root, text = true }):wait()

        if result.code == 0 and result.stdout ~= "" then
            files = vim.split(result.stdout, "\n", { trimempty = true })
        end
    else
        files = vim.fn.globpath(root, "**/Cargo.toml", false, true)
        vim.list_extend(files, vim.fn.globpath(root, "**/rust-project.json", false, true))
        files = vim.tbl_map(function(path)
            return relative_to(path, root)
        end, files)
    end

    files = vim.tbl_filter(function(path)
        return path ~= nil
            and path ~= ""
            and not path:match("^target/")
            and not path:match("/target/")
            and not path:match("^%.git/")
            and not path:match("^%.jj/")
    end, files)

    table.sort(files)
    return files
end

local function cargo_package_name(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return nil
    end

    local in_package = false
    for _, line in ipairs(lines) do
        local section = line:match("^%s*%[([^%]]+)%]")
        if section then
            in_package = section == "package"
        elseif in_package then
            local name = line:match('^%s*name%s*=%s*"([^"]+)"')
            if name then
                return name
            end

            name = line:match("^%s*name%s*=%s*'([^']+)'")
            if name then
                return name
            end
        end
    end

    return nil
end

local function rust_project_name(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return nil
    end

    local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
    if not decoded_ok or type(decoded) ~= "table" or type(decoded.crates) ~= "table" then
        return nil
    end

    local first_crate = decoded.crates[1]
    if type(first_crate) ~= "table" then
        return nil
    end

    return first_crate.display_name or first_crate.name
end

local function project_dir(path)
    local dir = vim.fs.dirname(path)
    if dir == "." or dir == nil then
        return "."
    end
    return dir
end

local function path_depth(path)
    if path == "." then
        return 0
    end

    local _, count = path:gsub("/", "")
    return count + 1
end

local function parent_dir(path)
    if path == "." then
        return nil
    end

    local parent = vim.fs.dirname(path)
    if not parent or parent == "" or parent == "." then
        return "."
    end
    return parent
end

local function fallback_project_name(root, dir)
    if dir == "." then
        return vim.fs.basename(root) or "workspace"
    end
    return vim.fs.basename(dir) or dir
end

local function tree_prefix(entry)
    if entry.depth == 0 then
        return ""
    end

    return string.rep("  ", entry.depth - 1) .. "|-- "
end

function M.project_entries(root, projects)
    root = normalize(root or M.find_root())

    return vim.tbl_map(function(path)
        local full_path = join_path(root, path)
        local dir = project_dir(path)
        local name = nil
        local kind = "cargo"

        if vim.endswith(path, "Cargo.toml") then
            name = cargo_package_name(full_path)
        elseif vim.endswith(path, "rust-project.json") then
            kind = "rust-project"
            name = rust_project_name(full_path)
        end

        name = name or fallback_project_name(root, dir)

        return {
            value = path,
            name = name,
            dir = dir,
            depth = path_depth(dir),
            kind = kind,
            ordinal = table.concat({ name, dir, path, kind }, " "),
        }
    end, projects)
end

function M.tree_entries(root, projects)
    root = normalize(root or M.find_root())

    local groups = {}
    local projects_by_dir = {}

    local function ensure_group(dir)
        dir = dir or "."

        if groups[dir] then
            return groups[dir]
        end

        local parent = parent_dir(dir)
        local group = {
            kind = "group",
            value = "__group__:" .. dir,
            name = fallback_project_name(root, dir),
            dir = dir,
            depth = path_depth(dir),
            children = {},
            subgroups = {},
            ordinal = table.concat({ fallback_project_name(root, dir), dir, "folder" }, " "),
        }

        groups[dir] = group

        if parent then
            ensure_group(parent).subgroups[dir] = true
        end

        return group
    end

    ensure_group(".")

    for _, project in ipairs(projects) do
        ensure_group(project.dir)
        projects_by_dir[project.dir] = projects_by_dir[project.dir] or {}
        table.insert(projects_by_dir[project.dir], project)

        local group_dir = project.dir
        while group_dir do
            table.insert(ensure_group(group_dir).children, project.value)
            group_dir = parent_dir(group_dir)
        end
    end

    local function sorted_group_dirs(subgroups)
        local dirs = vim.tbl_keys(subgroups)
        table.sort(dirs)
        return dirs
    end

    local function sorted_projects(dir)
        local dir_projects = projects_by_dir[dir] or {}
        table.sort(dir_projects, function(left, right)
            if left.name ~= right.name then
                return left.name < right.name
            end
            return left.value < right.value
        end)
        return dir_projects
    end

    local rows = {}
    local function emit_group(dir)
        local group = groups[dir]
        table.sort(group.children)
        group.ordinal = table.concat({ group.name, group.dir, table.concat(group.children, " ") }, " ")
        table.insert(rows, group)

        for _, subgroup in ipairs(sorted_group_dirs(group.subgroups)) do
            emit_group(subgroup)
        end

        for _, project in ipairs(sorted_projects(dir)) do
            local entry = vim.deepcopy(project)
            entry.kind = "project"
            entry.depth = group.depth + 1
            table.insert(rows, entry)
        end
    end

    emit_group(".")
    return rows
end

function M.get_selected(root)
    local state = read_state()
    local state_root = resolve_state_root(root or M.find_root(), state)
    local entry = state[state_root]
    if type(entry) ~= "table" or type(entry.linked_projects) ~= "table" then
        return nil, state_root
    end
    return vim.deepcopy(entry.linked_projects), state_root
end

function M.set_selected(root, linked_projects)
    root = normalize(root or M.find_root())
    local state = read_state()

    state[root] = {
        linked_projects = linked_projects,
        updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    write_state(state)
end

function M.remove_selected(root)
    root = normalize(root or M.find_root())
    local state = read_state()
    state[root] = nil

    write_state(state)
end

function M.linked_projects_for_settings(project_root)
    local selected, state_root = M.get_selected(project_root)
    if not selected then
        return {}, false
    end

    local linked_projects = {}
    for _, rel in ipairs(selected) do
        local path = join_path(state_root, rel)
        if vim.fn.filereadable(path) == 1 then
            table.insert(linked_projects, path)
        end
    end
    return linked_projects, true
end

function M.apply_settings(project_root, default_settings)
    local settings = vim.deepcopy(default_settings or {})
    local linked_projects, has_override = M.linked_projects_for_settings(project_root)

    if has_override then
        settings["rust-analyzer"] = settings["rust-analyzer"] or {}
        settings["rust-analyzer"].linkedProjects = linked_projects
    end

    return settings
end

function M.restart_rust_analyzer()
    local names = {}
    for _, client in ipairs(vim.lsp.get_clients()) do
        if client.name == "rust_analyzer" or client.name == "rust-analyzer" then
            names[client.name] = true
        end
    end

    local restarted = false
    for name in pairs(names) do
        vim.cmd.lsp({ "restart", name })
        restarted = true
    end

    if restarted then
        notify("Saved linked projects and restarted rust-analyzer")
    else
        notify("Saved linked projects; rust-analyzer will use them next time it starts")
    end
end

function M.clear()
    local root = M.find_root()
    local selected = M.get_selected(root)
    if not selected then
        notify("No linkedProjects override to clear; rust-analyzer was not restarted")
        return
    end

    M.remove_selected(root)
    M.restart_rust_analyzer()
end

function M.status()
    local selected, state_root = M.get_selected(M.find_root())
    if not selected then
        notify("No linkedProjects override; rust-analyzer will auto-discover projects")
        return
    end
    if #selected == 0 then
        notify("linkedProjects override for " .. state_root .. ": no projects selected")
        return
    end
    notify(("linkedProjects override for %s:\n%s"):format(state_root, table.concat(selected, "\n")))
end

local function group_selection(entry, selected)
    local total = #(entry.children or {})
    local checked = 0

    for _, child in ipairs(entry.children or {}) do
        if selected[child] then
            checked = checked + 1
        end
    end

    if checked == 0 then
        return "[ ]", checked, total
    elseif checked == total then
        return "[x]", checked, total
    end

    return "[-]", checked, total
end

local function format_entry(entry, selected)
    if entry.kind == "group" then
        local mark, checked, total = group_selection(entry, selected)
        local tree_name = tree_prefix(entry) .. entry.name .. "/"
        local detail = entry.dir == "." and ("%d/%d projects"):format(checked, total)
            or ("%s  %d/%d projects"):format(entry.dir, checked, total)

        return string.format("%s %-42s %s", mark, tree_name, detail)
    end

    local mark = selected[entry.value] and "[x]" or "[ ]"
    local tree_name = tree_prefix(entry) .. entry.name

    return string.format("%s %-42s %s", mark, tree_name, entry.dir)
end

local function toggle_entry_selection(entry, selected)
    if entry.kind == "group" then
        local _, checked, total = group_selection(entry, selected)
        local enable = checked ~= total

        for _, child in ipairs(entry.children or {}) do
            selected[child] = enable or nil
        end
        return
    end

    if selected[entry.value] then
        selected[entry.value] = nil
    else
        selected[entry.value] = true
    end
end

M.toggle_entry_selection = toggle_entry_selection

local function make_entry(item, selected)
    return {
        value = item.value,
        display = function()
            return format_entry(item, selected)
        end,
        ordinal = item.ordinal,
        project = item,
    }
end

function M.select()
    local root = M.find_root()
    local projects = M.discover_projects(root)

    if #projects == 0 then
        notify("No Cargo.toml or rust-project.json files found under " .. root, vim.log.levels.WARN)
        return
    end

    local project_entries = M.project_entries(root, projects)
    local entries = M.tree_entries(root, project_entries)
    local project_set = list_to_set(projects)
    local persisted = M.get_selected(root)
    local selected = {}
    if persisted then
        for _, item in ipairs(persisted) do
            if project_set[item] then
                selected[item] = true
            end
        end
    else
        selected = vim.deepcopy(project_set)
    end
    local initial_selected = sorted_keys(selected)

    local ok, pickers = pcall(require, "telescope.pickers")
    if not ok then
        notify("Telescope is not available", vim.log.levels.ERROR)
        return
    end

    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local function entry_maker(item)
        return make_entry(item, selected)
    end

    local function refresh(prompt_bufnr)
        local picker = action_state.get_current_picker(prompt_bufnr)
        local row = picker:get_selection_row()
        picker:refresh(finders.new_table({
            results = entries,
            entry_maker = entry_maker,
        }), { reset_prompt = false })
        vim.schedule(function()
            if picker.results_win and vim.api.nvim_win_is_valid(picker.results_win) and row then
                picker:set_selection(row)
            end
        end)
    end

    local function toggle(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry then
            return
        end
        toggle_entry_selection(entry.project, selected)
        refresh(prompt_bufnr)
    end

    local function select_all(prompt_bufnr)
        selected = list_to_set(projects)
        refresh(prompt_bufnr)
    end

    local function clear_all(prompt_bufnr)
        selected = {}
        refresh(prompt_bufnr)
    end

    local function apply(prompt_bufnr)
        local linked_projects = sorted_keys(selected)
        actions.close(prompt_bufnr)

        if lists_equal(initial_selected, linked_projects) then
            notify("Linked projects unchanged; rust-analyzer was not restarted")
            return
        end

        M.set_selected(root, linked_projects)
        M.restart_rust_analyzer()
    end

    pickers.new({}, {
        prompt_title = "Rust projects: j/k move, i search, Space toggle subtree, Enter apply",
        results_title = relative_to(root, vim.uv.cwd()) == "." and root or "Cargo projects",
        finder = finders.new_table({
            results = entries,
            entry_maker = entry_maker,
        }),
        sorter = conf.generic_sorter({}),
        initial_mode = "normal",
        selection_strategy = "row",
        attach_mappings = function(prompt_bufnr, map)
            map("n", "<Space>", toggle)
            map({ "i", "n" }, "<Tab>", toggle)
            map({ "i", "n" }, "<CR>", apply)
            map({ "i", "n" }, "<C-a>", select_all)
            map({ "i", "n" }, "<C-x>", clear_all)
            map("n", "/", function()
                vim.cmd("startinsert")
            end)
            return true
        end,
    }):find()
end

function M.setup()
    if M._setup_done then
        return
    end
    M._setup_done = true

    vim.api.nvim_create_user_command("RustWorkspaceSelect", M.select, {
        desc = "Pick rust-analyzer linkedProjects for this repo",
    })
    vim.api.nvim_create_user_command("RustWorkspaceClear", M.clear, {
        desc = "Clear rust-analyzer linkedProjects override for this repo",
    })
    vim.api.nvim_create_user_command("RustWorkspaceStatus", M.status, {
        desc = "Show rust-analyzer linkedProjects override for this repo",
    })
end

return M
