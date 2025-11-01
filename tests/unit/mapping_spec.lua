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
			local key = mapping.generate_task_key("Shopping", "/path/to/file.md", 10, nil)
			assert.equals("Shopping|/path/to/file.md:10:top", key)
		end)

		it("should generate key for subtask", function()
			local key = mapping.generate_task_key("Shopping", "/path/to/file.md", 15, 10)
			assert.equals("Shopping|/path/to/file.md:15:10", key)
		end)

		it("should handle different list names", function()
			local key = mapping.generate_task_key("Work Tasks", "/work.md", 5, nil)
			assert.equals("Work Tasks|/work.md:5:top", key)
		end)
	end)

	describe("generate_context_signature", function()
		it("should generate signature for top-level task", function()
			local sig = mapping.generate_context_signature("Shopping", "Buy milk", nil)
			assert.equals("Shopping||||Buy milk", sig)
		end)

		it("should generate signature for subtask", function()
			local sig = mapping.generate_context_signature("Shopping", "Get organic", "Buy milk")
			assert.equals("Shopping||Buy milk||Get organic", sig)
		end)

		it("should handle empty parent", function()
			local sig = mapping.generate_context_signature("Shopping", "Buy eggs", "")
			assert.equals("Shopping||||Buy eggs", sig)
		end)
	end)

	describe("register_task and get_google_id", function()
		it("should register and retrieve task", function()
			local map = { tasks = {}, context_index = {} }
			local key = "Shopping|/file.md:10:top"
			local context_sig = "Shopping||||Buy milk"

			mapping.register_task(map, key, "google123", "Shopping", "Buy milk", "/file.md", 10, nil, context_sig)

			local google_id = mapping.get_google_id(map, key)
			assert.equals("google123", google_id)
		end)

		it("should store task metadata", function()
			local map = { tasks = {}, context_index = {} }
			local key = "Shopping|/file.md:10:top"
			local context_sig = "Shopping||||Buy milk"

			mapping.register_task(map, key, "google123", "Shopping", "Buy milk", "/file.md", 10, nil, context_sig)

			local task_data = map.tasks[key]
			assert.is_not_nil(task_data)
			assert.equals("google123", task_data.google_id)
			assert.equals("Shopping", task_data.list_name)
			assert.equals("Buy milk", task_data.title)
			assert.equals("/file.md", task_data.file_path)
			assert.equals(10, task_data.line_number)
			assert.is_nil(task_data.parent_key)
			assert.equals(context_sig, task_data.context_sig)
		end)

		it("should update context index", function()
			local map = { tasks = {}, context_index = {} }
			local key = "Shopping|/file.md:10:top"
			local context_sig = "Shopping||||Buy milk"

			mapping.register_task(map, key, "google123", "Shopping", "Buy milk", "/file.md", 10, nil, context_sig)

			assert.equals(key, map.context_index[context_sig])
		end)
	end)

	describe("find_nearby", function()
		it("should find task at exact position", function()
			local map = { tasks = {}, context_index = {} }
			mapping.register_task(
				map,
				"Shopping|/file.md:10:top",
				"google123",
				"Shopping",
				"Buy milk",
				"/file.md",
				10,
				nil,
				"Shopping||||Buy milk"
			)

			local found_key, found_data, offset = mapping.find_nearby(map, "Shopping", "/file.md", 10, nil)

			assert.equals("Shopping|/file.md:10:top", found_key)
			assert.is_not_nil(found_data)
			assert.equals(0, offset)
		end)

		it("should find task moved up by 2 lines", function()
			local map = { tasks = {}, context_index = {} }
			mapping.register_task(
				map,
				"Shopping|/file.md:10:top",
				"google123",
				"Shopping",
				"Buy milk",
				"/file.md",
				10,
				nil,
				"Shopping||||Buy milk"
			)

			local found_key, found_data, offset = mapping.find_nearby(map, "Shopping", "/file.md", 12, nil)

			assert.equals("Shopping|/file.md:10:top", found_key)
			assert.is_not_nil(found_data)
			assert.equals(-2, offset)
		end)

		it("should find task moved down by 3 lines", function()
			local map = { tasks = {}, context_index = {} }
			mapping.register_task(
				map,
				"Shopping|/file.md:10:top",
				"google123",
				"Shopping",
				"Buy milk",
				"/file.md",
				10,
				nil,
				"Shopping||||Buy milk"
			)

			local found_key, found_data, offset = mapping.find_nearby(map, "Shopping", "/file.md", 7, nil)

			assert.equals("Shopping|/file.md:10:top", found_key)
			assert.is_not_nil(found_data)
			assert.equals(3, offset)
		end)

		it("should not find task beyond range", function()
			local map = { tasks = {}, context_index = {} }
			mapping.register_task(
				map,
				"Shopping|/file.md:10:top",
				"google123",
				"Shopping",
				"Buy milk",
				"/file.md",
				10,
				nil,
				"Shopping||||Buy milk"
			)

			local found_key, found_data, offset = mapping.find_nearby(map, "Shopping", "/file.md", 20, nil)

			assert.is_nil(found_key)
			assert.is_nil(found_data)
			assert.is_nil(offset)
		end)

		it("should respect custom range", function()
			local map = { tasks = {}, context_index = {} }
			mapping.register_task(
				map,
				"Shopping|/file.md:10:top",
				"google123",
				"Shopping",
				"Buy milk",
				"/file.md",
				10,
				nil,
				"Shopping||||Buy milk"
			)

			local found_key = mapping.find_nearby(map, "Shopping", "/file.md", 13, nil, 2)

			assert.is_nil(found_key) -- 3 lines away, but range is only 2
		end)
	end)

	describe("find_by_context", function()
		it("should find task by context signature", function()
			local map = { tasks = {}, context_index = {} }
			local key = "Shopping|/file.md:10:top"
			local context_sig = "Shopping||||Buy milk"

			mapping.register_task(map, key, "google123", "Shopping", "Buy milk", "/file.md", 10, nil, context_sig)

			local found_key, found_data = mapping.find_by_context(map, context_sig)

			assert.equals(key, found_key)
			assert.is_not_nil(found_data)
			assert.equals("google123", found_data.google_id)
		end)

		it("should return nil for non-existent context", function()
			local map = { tasks = {}, context_index = {} }

			local found_key, found_data = mapping.find_by_context(map, "Shopping||||Buy eggs")

			assert.is_nil(found_key)
			assert.is_nil(found_data)
		end)

		it("should find subtask by context with parent", function()
			local map = { tasks = {}, context_index = {} }
			local key = "Shopping|/file.md:15:10"
			local context_sig = "Shopping|Buy milk|Get organic"

			mapping.register_task(
				map,
				key,
				"google456",
				"Shopping",
				"Get organic",
				"/file.md",
				15,
				"Shopping|/file.md:10:top",
				context_sig
			)

			local found_key, found_data = mapping.find_by_context(map, context_sig)

			assert.equals(key, found_key)
			assert.equals("google456", found_data.google_id)
		end)
	end)

	describe("update_task_position", function()
		it("should update task position and key", function()
			local map = { tasks = {}, context_index = {} }
			local old_key = "Shopping|/file.md:10:top"
			local new_key = "Shopping|/file.md:15:top"
			local context_sig = "Shopping||||Buy milk"

			mapping.register_task(map, old_key, "google123", "Shopping", "Buy milk", "/file.md", 10, nil, context_sig)

			local success = mapping.update_task_position(map, old_key, new_key, 15)

			assert.is_true(success)
			assert.is_nil(map.tasks[old_key])
			assert.is_not_nil(map.tasks[new_key])
			assert.equals(15, map.tasks[new_key].line_number)
		end)

		it("should update context index", function()
			local map = { tasks = {}, context_index = {} }
			local old_key = "Shopping|/file.md:10:top"
			local new_key = "Shopping|/file.md:15:top"
			local context_sig = "Shopping||||Buy milk"

			mapping.register_task(map, old_key, "google123", "Shopping", "Buy milk", "/file.md", 10, nil, context_sig)

			mapping.update_task_position(map, old_key, new_key, 15)

			assert.equals(new_key, map.context_index[context_sig])
		end)

		it("should return false for non-existent task", function()
			local map = { tasks = {}, context_index = {} }

			local success = mapping.update_task_position(map, "nonexistent", "newkey", 20)

			assert.is_false(success)
		end)
	end)

	describe("remove_task", function()
		it("should remove task from mapping", function()
			local map = { tasks = {}, context_index = {} }
			local key = "Shopping|/file.md:10:top"
			local context_sig = "Shopping||||Buy milk"

			mapping.register_task(map, key, "google123", "Shopping", "Buy milk", "/file.md", 10, nil, context_sig)

			mapping.remove_task(map, key)

			assert.is_nil(map.tasks[key])
		end)

		it("should remove from context index", function()
			local map = { tasks = {}, context_index = {} }
			local key = "Shopping|/file.md:10:top"
			local context_sig = "Shopping||||Buy milk"

			mapping.register_task(map, key, "google123", "Shopping", "Buy milk", "/file.md", 10, nil, context_sig)

			mapping.remove_task(map, key)

			assert.is_nil(map.context_index[context_sig])
		end)
	end)

	describe("find_task_key_by_google_id", function()
		it("should find task key by Google ID", function()
			local map = { tasks = {}, context_index = {} }
			local key = "Shopping|/file.md:10:top"

			mapping.register_task(
				map,
				key,
				"google123",
				"Shopping",
				"Buy milk",
				"/file.md",
				10,
				nil,
				"Shopping||||Buy milk"
			)

			local found_key = mapping.find_task_key_by_google_id(map, "google123")

			assert.equals(key, found_key)
		end)

		it("should return nil for non-existent Google ID", function()
			local map = { tasks = {}, context_index = {} }

			local found_key = mapping.find_task_key_by_google_id(map, "nonexistent")

			assert.is_nil(found_key)
		end)
	end)

	describe("cleanup_orphaned_tasks", function()
		it("should remove tasks not in current list", function()
			local map = { tasks = {}, context_index = {} }

			mapping.register_task(
				map,
				"Shopping|/file.md:10:top",
				"google1",
				"Shopping",
				"Buy milk",
				"/file.md",
				10,
				nil,
				"Shopping||||Buy milk"
			)
			mapping.register_task(
				map,
				"Shopping|/file.md:15:top",
				"google2",
				"Shopping",
				"Buy eggs",
				"/file.md",
				15,
				nil,
				"Shopping||||Buy eggs"
			)
			mapping.register_task(
				map,
				"Shopping|/file.md:20:top",
				"google3",
				"Shopping",
				"Buy bread",
				"/file.md",
				20,
				nil,
				"Shopping||||Buy bread"
			)

			local current_keys = { "Shopping|/file.md:10:top", "Shopping|/file.md:20:top" }
			local removed = mapping.cleanup_orphaned_tasks(map, "Shopping", current_keys)

			assert.equals(1, removed)
			assert.is_not_nil(map.tasks["Shopping|/file.md:10:top"])
			assert.is_nil(map.tasks["Shopping|/file.md:15:top"])
			assert.is_not_nil(map.tasks["Shopping|/file.md:20:top"])
		end)

		it("should not remove tasks from other lists", function()
			local map = { tasks = {}, context_index = {} }

			mapping.register_task(
				map,
				"Shopping|/file.md:10:top",
				"google1",
				"Shopping",
				"Buy milk",
				"/file.md",
				10,
				nil,
				"Shopping||||Buy milk"
			)
			mapping.register_task(
				map,
				"Work|/work.md:5:top",
				"google2",
				"Work",
				"Email boss",
				"/work.md",
				5,
				nil,
				"Work||||Email boss"
			)

			local current_keys = {}
			local removed = mapping.cleanup_orphaned_tasks(map, "Shopping", current_keys)

			assert.equals(1, removed)
			assert.is_nil(map.tasks["Shopping|/file.md:10:top"])
			assert.is_not_nil(map.tasks["Work|/work.md:5:top"])
		end)
	end)
end)
