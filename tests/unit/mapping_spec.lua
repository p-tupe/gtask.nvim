---Unit tests for mapping module (UUID-based)
describe("mapping module", function()
	local mapping
	local vim_mock

	before_each(function()
		-- Load vim mock
		vim_mock = require("tests.helpers.vim_mock")
		vim_mock.reset()

		-- Load mapping module
		mapping = require("gtask.mapping")
	end)

	describe("generate_task_key", function()
		it("should return UUID as key", function()
			local key = mapping.generate_task_key("uuid-abc123")
			assert.equals("uuid-abc123", key)
		end)

		it("should handle different UUIDs", function()
			local key1 = mapping.generate_task_key("uuid-111")
			local key2 = mapping.generate_task_key("uuid-222")
			assert.equals("uuid-111", key1)
			assert.equals("uuid-222", key2)
		end)
	end)

	describe("register_task and get_google_id", function()
		it("should register and retrieve task", function()
			local map = { tasks = {} }
			local uuid = "uuid-abc123"

			mapping.register_task(map, uuid, "google123", "Shopping", "/file.md", nil)

			local google_id = mapping.get_google_id(map, uuid)
			assert.equals("google123", google_id)
		end)

		it("should store task metadata", function()
			local map = { tasks = {} }
			local uuid = "uuid-abc123"

			mapping.register_task(map, uuid, "google123", "Shopping", "/file.md", nil)

			local task_data = map.tasks[uuid]
			assert.is_not_nil(task_data)
			assert.equals("google123", task_data.google_id)
			assert.equals("Shopping", task_data.list_name)
			assert.equals("/file.md", task_data.file_path)
			assert.is_nil(task_data.parent_uuid)
		end)

		it("should register subtask with parent uuid", function()
			local map = { tasks = {} }
			local uuid = "uuid-child"
			local parent_uuid = "uuid-parent"

			mapping.register_task(map, uuid, "google456", "Shopping", "/file.md", parent_uuid)

			local task_data = map.tasks[uuid]
			assert.is_not_nil(task_data)
			assert.equals("google456", task_data.google_id)
			assert.equals(parent_uuid, task_data.parent_uuid)
		end)
	end)

	describe("remove_task", function()
		it("should remove task from mapping", function()
			local map = { tasks = {} }
			local uuid = "uuid-abc123"

			mapping.register_task(map, uuid, "google123", "Shopping", "/file.md", nil)

			mapping.remove_task(map, uuid)

			assert.is_nil(map.tasks[uuid])
		end)
	end)

	describe("find_task_key_by_google_id", function()
		it("should find UUID by Google ID", function()
			local map = { tasks = {} }
			local uuid = "uuid-abc123"

			mapping.register_task(map, uuid, "google123", "Shopping", "/file.md", nil)

			local found_key = mapping.find_task_key_by_google_id(map, "google123")

			assert.equals(uuid, found_key)
		end)

		it("should return nil for non-existent Google ID", function()
			local map = { tasks = {} }

			local found_key = mapping.find_task_key_by_google_id(map, "nonexistent")

			assert.is_nil(found_key)
		end)
	end)

	describe("cleanup_orphaned_tasks", function()
		it("should remove tasks not in current list", function()
			local map = { tasks = {} }

			mapping.register_task(map, "uuid-1", "google1", "Shopping", "/file.md", nil)
			mapping.register_task(map, "uuid-2", "google2", "Shopping", "/file.md", nil)
			mapping.register_task(map, "uuid-3", "google3", "Shopping", "/file.md", nil)

			local current_keys = { "uuid-1", "uuid-3" }
			local removed = mapping.cleanup_orphaned_tasks(map, "Shopping", current_keys)

			assert.equals(1, removed)
			assert.is_not_nil(map.tasks["uuid-1"])
			assert.is_nil(map.tasks["uuid-2"])
			assert.is_not_nil(map.tasks["uuid-3"])
		end)

		it("should not remove tasks from other lists", function()
			local map = { tasks = {} }

			mapping.register_task(map, "uuid-shopping", "google1", "Shopping", "/file.md", nil)
			mapping.register_task(map, "uuid-work", "google2", "Work", "/work.md", nil)

			local current_keys = {}
			local removed = mapping.cleanup_orphaned_tasks(map, "Shopping", current_keys)

			assert.equals(1, removed)
			assert.is_nil(map.tasks["uuid-shopping"])
			assert.is_not_nil(map.tasks["uuid-work"])
		end)
	end)

	describe("migration", function()
		it("should detect old format", function()
			local old_map = {
				lists = {},
				tasks = {
					["Shopping|/file.md:[0]"] = {
						google_id = "g123",
						position_path = "[0]",
					},
				},
			}

			assert.is_true(mapping.is_old_format(old_map))
		end)

		it("should not detect new format as old", function()
			local new_map = {
				lists = {},
				tasks = {
					["uuid-abc123"] = {
						google_id = "g123",
						parent_uuid = nil,
					},
				},
			}

			assert.is_false(mapping.is_old_format(new_map))
		end)
	end)
end)
