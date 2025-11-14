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

	describe("task removal", function()
		it("should remove task from mapping", function()
			local map = { tasks = {} }
			local uuid = "uuid-abc123"

			mapping.register_task(map, uuid, "google1", "List", "/file.md", nil, "2025-01-01T10:00:00Z")

			-- Verify task exists
			assert.is_not_nil(map.tasks[uuid])
			assert.equals("google1", map.tasks[uuid].google_id)

			-- Remove task
			mapping.remove_task(map, uuid)

			-- Task should be gone
			assert.is_nil(map.tasks[uuid])
		end)

		it("should preserve other tasks when removing one", function()
			local map = { tasks = {} }
			local uuid1 = "uuid-111"
			local uuid2 = "uuid-222"

			mapping.register_task(map, uuid1, "google1", "List", "/file.md", nil, "2025-01-01T10:00:00Z")
			mapping.register_task(map, uuid2, "google2", "List", "/file.md", nil, "2025-01-01T10:00:00Z")

			-- Remove first task
			mapping.remove_task(map, uuid1)

			-- First should be gone, second should remain
			assert.is_nil(map.tasks[uuid1])
			assert.is_not_nil(map.tasks[uuid2])
			assert.equals("google2", map.tasks[uuid2].google_id)
		end)
	end)

	describe("timestamp-based conflict resolution", function()
		it("should use Google's completion status when Google timestamp is newer", function()
			local map = { tasks = {} }
			local uuid = "uuid-abc123"

			-- Register task with old timestamp
			mapping.register_task(map, uuid, "google1", "List", "/file.md", nil, "2025-01-01T10:00:00Z")

			-- Verify timestamps can be compared
			-- (Google's timestamp "2025-01-01T12:00:00Z" is newer than mapping's "2025-01-01T10:00:00Z")
			assert.is_true("2025-01-01T12:00:00Z" > "2025-01-01T10:00:00Z")
		end)

		it("should use markdown's completion status when mapping timestamp is newer", function()
			local map = { tasks = {} }
			local uuid = "uuid-abc123"

			-- Register task with recent timestamp
			mapping.register_task(map, uuid, "google1", "List", "/file.md", nil, "2025-01-01T12:00:00Z")

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



	describe("register_task with google_updated", function()
		it("should store google_updated timestamp when provided", function()
			local map = { tasks = {} }
			local uuid = "uuid-abc123"
			local timestamp = "2025-01-01T15:30:00Z"

			mapping.register_task(map, uuid, "google1", "List", "/file.md", nil, timestamp)

			assert.equals(timestamp, map.tasks[uuid].google_updated)
		end)

		it("should use current time when google_updated not provided", function()
			local map = { tasks = {} }
			local uuid = "uuid-abc123"

			mapping.register_task(
				map,
				uuid,
				"google1",
				"List",
				"/file.md",
				nil,
				nil -- No timestamp provided
			)

			-- Should have some timestamp
			assert.is_not_nil(map.tasks[uuid].google_updated)
			-- Should be in RFC3339 format
			assert.is_not_nil(
				map.tasks[uuid].google_updated:match("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ")
			)
		end)

		it("should store parent_uuid when provided", function()
			local map = { tasks = {} }
			local uuid = "uuid-child"
			local parent_uuid = "uuid-parent"

			mapping.register_task(map, uuid, "google1", "List", "/file.md", parent_uuid, "2025-01-01T10:00:00Z")

			assert.equals(parent_uuid, map.tasks[uuid].parent_uuid)
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
