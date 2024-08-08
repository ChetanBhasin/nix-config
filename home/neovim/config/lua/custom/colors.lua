function DefineColors(scheme)
    -- Let's set a default color scheme
    local color_scheme = scheme or "catppuccin-mocha"
    -- Apply the color scheme
    vim.cmd.colorscheme(color_scheme)

    -- Set the background to transparent
    vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
    -- Set the background to transparent for floating windows
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
end

require("catppuccin").setup {
    highlight_overrides = {
        mocha = function(C)
            return {
                NvimTreeNormal = { bg = C.none },
                CmpBorder = { fg = C.surface2 },
                Pmenu = { bg = C.none },
                NormalFloat = { bg = C.none },
                TelescopeBorder = { link = "FloatBorder" }
            }
        end
    },
    integrations = {
        cmp = true,
        telescope = true,
        gitsigns = true,
        nvimtree = true,
        treesitter = true,
        treesitter_context = true,
    }
}
