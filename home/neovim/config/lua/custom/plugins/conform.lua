-- ═══════════════════════════════════════════════════════════════════════════════
-- 🧹 CONFORM.NVIM — Formatting on Save (Python via Ruff)
-- ═══════════════════════════════════════════════════════════════════════════════

local ok, conform = pcall(require, "conform")
if not ok then
  return
end

conform.setup({
  -- Only configure Python explicitly; others remain untouched
  formatters_by_ft = {
    python = { "ruff_organize_imports", "ruff_format" },
  },

  -- Only format on save for Python; no LSP fallback to avoid hangs
  format_on_save = function(bufnr)
    if vim.bo[bufnr].filetype == "python" then
      return { lsp_fallback = false, timeout_ms = 2000 }
    end
  end,

  -- Prefer explicit external formatters; do not fallback automatically
  default_format_opts = {
    lsp_fallback = false,
  },
})

