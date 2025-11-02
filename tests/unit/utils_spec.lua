---Unit tests for utils module
describe("utils module", function()
	local utils
	local config
	local vim_mock

	before_each(function()
		-- Load vim mock
		vim_mock = require("tests.helpers.vim_mock")
		vim_mock.reset()

		-- Load modules
		config = require("gtask.config")
		utils = require("gtask.utils")

		-- Reset config to defaults
		config.reset()
	end)

	describe("notify with verbosity", function()
		it("should show error messages with default verbosity", function()
			vim_mock.clear_notifications()
			config.setup({ verbosity = "error" })

			utils.notify("Error message", vim.log.levels.ERROR)

			local notif = vim_mock.find_notification("Error message")
			assert.is_not_nil(notif)
			assert.equals(vim.log.levels.ERROR, notif.level)
		end)

		it("should not show info messages with default verbosity", function()
			vim_mock.clear_notifications()
			config.setup({ verbosity = "error" })

			utils.notify("Info message", vim.log.levels.INFO)

			local notif = vim_mock.find_notification("Info message")
			assert.is_nil(notif)
		end)

		it("should not show warn messages with error verbosity", function()
			vim_mock.clear_notifications()
			config.setup({ verbosity = "error" })

			utils.notify("Warning message", vim.log.levels.WARN)

			local notif = vim_mock.find_notification("Warning message")
			assert.is_nil(notif)
		end)

		it("should show warn messages with warn verbosity", function()
			vim_mock.clear_notifications()
			config.setup({ verbosity = "warn" })

			utils.notify("Warning message", vim.log.levels.WARN)

			local notif = vim_mock.find_notification("Warning message")
			assert.is_not_nil(notif)
			assert.equals(vim.log.levels.WARN, notif.level)
		end)

		it("should show error messages with warn verbosity", function()
			vim_mock.clear_notifications()
			config.setup({ verbosity = "warn" })

			utils.notify("Error message", vim.log.levels.ERROR)

			local notif = vim_mock.find_notification("Error message")
			assert.is_not_nil(notif)
			assert.equals(vim.log.levels.ERROR, notif.level)
		end)

		it("should not show info messages with warn verbosity", function()
			vim_mock.clear_notifications()
			config.setup({ verbosity = "warn" })

			utils.notify("Info message", vim.log.levels.INFO)

			local notif = vim_mock.find_notification("Info message")
			assert.is_nil(notif)
		end)

		it("should show all messages with info verbosity", function()
			vim_mock.clear_notifications()
			config.setup({ verbosity = "info" })

			utils.notify("Info message", vim.log.levels.INFO)
			utils.notify("Warning message", vim.log.levels.WARN)
			utils.notify("Error message", vim.log.levels.ERROR)

			assert.is_not_nil(vim_mock.find_notification("Info message"))
			assert.is_not_nil(vim_mock.find_notification("Warning message"))
			assert.is_not_nil(vim_mock.find_notification("Error message"))
		end)

		it("should default to INFO level when level not provided", function()
			vim_mock.clear_notifications()
			config.setup({ verbosity = "info" })

			-- Call without level parameter
			utils.notify("Default level message")

			local notif = vim_mock.find_notification("Default level message")
			assert.is_not_nil(notif)
			assert.equals(vim.log.levels.INFO, notif.level)
		end)

		it("should not show messages with default INFO level when verbosity is error", function()
			vim_mock.clear_notifications()
			config.setup({ verbosity = "error" })

			-- Call without level parameter (defaults to INFO)
			utils.notify("Default level message")

			local notif = vim_mock.find_notification("Default level message")
			assert.is_nil(notif)
		end)
	end)

	describe("config verbosity validation", function()
		it("should accept valid verbosity levels", function()
			assert.has_no_errors(function()
				config.setup({ verbosity = "error" })
			end)
			assert.has_no_errors(function()
				config.setup({ verbosity = "warn" })
			end)
			assert.has_no_errors(function()
				config.setup({ verbosity = "info" })
			end)
		end)

		it("should reject invalid verbosity levels", function()
			assert.has_error(function()
				config.setup({ verbosity = "debug" })
			end)
			assert.has_error(function()
				config.setup({ verbosity = "verbose" })
			end)
		end)

		it("should reject non-string verbosity", function()
			assert.has_error(function()
				config.setup({ verbosity = 1 })
			end)
			assert.has_error(function()
				config.setup({ verbosity = true })
			end)
		end)

		it("should have error as default verbosity", function()
			config.setup({})
			assert.equals("error", config.get().verbosity)
		end)
	end)
end)
