-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎨 COLORIZER CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

require('colorizer').setup({
    filetypes = {
        -- Specific file types with custom options
        'css',
        'scss',
        'sass',
        'html',
        'javascript',
        'typescript',
        'jsx',
        'tsx',
        'vue',
        'svelte',
        'lua',
        'conf',
        'config',
        'dosini',
        'yaml',
        'json',
        'toml',
        'vim',
    },
    user_default_options = {
        RGB = true, -- #RGB hex codes
        RRGGBB = true, -- #RRGGBB hex codes
        names = true, -- "Name" codes like Blue or blue
        RRGGBBAA = true, -- #RRGGBBAA hex codes
        AARRGGBB = false, -- 0xAARRGGBB hex codes
        rgb_fn = true, -- CSS rgb() and rgba() functions
        hsl_fn = true, -- CSS hsl() and hsla() functions
        css = true, -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
        css_fn = true, -- Enable all CSS *functions*: rgb_fn, hsl_fn
        mode = "background", -- Set the display mode: foreground, background, virtualtext
        tailwind = "both", -- Enable tailwind colors: true/false/"normal"/"lsp"/"both"
        sass = { enable = true, parsers = { "css" } }, -- Enable sass colors
        virtualtext = "■", -- Character to show for virtualtext mode
        always_update = true -- Update color values even if buffer is not focused
    },
    -- all the sub-options of filetypes apply to buftypes
    buftypes = {},
})
