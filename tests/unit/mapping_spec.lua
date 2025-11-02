---Unit tests for mapping module
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
		it("should generate key for top-level task", function()
			local key = mapping.generate_task_key("Shopping", "/path/to/file.md", "[0]")
			assert.equals("Shopping|/path/to/file.md:[0]", key)
		end)

		it("should generate key for second top-level task", function()
			local key = mapping.generate_task_key("Shopping", "/path/to/file.md", "[1]")
			assert.equals("Shopping|/path/to/file.md:[1]", key)
		end)

		it("should generate key for subtask", function()
			local key = mapping.generate_task_key("Shopping", "/path/to/file.md", "[0].[1]")
			assert.equals("Shopping|/path/to/file.md:[0].[1]", key)
		end)

		it("should generate key for deep subtask", function()
			local key = mapping.generate_task_key("Shopping", "/path/to/file.md", "[0].[1].[2]")
			assert.equals("Shopping|/path/to/file.md:[0].[1].[2]", key)
		end)

		it("should handle different list names", function()
			local key = mapping.generate_task_key("Work Tasks", "/work.md", "[0]")
			assert.equals("Work Tasks|/work.md:[0]", key)
		end)
	end)

	describe("register_task and get_google_id", function()
		it("should register and retrieve task", function()
			local map = { tasks = {} }
			local key = "Shopping|/file.md:[0]"

			mapping.register_task(map, key, "google123", "Shopping", "/file.md", "[0]", nil)

			local google_id = mapping.get_google_id(map, key)
			assert.equals("google123", google_id)
		end)

		it("should store task metadata", function()
			local map = { tasks = {} }
			local key = "Shopping|/file.md:[0]"

			mapping.register_task(map, key, "google123", "Shopping", "/file.md", "[0]", nil)

			local task_data = map.tasks[key]
			assert.is_not_nil(task_data)
			assert.equals("google123", task_data.google_id)
			assert.equals("Shopping", task_data.list_name)
			assert.equals("/file.md", task_data.file_path)
			assert.equals("[0]", task_data.position_path)
			assert.is_nil(task_data.parent_key)
		end)

		it("should register subtask with parent key", function()
			local map = { tasks = {} }
			local key = "Shopping|/file.md:[0].[1]"
			local parent_key = "Shopping|/file.md:[0]"

			mapping.register_task(map, key, "google456", "Shopping", "/file.md", "[0].[1]", parent_key)

			local task_data = map.tasks[key]
			assert.is_not_nil(task_data)
			assert.equals("google456", task_data.google_id)
			assert.equals(parent_key, task_data.parent_key)
		end)
	end)

	describe("remove_task", function()
		it("should remove task from mapping", function()
			local map = { tasks = {} }
			local key = "Shopping|/file.md:[0]"

			mapping.register_task(map, key, "google123", "Shopping", "/file.md", "[0]", nil)

			mapping.remove_task(map, key)

			assert.is_nil(map.tasks[key])
		end)
	end)

	describe("find_task_key_by_google_id", function()
		it("should find task key by Google ID", function()
			local map = { tasks = {} }
			local key = "Shopping|/file.md:[0]"

			mapping.register_task(map, key, "google123", "Shopping", "/file.md", "[0]", nil)

			local found_key = mapping.find_task_key_by_google_id(map, "google123")

			assert.equals(key, found_key)
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

			mapping.register_task(map, "Shopping|/file.md:[0]", "google1", "Shopping", "/file.md", "[0]", nil)
			mapping.register_task(map, "Shopping|/file.md:[1]", "google2", "Shopping", "/file.md", "[1]", nil)
			mapping.register_task(map, "Shopping|/file.md:[2]", "google3", "Shopping", "/file.md", "[2]", nil)

			local current_keys = { "Shopping|/file.md:[0]", "Shopping|/file.md:[2]" }
			local removed = mapping.cleanup_orphaned_tasks(map, "Shopping", current_keys)

			assert.equals(1, removed)
			assert.is_not_nil(map.tasks["Shopping|/file.md:[0]"])
			assert.is_nil(map.tasks["Shopping|/file.md:[1]"])
			assert.is_not_nil(map.tasks["Shopping|/file.md:[2]"])
		end)

		it("should not remove tasks from other lists", function()
			local map = { tasks = {} }

			mapping.register_task(map, "Shopping|/file.md:[0]", "google1", "Shopping", "/file.md", "[0]", nil)
			mapping.register_task(map, "Work|/work.md:[0]", "google2", "Work", "/work.md", "[0]", nil)

			local current_keys = {}
			local removed = mapping.cleanup_orphaned_tasks(map, "Shopping", current_keys)

			assert.equals(1, removed)
			assert.is_nil(map.tasks["Shopping|/file.md:[0]"])
			assert.is_not_nil(map.tasks["Work|/work.md:[0]"])
		end)
	end)
end)
