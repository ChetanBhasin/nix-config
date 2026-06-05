local M = {}

local state_path = vim.fs.joinpath(vim.fn.stdpath("data"), "rust-linked-projects.json")

local display_colors = {
    fg1 = "#ebdbb2",
    gray = "#928374",
    green = "#b8bb26",
    yellow = "#fabd2f",
    blue = "#83a598",
    aqua = "#8ec07c",
    orange = "#fe8019",
    bg4 = "#7c6f64",
}

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

local function state_root_for_path(path, state)
    path = normalize(path)
    if not path then
        return nil
    end

    state = state or read_state()
    local start = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
    local best_match = nil

    for candidate, entry in pairs(state) do
        if type(entry) == "table" and type(entry.linked_projects) == "table" and is_subpath(start, candidate) then
            if not best_match or #candidate > #best_match then
                best_match = candidate
            end
        end
    end

    return best_match
end

function M.root_for_picker(start)
    start = normalize(start or current_start_path()) or vim.uv.cwd()
    return state_root_for_path(start) or M.find_root(start)
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

local function cargo_manifest_info(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return {}
    end

    local section_name = nil
    local info = {
        has_package = false,
        has_workspace = false,
        package_name = nil,
    }

    for _, line in ipairs(lines) do
        local section = line:match("^%s*%[([^%]]+)%]")
        if section then
            section_name = section
            if section == "package" then
                info.has_package = true
            elseif section == "workspace" then
                info.has_workspace = true
            end
        elseif section_name == "package" then
            local name = line:match('^%s*name%s*=%s*"([^"]+)"')
            if name then
                info.package_name = name
            end

            name = line:match("^%s*name%s*=%s*'([^']+)'")
            if name then
                info.package_name = name
            end
        end
    end

    return info
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

local function tree_indent(entry)
    if entry.depth == 0 then
        return ""
    end

    return string.rep("  ", entry.depth - 1) .. "|-- "
end

local function is_relative_subpath(path, root)
    if root == "." then
        return path ~= "."
    end

    return path ~= root and vim.startswith(path, root .. "/")
end

function M.project_entries(root, projects)
    root = normalize(root or M.find_root())

    local entries = {}
    for _, path in ipairs(projects) do
        local full_path = join_path(root, path)
        local dir = project_dir(path)
        local name = nil
        local kind = "cargo"

        if vim.endswith(path, "Cargo.toml") then
            local info = cargo_manifest_info(full_path)
            -- A workspace-only manifest would make rust-analyzer load every member.
            if info.has_workspace and not info.has_package then
                path = nil
            else
                name = info.package_name
            end
        elseif vim.endswith(path, "rust-project.json") then
            kind = "rust-project"
            name = rust_project_name(full_path)
        end

        if path then
            name = name or fallback_project_name(root, dir)

            table.insert(entries, {
                value = path,
                name = name,
                dir = dir,
                depth = path_depth(dir),
                kind = kind,
                ordinal = table.concat({ name, dir, path, kind }, " "),
            })
        end
    end

    return entries
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

function M.visible_tree_entries(entries, collapsed)
    collapsed = collapsed or {}

    return vim.tbl_filter(function(entry)
        for dir, is_collapsed in pairs(collapsed) do
            if is_collapsed then
                if entry.kind == "group" and is_relative_subpath(entry.dir, dir) then
                    return false
                end

                if entry.kind ~= "group" and (entry.dir == dir or is_relative_subpath(entry.dir, dir)) then
                    return false
                end
            end
        end

        return true
    end, entries)
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

    local valid_projects = list_to_set(vim.tbl_map(function(project)
        return project.value
    end, M.project_entries(state_root, M.discover_projects(state_root))))
    local linked_projects = {}
    for _, rel in ipairs(selected) do
        local path = join_path(state_root, rel)
        if valid_projects[rel] and vim.fn.filereadable(path) == 1 then
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

local function settings_for_reload(project_root, current_settings)
    local settings = vim.deepcopy(current_settings or {})
    local linked_projects, has_override = M.linked_projects_for_settings(project_root)
    local rust_settings = settings["rust-analyzer"]

    if has_override then
        rust_settings = rust_settings or {}
        rust_settings.linkedProjects = linked_projects
        settings["rust-analyzer"] = rust_settings
    elseif rust_settings then
        rust_settings.linkedProjects = nil
    end

    return settings
end

local function selection_for_file(file_name)
    file_name = normalize(file_name)
    if not file_name then
        return nil, M.find_root()
    end

    local state = read_state()
    local state_root = state_root_for_path(file_name, state)
    if state_root then
        local entry = state[state_root]
        return vim.deepcopy(entry.linked_projects), state_root
    end

    local start = vim.fn.isdirectory(file_name) == 1 and file_name or vim.fs.dirname(file_name)
    local root = M.find_root(start)
    return M.get_selected(root)
end

local function selected_contains_file(file_name, state_root, selected)
    file_name = normalize(file_name)
    state_root = normalize(state_root)
    if not file_name or not state_root then
        return false
    end

    local selected_set = list_to_set(selected or {})
    local best_project = nil
    local best_project_root = nil
    local projects = M.project_entries(state_root, M.discover_projects(state_root))

    for _, project in ipairs(projects) do
        local dir = project.dir
        local project_root = dir == "." and state_root or join_path(state_root, dir)
        if is_subpath(file_name, project_root) then
            if not best_project_root or #project_root > #best_project_root then
                best_project = project
                best_project_root = project_root
            end
        end
    end

    return best_project ~= nil and selected_set[best_project.value] == true
end

function M.file_is_selected(file_name, root)
    local selected, state_root
    if root then
        selected, state_root = M.get_selected(root)
    else
        selected, state_root = selection_for_file(file_name)
    end

    if not selected then
        return true, state_root
    end

    return selected_contains_file(file_name, state_root, selected), state_root
end

function M.root_dir_for_file(file_name, default_root_dir)
    local selected, state_root = selection_for_file(file_name)

    if selected then
        if selected_contains_file(file_name, state_root, selected) then
            return state_root
        end
        return nil
    end

    if type(default_root_dir) == "function" then
        local root = default_root_dir(file_name)
        if root then
            return root
        end
    end

    file_name = normalize(file_name)
    if file_name then
        return vim.fs.dirname(file_name)
    end

    return nil
end

local function is_rust_analyzer(client)
    return client and (client.name == "rust_analyzer" or client.name == "rust-analyzer")
end

local function client_root(client)
    local root = client and client.config and client.config.root_dir
    if root then
        return normalize(root)
    end

    local folder = client and client.workspace_folders and client.workspace_folders[1]
    if folder then
        return normalize(folder.name)
    end

    return nil
end

local function client_matches_root(client, root)
    root = normalize(root)
    local root_dir = client_root(client)
    if not root or not root_dir then
        return true
    end

    return root == root_dir or is_subpath(root_dir, root) or is_subpath(root, root_dir)
end

local function rust_analyzer_clients(root)
    local clients = {}
    for _, client in ipairs(vim.lsp.get_clients()) do
        if is_rust_analyzer(client) and client_matches_root(client, root) then
            table.insert(clients, client)
        end
    end
    return clients
end

local function buffer_has_client(bufnr, client_id)
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if client.id == client_id then
            return true
        end
    end
    return false
end

local function is_rust_buffer(bufnr)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        return false
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    return name ~= "" and (vim.bo[bufnr].filetype == "rust" or vim.endswith(name, ".rs"))
end

local function refresh_buffer_attachments(clients)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if is_rust_buffer(bufnr) then
            M.detach_excluded_clients(bufnr)

            local file_name = vim.api.nvim_buf_get_name(bufnr)
            local allowed = M.file_is_selected(file_name)
            if allowed then
                for _, client in ipairs(clients) do
                    if vim.lsp.get_client_by_id(client.id) and not buffer_has_client(bufnr, client.id) then
                        pcall(vim.lsp.buf_attach_client, bufnr, client.id)
                    end
                end
            end
        end
    end
end

function M.detach_client_if_excluded(client, bufnr)
    if not is_rust_analyzer(client) then
        return false
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local file_name = vim.api.nvim_buf_get_name(bufnr)
    local allowed = M.file_is_selected(file_name)
    if allowed then
        return false
    end

    local notify_key = "rust_workspace_detached_" .. tostring(client.id)
    if not vim.b[bufnr][notify_key] then
        vim.b[bufnr][notify_key] = true
        notify("Skipped rust-analyzer for file outside selected linked projects", vim.log.levels.WARN)
    end

    vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) and vim.lsp.get_client_by_id(client.id) then
            pcall(vim.lsp.buf_detach_client, bufnr, client.id)
        end
    end)

    return true
