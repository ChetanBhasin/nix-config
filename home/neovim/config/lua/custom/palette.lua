-- Canonical Lua projection of modules/theme/gruvbox-night.nix.
-- Keep literal values here because Neovim's runtime config is shared by the
-- internal and exportable Home Manager modules.

return {
    -- Warm neutral ladder, dark to light.
    base00 = "#1d2021",
    base01 = "#282828",
    base02 = "#3c3836",
    base03 = "#aea089",
    base04 = "#bcae94",
    base05 = "#d0c0a0",
    base06 = "#dfcfaa",
    base07 = "#ebdbb2",

    -- Gruvbox syntax and diagnostic accents.
    base08 = "#db7e75",
    base09 = "#d58a54",
    base0A = "#c9a257",
    base0B = "#a3ad62",
    base0C = "#7fa98a",
    base0D = "#84a9b2",
    base0E = "#c38da0",
    base0F = "#b9916b",

    dim_neutral = "#7c6f64",
    soft_neutral = "#96918a",
    primary_accent = "#c9a257",
    primary_surface = "#38321f",
    border = "#504945",

    signal = "#c9a257",
    ok = "#a3ad62",
    warning = "#c9a257",
    error = "#db7e75",
    info = "#84a9b2",
    hint = "#b9916b",
}
