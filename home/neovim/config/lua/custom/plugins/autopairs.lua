-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔗 NVIM-AUTOPAIRS CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Auto-close brackets with treesitter awareness

local ok, autopairs = pcall(require, "nvim-autopairs")
if not ok then
    return
end

autopairs.setup({
    check_ts = true, -- Enable treesitter
    ts_config = {
        lua = { "string", "source" }, -- Don't add pairs in lua string treesitter nodes
        javascript = { "string", "template_string" },
        typescript = { "string", "template_string" },
        java = false, -- Don't check treesitter on java
    },
    disable_filetype = { "TelescopePrompt", "spectre_panel" },
    disable_in_macro = true, -- Disable when recording/executing macros
    disable_in_visualblock = false, -- Disable when in visual block mode
    disable_in_replace_mode = true,
    ignored_next_char = [=[[%w%%%'%[%"%.%`%$]]=],
    enable_moveright = true,
    enable_afterquote = true, -- Add bracket pairs after quote
    enable_check_bracket_line = true, -- Check bracket in same line
    enable_bracket_in_quote = true,
    enable_abbr = false, -- Trigger abbreviation
    break_undo = true, -- Switch for basic rule break undo sequence
    map_cr = true, -- Map <CR> to complete pair
    map_bs = true, -- Map <BS> to delete pair
    map_c_h = false, -- Map <C-h> to delete pair
    map_c_w = false, -- Map <C-w> to delete a pair if possible

    -- Fast wrap configuration
    fast_wrap = {
        map = "<M-e>", -- Alt+e to trigger fast wrap
        chars = { "{", "[", "(", '"', "'" },
        pattern = [=[[%'%"%>%]%)%}%,]]=],
        end_key = "$",
        before_key = "h",
        after_key = "l",
        cursor_pos_before = true,
        keys = "qwertyuiopzxcvbnmasdfghjkl",
        manual_position = true,
        highlight = "Search",
        highlight_grey = "Comment",
    },
})

-- nvim-cmp integration: Insert '(' after selecting function/method
local cmp_ok, cmp = pcall(require, "cmp")
if cmp_ok then
    local cmp_autopairs = require("nvim-autopairs.completion.cmp")
    cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
end

-- Treesitter integration rules
local Rule = require("nvim-autopairs.rule")
local npairs = require("nvim-autopairs")
local cond = require("nvim-autopairs.conds")

-- Add spaces between parentheses
npairs.add_rules({
    Rule(" ", " ")
        :with_pair(function(opts)
            local pair = opts.line:sub(opts.col - 1, opts.col)
            return vim.tbl_contains({ "()", "[]", "{}" }, pair)
        end)
        :with_move(cond.none())
        :with_cr(cond.none())
        :with_del(function(opts)
            local col = vim.api.nvim_win_get_cursor(0)[2]
            local context = opts.line:sub(col - 1, col + 2)
            return vim.tbl_contains({ "(  )", "[  ]", "{  }" }, context)
        end),
    Rule("", " )")
        :with_pair(cond.none())
        :with_move(function(opts)
            return opts.char == ")"
        end)
        :with_cr(cond.none())
        :with_del(cond.none())
        :use_key(")"),
    Rule("", " ]")
        :with_pair(cond.none())
        :with_move(function(opts)
            return opts.char == "]"
        end)
        :with_cr(cond.none())
        :with_del(cond.none())
        :use_key("]"),
    Rule("", " }")
        :with_pair(cond.none())
        :with_move(function(opts)
            return opts.char == "}"
        end)
        :with_cr(cond.none())
        :with_del(cond.none())
        :use_key("}"),
})
