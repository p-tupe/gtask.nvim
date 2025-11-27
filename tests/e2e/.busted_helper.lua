-- Auto-generated E2E test helper
package.path = '/Users/pritesh/Projects/gtask.nvim/lua/?.lua;' .. package.path

-- Initialize plugin
require('gtask').setup({
	markdown_dir = vim.fn.expand('~/gtask-e2e-test'),
	verbosity = 'info',
})
