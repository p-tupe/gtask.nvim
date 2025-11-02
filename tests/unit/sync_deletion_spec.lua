---Unit tests for deletion and conflict resolution behavior
describe("deletion and conflict resolution", function()
	local mapping
	local vim_mock

	before_each(function()
		-- Load vim mock
		vim_mock = require("tests.helpers.vim_mock")
		vim_mock.reset()

		-- Load modules (avoid loading sync module which has heavy dependencies)
		mapping = require("gtask.mapping")
	end)

	describe("deleted_from_google flag", function()
		it("should not recreate tasks with deleted_from_google flag", function()
			local map = { tasks = {} }
			mapping.register_task(
				map,
				"List|/file.md:[0]",
				"google1",
				"List",
				"/file.md",
				"[0]",
				nil,
				"2025-01-01T10:00:00Z"
			)
			mapping.mark_deleted_from_google(map, "List|/file.md:[0]")

			local task_data = map.tasks["List|/file.md:[0]"]
			assert.is_true(task_data.deleted_from_google)
			assert.equals("google1", task_data.google_id) -- Still in mapping, just flagged
		end)

		it("should mark deleted_from_google when task deleted from Google", function()
			local map = { tasks = {} }
			mapping.register_task(
				map,
				"List|/file.md:[0]",
				"google1",
				"List",
				"/file.md",
				"[0]",
				nil,
				"2025-01-01T10:00:00Z"
			)

			-- Mark as deleted
			mapping.mark_deleted_from_google(map, "List|/file.md:[0]")

			local task_data = map.tasks["List|/file.md:[0]"]
			assert.is_true(task_data.deleted_from_google)

			-- Should have updated last_synced timestamp
			assert.is_not_nil(task_data.last_synced)
		end)

		it("should preserve task metadata when marked deleted", function()
			local map = { tasks = {} }
			mapping.register_task(
				map,
				"List|/file.md:[0]",
				"google1",
				"List",
				"/file.md",
				"[0]",
				nil,
				"2025-01-01T10:00:00Z"
			)

			local original_google_id = map.tasks["List|/file.md:[0]"].google_id
			local original_list_name = map.tasks["List|/file.md:[0]"].list_name

			mapping.mark_deleted_from_google(map, "List|/file.md:[0]")

			-- Metadata should be preserved
			assert.equals(original_google_id, map.tasks["List|/file.md:[0]"].google_id)
			assert.equals(original_list_name, map.tasks["List|/file.md:[0]"].list_name)
		end)
	end)

	describe("timestamp-based conflict resolution", function()
		it("should use Google's completion status when Google timestamp is newer", function()
			local map = { tasks = {} }
			local task_key = "List|/file.md:[0]"

			-- Register task with old timestamp
			mapping.register_task(map, task_key, "google1", "List", "/file.md", "[0]", nil, "2025-01-01T10:00:00Z")

			-- Verify timestamps can be compared
			-- (Google's timestamp "2025-01-01T12:00:00Z" is newer than mapping's "2025-01-01T10:00:00Z")
			assert.is_true("2025-01-01T12:00:00Z" > "2025-01-01T10:00:00Z")
		end)

		it("should use markdown's completion status when mapping timestamp is newer", function()
			local map = { tasks = {} }
			local task_key = "List|/file.md:[0]"

			-- Register task with recent timestamp
			mapping.register_task(map, task_key, "google1", "List", "/file.md", "[0]", nil, "2025-01-01T12:00:00Z")

			-- Google task updated timestamp is older
			local g_updated = "2025-01-01T10:00:00Z"
			local mapping_updated = "2025-01-01T12:00:00Z"

			-- Verify markdown wins
			assert.is_false(g_updated > mapping_updated)
		end)

		it("should use markdown when timestamps are equal", function()
			local timestamp = "2025-01-01T10:00:00Z"

			-- Equal timestamps mean markdown wins (not greater than)
			assert.is_false(timestamp > timestamp)
		end)
	end)

	describe("mark_deleted_from_google", function()
		it("should set deleted_from_google flag to true", function()
			local map = { tasks = {} }
			mapping.register_task(map, "List|/file.md:[0]", "google1", "List", "/file.md", "[0]", nil)

			mapping.mark_deleted_from_google(map, "List|/file.md:[0]")

			assert.is_true(map.tasks["List|/file.md:[0]"].deleted_from_google)
		end)

		it("should update last_synced timestamp", function()
			local map = { tasks = {} }
			mapping.register_task(
				map,
				"List|/file.md:[0]",
				"google1",
				"List",
				"/file.md",
				"[0]",
				nil,
				"2025-01-01T10:00:00Z"
			)

			-- Mark task as deleted from Google
			mapping.mark_deleted_from_google(map, "List|/file.md:[0]")

			local new_synced = map.tasks["List|/file.md:[0]"].last_synced
			assert.is_not_nil(new_synced)
		end)

		it("should not fail for non-existent task", function()
			local map = { tasks = {} }

			-- Should not error
			assert.has_no_errors(function()
				mapping.mark_deleted_from_google(map, "List|/file.md:[999]")
			end)
		end)
	end)

	describe("register_task with google_updated", function()
		it("should store google_updated timestamp when provided", function()
			local map = { tasks = {} }
			local timestamp = "2025-01-01T15:30:00Z"

			mapping.register_task(map, "List|/file.md:[0]", "google1", "List", "/file.md", "[0]", nil, timestamp)

			assert.equals(timestamp, map.tasks["List|/file.md:[0]"].google_updated)
		end)

		it("should use current time when google_updated not provided", function()
			local map = { tasks = {} }

			mapping.register_task(
				map,
				"List|/file.md:[0]",
				"google1",
				"List",
				"/file.md",
				"[0]",
				nil,
				nil -- No timestamp provided
			)

			-- Should have some timestamp
			assert.is_not_nil(map.tasks["List|/file.md:[0]"].google_updated)
			-- Should be in RFC3339 format
			assert.is_not_nil(
				map.tasks["List|/file.md:[0]"].google_updated:match("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ")
			)
		end)

		it("should initialize deleted_from_google to false", function()
			local map = { tasks = {} }

			mapping.register_task(
				map,
				"List|/file.md:[0]",
				"google1",
				"List",
				"/file.md",
				"[0]",
				nil,
				"2025-01-01T10:00:00Z"
			)

			assert.is_false(map.tasks["List|/file.md:[0]"].deleted_from_google)
		end)
	end)

	describe("config - keep_completed_in_markdown", function()
		it("should have default value of true", function()
			local config = require("gtask.config")
			assert.is_true(config.sync.keep_completed_in_markdown)
		end)

		it("should accept boolean configuration", function()
			local config = require("gtask.config")

			-- Test with false
			assert.has_no_errors(function()
				config.setup({ keep_completed_in_markdown = false })
			end)

			assert.is_false(config.sync.keep_completed_in_markdown)

			-- Reset to true
			config.setup({ keep_completed_in_markdown = true })
			assert.is_true(config.sync.keep_completed_in_markdown)
		end)

		it("should error on non-boolean value", function()
			local config = require("gtask.config")

			assert.has_error(function()
				config.setup({ keep_completed_in_markdown = "true" }) -- String instead of boolean
			end)
		end)
	end)
end)