end

function M.detach_excluded_clients(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        M.detach_client_if_excluded(client, bufnr)
    end
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

function M.reload_rust_analyzer(root)
    root = normalize(root or M.root_for_picker())
    local clients = rust_analyzer_clients(root)
    if #clients == 0 then
        return false, false
    end

    local methods = vim.lsp.protocol.Methods or {}
    local method = methods.workspace_didChangeConfiguration or "workspace/didChangeConfiguration"
    local reloaded_clients = {}
    local failed = false

    for _, client in ipairs(clients) do
        local current_settings = client.settings or (client.config and client.config.settings) or {}
        local settings = settings_for_reload(root, current_settings)
        client.config = client.config or {}
        client.settings = settings
        client.config.settings = settings

        local ok, notified = pcall(client.notify, client, method, { settings = settings })
        if ok and notified ~= false then
            table.insert(reloaded_clients, client)
        else
            failed = true
        end
    end

    refresh_buffer_attachments(reloaded_clients)
    return #reloaded_clients > 0, true, failed
end

function M.reload_or_restart_rust_analyzer(root)
    local reloaded, had_clients, failed = M.reload_rust_analyzer(root)

    if reloaded then
        local suffix = failed and "; some clients may still need a restart" or ""
        notify("Saved linked projects and reloaded rust-analyzer workspace config" .. suffix)
        return
    end

    if had_clients then
        notify("rust-analyzer config reload failed; restarting as fallback", vim.log.levels.WARN)
        M.restart_rust_analyzer()
        return
    end

    notify("Saved linked projects; rust-analyzer will use them next time it starts")
end

function M.clear()
    local root = M.find_root()
    local selected, state_root = M.get_selected(root)
    if not selected then
        notify("No linkedProjects override to clear; rust-analyzer was not reloaded")
        return
    end

    M.remove_selected(state_root)
    M.reload_or_restart_rust_analyzer(state_root)
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

function M.setup_highlights()
    vim.api.nvim_set_hl(0, "RustWorkspaceSelected", { fg = display_colors.green, bold = true })
    vim.api.nvim_set_hl(0, "RustWorkspacePartial", { fg = display_colors.yellow, bold = true })
    vim.api.nvim_set_hl(0, "RustWorkspaceUnchecked", { fg = display_colors.gray })
    vim.api.nvim_set_hl(0, "RustWorkspaceGroup", { fg = display_colors.blue, bold = true })
    vim.api.nvim_set_hl(0, "RustWorkspaceProject", { fg = display_colors.fg1 })
    vim.api.nvim_set_hl(0, "RustWorkspacePath", { fg = display_colors.gray })
    vim.api.nvim_set_hl(0, "RustWorkspaceCount", { fg = display_colors.aqua })
    vim.api.nvim_set_hl(0, "RustWorkspaceKind", { fg = display_colors.orange })
    vim.api.nvim_set_hl(0, "RustWorkspaceTree", { fg = display_colors.bg4 })
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

local function selection_marker(entry, selected)
    if entry.kind == "group" then
        local mark, checked, total = group_selection(entry, selected)
        if checked == 0 then
            return mark, "RustWorkspaceUnchecked"
        elseif checked == total then
            return mark, "RustWorkspaceSelected"
        end
        return mark, "RustWorkspacePartial"
    end

    if selected[entry.value] then
        return "[x]", "RustWorkspaceSelected"
    end

    return "[ ]", "RustWorkspaceUnchecked"
end

local function kind_label(entry)
    if entry.kind == "group" then
        return "dir", "RustWorkspaceTree"
    elseif entry.kind == "rust-project" then
        return "json", "RustWorkspaceKind"
    end

    return "crate", "RustWorkspaceKind"
end

local function display_name(entry, collapsed)
    if entry.kind == "group" then
        local expander = collapsed[entry.dir] and "+" or "-"
        return tree_indent(entry) .. expander .. " " .. entry.name .. "/"
    end

    return tree_indent(entry) .. entry.name
end

local function detail_text(entry, selected)
    if entry.kind == "group" then
        local _, checked, total = group_selection(entry, selected)
        if entry.dir == "." then
            return ("%d/%d selected"):format(checked, total), "RustWorkspaceCount"
        end
        return ("%s  %d/%d selected"):format(entry.dir, checked, total), "RustWorkspaceCount"
    end

    return entry.dir, "RustWorkspacePath"
end

local function format_entry(entry, selected, collapsed, displayer)
    local mark, mark_hl = selection_marker(entry, selected)
    local kind, kind_hl = kind_label(entry)
    local name_hl = entry.kind == "group" and "RustWorkspaceGroup" or "RustWorkspaceProject"
    local detail, detail_hl = detail_text(entry, selected)

    return displayer({
        { mark, mark_hl },
        { kind, kind_hl },
        { display_name(entry, collapsed), name_hl },
        { detail, detail_hl },
    })
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

local function make_entry(item, selected, collapsed, displayer)
    return {
        value = item.value,
        display = function()
            return format_entry(item, selected, collapsed, displayer)
        end,
        ordinal = item.ordinal,
        project = item,
    }
end

function M.select()
    local root = M.root_for_picker()
    local projects = M.discover_projects(root)

    if #projects == 0 then
        notify("No Cargo.toml or rust-project.json files found under " .. root, vim.log.levels.WARN)
        return
    end

    local project_entries = M.project_entries(root, projects)
    local entries = M.tree_entries(root, project_entries)
    local collapsed = {}
    local selectable_project_set = list_to_set(vim.tbl_map(function(project)
        return project.value
    end, project_entries))
    local persisted = M.get_selected(root)
    local persisted_had_stale_projects = false
    local selected = {}
    if persisted then
        for _, item in ipairs(persisted) do
            if selectable_project_set[item] then
                selected[item] = true
            else
                persisted_had_stale_projects = true
            end
        end
    else
        selected = vim.deepcopy(selectable_project_set)
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
    local entry_display = require("telescope.pickers.entry_display")
    local displayer = entry_display.create({
        separator = " ",
        items = {
            { width = 3 },
            { width = 5 },
            { width = 44 },
            { remaining = true },
        },
    })

    local function entry_maker(item)
        return make_entry(item, selected, collapsed, displayer)
    end

    local function current_entries()
        return M.visible_tree_entries(entries, collapsed)
    end

    local function refresh(prompt_bufnr)
        local picker = action_state.get_current_picker(prompt_bufnr)
        local row = picker:get_selection_row()
        picker:refresh(finders.new_table({
            results = current_entries(),
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

    local function collapse(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry then
            return
        end

        local item = entry.project
        if item.kind == "group" then
            collapsed[item.dir] = true
            refresh(prompt_bufnr)
        elseif item.dir ~= "." then
            collapsed[item.dir] = true
            refresh(prompt_bufnr)
        end
    end

    local function expand(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry then
            return
        end

        local item = entry.project
        if item.kind ~= "group" then
            return
        end

        collapsed[item.dir] = nil
        refresh(prompt_bufnr)
    end

    local function select_all(prompt_bufnr)
        selected = vim.deepcopy(selectable_project_set)
        refresh(prompt_bufnr)
    end

    local function clear_all(prompt_bufnr)
        selected = {}
        refresh(prompt_bufnr)
    end

    local function apply(prompt_bufnr)
        local linked_projects = sorted_keys(selected)
        actions.close(prompt_bufnr)

        if lists_equal(initial_selected, linked_projects) and not persisted_had_stale_projects then
            notify("Linked projects unchanged; rust-analyzer was not reloaded")
            return
        end

        M.set_selected(root, linked_projects)
        M.reload_or_restart_rust_analyzer(root)
    end

    pickers.new({}, {
        prompt_title = "Rust workspace",
        results_title = relative_to(root, vim.uv.cwd()) == "." and root or relative_to(root, vim.uv.cwd()),
        finder = finders.new_table({
            results = current_entries(),
            entry_maker = entry_maker,
        }),
        previewer = false,
        sorter = conf.generic_sorter({}),
        initial_mode = "normal",
        selection_strategy = "row",
        sorting_strategy = "ascending",
        prompt_prefix = " filter > ",
        selection_caret = "> ",
        entry_prefix = "  ",
        layout_config = {
            width = 0.78,
            height = 0.82,
        },
        attach_mappings = function(prompt_bufnr, map)
            map("n", "<Space>", toggle)
            map("n", "h", collapse)
            map("n", "l", expand)
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
    M.setup_highlights()

    vim.api.nvim_create_user_command("RustWorkspaceSelect", M.select, {
        desc = "Pick rust-analyzer linkedProjects for this repo",
    })
    vim.api.nvim_create_user_command("RustWorkspaceClear", M.clear, {
        desc = "Clear rust-analyzer linkedProjects override for this repo",
    })
    vim.api.nvim_create_user_command("RustWorkspaceStatus", M.status, {
        desc = "Show rust-analyzer linkedProjects override for this repo",
    })

    local group = vim.api.nvim_create_augroup("CustomRustWorkspace", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = M.setup_highlights,
    })
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        callback = function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            M.detach_client_if_excluded(client, args.buf)
        end,
    })
    vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
        group = group,
        pattern = { "*.rs", "rust" },
        callback = function(args)
            M.detach_excluded_clients(args.buf)
        end,
    })
end

return M
