-- Show Buildifier diagnostics while editing Bazel files.
local lint_ok, lint = pcall(require, "lint")
if not lint_ok then
	return
end

lint.linters_by_ft = vim.tbl_extend("force", lint.linters_by_ft, {
	bzl = { "buildifier" },
})

local lint_group = vim.api.nvim_create_augroup("custom_buildifier_lint", { clear = true })
vim.api.nvim_create_autocmd({ "FileType", "BufEnter", "BufWritePost", "InsertLeave" }, {
	group = lint_group,
	callback = function(args)
		if vim.bo[args.buf].filetype == "bzl" then
			lint.try_lint(nil, {
				cwd = vim.fs.root(args.buf, { "MODULE.bazel", "WORKSPACE.bazel", "WORKSPACE" }),
			})
		end
	end,
})
