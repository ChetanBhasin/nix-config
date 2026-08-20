-- ═══════════════════════════════════════════════════════════════════════════════
-- 🌳 TREESITTER CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

local status_ok, treesitter = pcall(require, "nvim-treesitter")
if not status_ok then
    vim.notify("Failed to load nvim-treesitter", vim.log.levels.ERROR)
    return
end

treesitter.setup({})

local max_filesize = 100 * 1024 -- 100 KB
local problematic_filetypes = {
    alpha = true,
    dashboard = true,
    NvimTree = true,
    ["neo-tree"] = true,
    help = true,
    qf = true,
    lspinfo = true,
    Trouble = true,
    trouble = true,
    lazy = true,
    mason = true,
    TelescopePrompt = true,
    toggleterm = true,
    lazyterm = true,
    floaterm = true,
}
local excluded_buftypes = {
    nofile = true,
    prompt = true,
    popup = true,
    terminal = true,
}

local function should_disable(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return true
    end

    if problematic_filetypes[vim.bo[bufnr].filetype] or excluded_buftypes[vim.bo[bufnr].buftype] then
        return true
    end

    local path = vim.api.nvim_buf_get_name(bufnr)
    local stats = path ~= "" and vim.uv.fs_stat(path) or nil
    return stats ~= nil and stats.size > max_filesize
end

local group = vim.api.nvim_create_augroup("CustomTreesitter", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(args)
        local bufnr = args.buf
        if should_disable(bufnr) then
            return
        end

        local filetype = vim.bo[bufnr].filetype
        local language = vim.treesitter.language.get_lang(filetype) or filetype
        local started = pcall(vim.treesitter.start, bufnr, language)
        if not started or filetype == "python" or filetype == "yaml" then
            return
        end

        local has_indent_query, indent_query = pcall(vim.treesitter.query.get, language, "indents")
        if has_indent_query and indent_query then
            vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
    end,
    desc = "Enable Tree-sitter highlighting and indentation when supported",
})

-- nvim-treesitter's rewrite removed its incremental-selection module. Keep the
-- familiar keys with Neovim's native TSNode API and a small per-buffer stack.
local selection_state = {}

local function select_node(node)
    if not node then
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local start_row, start_col, end_row, end_col = node:range()
    if end_col > 0 then
        end_col = end_col - 1
    elseif end_row > start_row then
        end_row = end_row - 1
        local line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ""
        end_col = math.max(#line - 1, 0)
    end

    local escape = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(escape, "nx", false)
    vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col })
end

local function initial_selection()
    local bufnr = vim.api.nvim_get_current_buf()
    local filetype = vim.bo[bufnr].filetype
    local language = vim.treesitter.language.get_lang(filetype) or filetype
    local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr, language)
    if not parser_ok or not pcall(parser.parse, parser) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local node = vim.treesitter.get_node({
        bufnr = bufnr,
        lang = language,
        pos = { cursor[1] - 1, cursor[2] },
    })
    if not node then
        return
    end

    selection_state[bufnr] = { node }
    select_node(node)
end

local function grow_selection(scope_only)
    local bufnr = vim.api.nvim_get_current_buf()
    local stack = selection_state[bufnr]
    if not stack or not stack[#stack] then
        initial_selection()
        return
    end

    local node = stack[#stack]:parent()
    if scope_only and node then
        local filetype = vim.bo[bufnr].filetype
        local language = vim.treesitter.language.get_lang(filetype) or filetype
        local query_ok, locals_query = pcall(vim.treesitter.query.get, language, "locals")

        if query_ok and locals_query then
            while node do
                local is_scope = false
                local start_row, _, end_row = node:range()
                for id, capture in locals_query:iter_captures(node, bufnr, start_row, end_row + 1) do
                    if locals_query.captures[id] == "local.scope" and capture:equal(node) then
                        is_scope = true
                        break
                    end
                end
                if is_scope then
                    break
                end
                node = node:parent()
            end
        end
    end

    if node then
        table.insert(stack, node)
        select_node(node)
    end
end

local function shrink_selection()
    local bufnr = vim.api.nvim_get_current_buf()
    local stack = selection_state[bufnr]
    if not stack or #stack <= 1 then
        return
    end

    table.remove(stack)
    select_node(stack[#stack])
end

vim.keymap.set("n", "gnn", initial_selection, { desc = "Start Tree-sitter selection" })
vim.keymap.set("x", "grn", function()
    grow_selection(false)
end, { desc = "Grow Tree-sitter selection" })
vim.keymap.set("x", "grc", function()
    grow_selection(true)
end, { desc = "Grow Tree-sitter selection to scope" })
vim.keymap.set("x", "grm", shrink_selection, { desc = "Shrink Tree-sitter selection" })

vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
        selection_state[args.buf] = nil
    end,
})

-- Rainbow delimiters and nvim-autopairs configure their own Tree-sitter use.
