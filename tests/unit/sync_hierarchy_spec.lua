---Unit tests for Google Tasks hierarchy preservation
describe("sync module - hierarchy preservation", function()
	local vim_mock
	local plenary_mock

	before_each(function()
		-- Load vim mock
		vim_mock = require("tests.helpers.vim_mock")
		vim_mock.reset()

		-- Load plenary mock
		plenary_mock = require("tests.helpers.plenary_mock")
		plenary_mock.setup()

		-- Clean up any stale state from previous test runs (CI isolation)
		-- This prevents tests from being affected by data from previous runs
		local mapping_file = vim.fn.stdpath("data") .. "/gtask_mappings.json"
		os.remove(mapping_file)

		-- Clean up test files that might exist from previous runs
		local test_files = {
			"/tmp/test-list.md",
			"/tmp/desc-list.md",
			"/tmp/multi-list.md",
		}
		for _, file in ipairs(test_files) do
			os.remove(file)
		end

		-- Unload sync module to ensure fresh state
		package.loaded["gtask.sync"] = nil
		package.loaded["gtask.mapping"] = nil
	end)

	after_each(function()
		-- Clean up test files after each test
		local test_files = {
			"/tmp/test-list.md",
			"/tmp/desc-list.md",
			"/tmp/multi-list.md",
		}
		for _, file in ipairs(test_files) do
			os.remove(file)
		end

		-- Clean up mapping file
		local mapping_file = vim.fn.stdpath("data") .. "/gtask_mappings.json"
		os.remove(mapping_file)
	end)

	describe("write_google_tasks_to_markdown with hierarchy", function()
		it("should write subtasks with proper indentation", function()
			local sync = require("gtask.sync")
			-- Normalized filename: "Test List" -> "test-list.md"
			local test_file = "/tmp/test-list.md"

			-- Google Tasks with parent-child relationship
			local google_tasks = {
				{
					id = "task1",
					title = "Parent Task",
					status = "needsAction",
					notes = "Parent task description",
				},
				{
					id = "task2",
					title = "Child Task 1",
					status = "needsAction",
					parent = "task1", -- This is a subtask of task1
				},
				{
					id = "task3",
					title = "Child Task 2",
					status = "needsAction",
					parent = "task1", -- This is also a subtask of task1
				},
				{
					id = "task4",
					title = "Grandchild Task",
					status = "needsAction",
					parent = "task2", -- This is a subtask of task2
				},
			}

			-- Write tasks to file
			local success = false
			sync.write_google_tasks_to_markdown(google_tasks, "/tmp", "Test List", nil, function(s)
				success = s
			end)

			assert.is_true(success)

			-- Read and verify the file
			local file = io.open(test_file, "r")
			assert.is_not_nil(file)

			local content = file:read("*all")
			file:close()

			-- Split content into lines for strict validation
			local lines = {}
			for line in content:gmatch("[^\r\n]*") do
				if line ~= "" or #lines > 0 then -- Keep empty lines after first line
					table.insert(lines, line)
				end
			end

			-- Strict validation: check exact structure
			assert.equals("# Test List", lines[1], "Line 1 must be H1 heading")
			assert.equals("", lines[2], "Line 2 must be blank")
			assert.equals("- [ ] Parent Task", lines[3], "Line 3 must be parent task with no indentation")

			-- Find description line (should be somewhere after parent task)
			local parent_desc_line = nil
			for i = 4, #lines do
				if lines[i] == "  Parent task description" then
					parent_desc_line = i
					break
				end
			end
			assert.is_not_nil(parent_desc_line, "Parent task description must exist with 2 spaces indentation")

			-- Find child tasks with exact indentation
			local child1_line = nil
			local child2_line = nil
			local grandchild_line = nil

			for i, line in ipairs(lines) do
				if line == "  - [ ] Child Task 1" then
					child1_line = i
				elseif line == "  - [ ] Child Task 2" then
					child2_line = i
				elseif line == "    - [ ] Grandchild Task" then
					grandchild_line = i
				end
			end

			assert.is_not_nil(child1_line, "Child Task 1 must exist with exactly 2 spaces indentation")
			assert.is_not_nil(child2_line, "Child Task 2 must exist with exactly 2 spaces indentation")
			assert.is_not_nil(grandchild_line, "Grandchild Task must exist with exactly 4 spaces indentation")

			-- Verify ordering: grandchild must come after child1
			assert.is_true(grandchild_line > child1_line, "Grandchild must appear after Child Task 1")
			assert.is_true(grandchild_line < child2_line, "Grandchild must appear before Child Task 2")

			-- Verify no unexpected tasks (count checkbox occurrences)
			local task_count = 0
			for _, line in ipairs(lines) do
				if line:match("^%s*%- %[[ x]%]") then
					task_count = task_count + 1
				end
			end
			assert.equals(4, task_count, "Must have exactly 4 tasks, no more, no less")

			-- Cleanup
			os.remove(test_file)
		end)

		it("should preserve task descriptions with proper indentation", function()
			local sync = require("gtask.sync")
			-- Normalized filename: "Desc List" -> "desc-list.md"
			local test_file = "/tmp/desc-list.md"

			-- Clean up any existing file first (avoid CI state issues)
			os.remove(test_file)
			-- Verify file is gone
			local check_file = io.open(test_file, "r")
			if check_file then
				check_file:close()
				error("Failed to remove test file before test")
			end

			local google_tasks = {
				{
					id = "task1",
					title = "Parent Task",
					status = "needsAction",
					notes = "Parent description",
				},
				{
					id = "task2",
					title = "Child Task",
					status = "needsAction",
					parent = "task1",
					notes = "Child description",
				},
			}

			local success = false
			sync.write_google_tasks_to_markdown(google_tasks, "/tmp", "Desc List", nil, function(s)
				success = s
			end)

			assert.is_true(success)

			local file = io.open(test_file, "r")
			local content = file:read("*all")
			file:close()

			-- Split content into lines for strict validation
			local lines = {}
			for line in content:gmatch("[^\r\n]*") do
				if line ~= "" or #lines > 0 then
					table.insert(lines, line)
				end
			end

			-- Find description lines and validate exact indentation
			local parent_desc_line = nil
			local child_desc_line = nil

			for i, line in ipairs(lines) do
				if line == "  Parent description" then
					parent_desc_line = i
				elseif line == "    Child description" then
					child_desc_line = i
				end
			end

			assert.is_not_nil(parent_desc_line, "Parent description must exist with exactly 2 spaces indentation")
			assert.is_not_nil(child_desc_line, "Child description must exist with exactly 4 spaces indentation")

			-- Validate description appears after task line
			local parent_task_line = nil
			local child_task_line = nil

			for i, line in ipairs(lines) do
				if line == "- [ ] Parent Task" then
					parent_task_line = i
				elseif line == "  - [ ] Child Task" then
					child_task_line = i
				end
			end

			assert.is_not_nil(parent_task_line, "Parent task must exist")
			assert.is_not_nil(child_task_line, "Child task must exist")
			assert.is_true(parent_desc_line > parent_task_line, "Parent description must come after parent task")
			assert.is_true(child_desc_line > child_task_line, "Child description must come after child task")

			-- Verify exactly 2 tasks
			local task_count = 0
			for _, line in ipairs(lines) do
				if line:match("^%s*%- %[[ x]%]") then
					task_count = task_count + 1
				end
			end
			assert.equals(2, task_count, "Must have exactly 2 tasks")

			-- Cleanup
			os.remove(test_file)
		end)

		it("should handle multiple top-level tasks with their own subtasks", function()
			local sync = require("gtask.sync")
			-- Normalized filename: "Multi List" -> "multi-list.md"
			local test_file = "/tmp/multi-list.md"

			-- Clean up any existing file first (avoid CI state issues)
			os.remove(test_file)
			-- Verify file is gone
			local check_file = io.open(test_file, "r")
			if check_file then
				check_file:close()
				error("Failed to remove test file before test")
			end

			local google_tasks = {
				{
					id = "task1",
					title = "First Parent",
					status = "needsAction",
				},
				{
					id = "task2",
					title = "First Child",
					status = "needsAction",
					parent = "task1",
				},
				{
					id = "task3",
					title = "Second Parent",
					status = "needsAction",
				},
				{
					id = "task4",
					title = "Second Child",
					status = "needsAction",
					parent = "task3",
				},
			}

			local success = false
			sync.write_google_tasks_to_markdown(google_tasks, "/tmp", "Multi List", nil, function(s)
				success = s
			end)

			assert.is_true(success)

			local file = io.open(test_file, "r")
			local content = file:read("*all")
			file:close()

			-- Split content into lines for strict validation
			local lines = {}
			for line in content:gmatch("[^\r\n]*") do
				if line ~= "" or #lines > 0 then
					table.insert(lines, line)
				end
			end

			-- Find all task lines with their exact positions
			local first_parent_line = nil
			local first_child_line = nil
			local second_parent_line = nil
			local second_child_line = nil

			for i, line in ipairs(lines) do
				if line == "- [ ] First Parent" then
					first_parent_line = i
				elseif line == "  - [ ] First Child" then
					first_child_line = i
				elseif line == "- [ ] Second Parent" then
					second_parent_line = i
				elseif line == "  - [ ] Second Child" then
					second_child_line = i
				end
			end

			-- Strict assertions
			assert.is_not_nil(first_parent_line, "First Parent must exist with no indentation")
			assert.is_not_nil(first_child_line, "First Child must exist with exactly 2 spaces indentation")
			assert.is_not_nil(second_parent_line, "Second Parent must exist with no indentation")
			assert.is_not_nil(second_child_line, "Second Child must exist with exactly 2 spaces indentation")

			-- Validate ordering: children must come immediately after their parents
			assert.is_true(first_child_line > first_parent_line, "First Child must come after First Parent")
			assert.is_true(first_child_line < second_parent_line, "First Child must come before Second Parent")
			assert.is_true(second_child_line > second_parent_line, "Second Child must come after Second Parent")

			-- Verify exactly 4 tasks
			local task_count = 0
			for _, line in ipairs(lines) do
				if line:match("^%s*%- %[[ x]%]") then
					task_count = task_count + 1
				end
			end
			assert.equals(4, task_count, "Must have exactly 4 tasks")

			-- Verify no improper indentation (tasks must be at 0, 2, 4 spaces, not odd numbers)
			for _, line in ipairs(lines) do
				if line:match("%- %[[ x]%]") then
					local indent = line:match("^(%s*)%- %[")
					local indent_len = #indent
					assert.equals(
						0,
						indent_len % 2,
						"Task indentation must be even number of spaces, got " .. indent_len
					)
				end
			end

			-- Cleanup
			os.remove(test_file)
		end)
	end)
end)
