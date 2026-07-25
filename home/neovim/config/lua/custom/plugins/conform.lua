-- ═══════════════════════════════════════════════════════════════════════════════
-- 🧹 CONFORM.NVIM — Formatting on Save
-- ═══════════════════════════════════════════════════════════════════════════════

local ok, conform = pcall(require, "conform")
if not ok then
  return
end

conform.setup({
  formatters_by_ft = {
    python = { "ruff_organize_imports", "ruff_format" },
    awk = { "gawk" },
    bzl = { "buildifier" },
    just = { "just" },
  },

  formatters = {
    gawk = {
      command = "gawk",
      args = { "-f", "-", "-o-" },
      stdin = true,
    },
  },

  -- Use explicit external formatters; no LSP fallback to avoid hangs.
  format_on_save = function(bufnr)
    local filetype = vim.bo[bufnr].filetype
    if filetype == "python" or filetype == "awk" or filetype == "bzl" or filetype == "just" then
      return { lsp_fallback = false, timeout_ms = 2000 }
    end
  end,

  -- Prefer explicit external formatters; do not fallback automatically
  default_format_opts = {
    lsp_fallback = false,
  },
})
