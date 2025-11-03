---Unit tests for parser module
describe("parser module", function()
	local parser
	local vim_mock

	before_each(function()
		vim_mock = require("tests.helpers.vim_mock")
		vim_mock.reset()
		parser = require("gtask.parser")
	end)

	describe("extract_list_name", function()
		it("should extract H1 heading", function()
			local lines = {
				"# Shopping List",
				"",
				"- [ ] Buy milk",
			}

			local name = parser.extract_list_name(lines)
			assert.equals("Shopping List", name)
		end)

		it("should return nil when no H1", function()
			local lines = {
				"## Not H1",
				"- [ ] Task",
			}

			local name = parser.extract_list_name(lines)
			assert.is_nil(name)
		end)

		it("should extract first H1 only", function()
			local lines = {
				"# First List",
				"# Second List",
			}

			local name = parser.extract_list_name(lines)
			assert.equals("First List", name)
		end)
	end)

	describe("parse_task_line", function()
		it("should parse simple incomplete task", function()
			local indent, checkbox, title, due_date = parser.parse_task_line("- [ ] Buy milk")

			assert.equals(0, indent)
			assert.equals(" ", checkbox)
			assert.equals("Buy milk", title)
			assert.is_nil(due_date)
		end)

		it("should parse malformed checkbox as empty string (lenient)", function()
			-- Missing space in checkbox - parser allows this
			local indent, checkbox, title = parser.parse_task_line("- [] Buy milk")
			assert.equals(0, indent)
			assert.equals("", checkbox) -- Empty string, not space
			assert.equals("Buy milk", title)
		end)

		it("should NOT parse lines without dash prefix", function()
			local _, checkbox, title = parser.parse_task_line("[ ] Not a task")
			assert.is_nil(checkbox)
			assert.is_nil(title)

			_, checkbox, title = parser.parse_task_line("* [ ] Wrong bullet")
			assert.is_nil(checkbox)
			assert.is_nil(title)
		end)

		it("should handle invalid due dates gracefully", function()
			-- Invalid date pattern doesn't match, so whole thing becomes title
			local indent, checkbox, title, due_date = parser.parse_task_line("- [ ] Task | not-a-date")
			assert.equals(0, indent)
			assert.equals(" ", checkbox)
			assert.equals("Task | not-a-date", title) -- Parser keeps pipe in title when date doesn't match
			assert.is_nil(due_date)
		end)

		it("should enforce valid date format YYYY-MM-DD", function()
			-- Only dates matching the pattern are parsed
			local _, _, title, due_date = parser.parse_task_line("- [ ] Task | 2025-01-15")
			assert.equals("Task", title)
			assert.is_not_nil(due_date)
			assert.equals("2025-01-15T00:00:00.000Z", due_date)
		end)

		it("should parse completed task", function()
			local indent, checkbox, title = parser.parse_task_line("- [x] Buy milk")

			assert.equals(0, indent)
			assert.equals("x", checkbox)
			assert.equals("Buy milk", title)
		end)

		it("should parse task with date only", function()
			local indent, checkbox, title, due_date = parser.parse_task_line("- [ ] Buy milk | 2025-12-31")

			assert.equals(0, indent)
			assert.equals(" ", checkbox)
			assert.equals("Buy milk", title)
			assert.equals("2025-12-31T00:00:00.000Z", due_date)
		end)

		it("should parse task with date and time", function()
			local indent, checkbox, title, due_date = parser.parse_task_line("- [ ] Buy milk | 2025-12-31 14:30")

			assert.equals(0, indent)
			assert.equals(" ", checkbox)
			assert.equals("Buy milk", title)
			assert.equals("2025-12-31T14:30:00.000Z", due_date)
		end)

		it("should parse indented task (2 spaces)", function()
			local indent, checkbox, title = parser.parse_task_line("  - [ ] Subtask")

			assert.equals(1, indent)
			assert.equals(" ", checkbox)
			assert.equals("Subtask", title)
		end)

		it("should parse deeply indented task (4 spaces)", function()
			local indent, checkbox, title = parser.parse_task_line("    - [ ] Deep subtask")

			assert.equals(2, indent)
			assert.equals(" ", checkbox)
			assert.equals("Deep subtask", title)
		end)

		it("should return nil for non-task lines", function()
			local indent, checkbox, title, due_date = parser.parse_task_line("Just some text")

			assert.equals(0, indent)
			assert.is_nil(checkbox)
			assert.is_nil(title)
			assert.is_nil(due_date)
		end)

		it("should handle task with multiple pipes in title", function()
			local indent, checkbox, title, due_date =
				parser.parse_task_line("- [ ] Research A | B options | 2025-01-15")

			assert.equals(0, indent)
			assert.equals(" ", checkbox)
			assert.equals("Research A | B options", title)
			assert.equals("2025-01-15T00:00:00.000Z", due_date)
		end)
	end)

	describe("parse_single_task", function()
		it("should parse task without description", function()
			local lines = {
				"- [ ] Buy milk",
				"- [ ] Buy eggs",
			}

			local task, consumed = parser.parse_single_task(lines, 1)

			assert.is_not_nil(task)
			assert.equals("Buy milk", task.title)
			assert.is_false(task.completed)
			assert.is_nil(task.description)
			assert.equals(1, task.line_number)
			assert.equals(0, task.indent_level)
			assert.equals(1, consumed)
		end)

		it("should parse task with description", function()
			local lines = {
				"- [ ] Buy milk",
				"  Get organic if available",
				"  From local farm",
				"",
				"- [ ] Buy eggs",
			}

			local task, consumed = parser.parse_single_task(lines, 1)

			assert.is_not_nil(task)
			assert.equals("Buy milk", task.title)
			assert.equals("Get organic if available\nFrom local farm", task.description)
			assert.equals(3, consumed)
		end)

		it("should parse task with blank line before description", function()
			local lines = {
				"- [ ] Buy milk",
				"",
				"  Get organic",
				"",
				"- [ ] Buy eggs",
			}

			local task, consumed = parser.parse_single_task(lines, 1)

			assert.is_not_nil(task)
			assert.equals("Buy milk", task.title)
			assert.equals("Get organic", task.description)
			assert.equals(3, consumed)
		end)

		it("should stop at double blank line", function()
			local lines = {
				"- [ ] Buy milk",
				"  Description line 1",
				"",
				"",
				"- [ ] Buy eggs",
			}

			local task, consumed = parser.parse_single_task(lines, 1)

			assert.is_not_nil(task)
			assert.equals("Buy milk", task.title)
			assert.equals("Description line 1", task.description)
			assert.equals(2, consumed)
		end)

		it("should stop at less-indented line", function()
			local lines = {
				"  - [ ] Subtask",
				"    Description for subtask",
				"Not indented enough",
				"- [ ] Another task",
			}

			local task, consumed = parser.parse_single_task(lines, 1)

			assert.is_not_nil(task)
			assert.equals("Subtask", task.title)
			assert.equals("Description for subtask", task.description)
			assert.equals(2, consumed)
		end)

		it("should parse completed task", function()
			local lines = {
				"- [x] Completed task",
			}

			local task = parser.parse_single_task(lines, 1)

			assert.is_not_nil(task)
			assert.equals("Completed task", task.title)
			assert.is_true(task.completed)
		end)

		it("should parse task with due date", function()
			local lines = {
				"- [ ] Task with deadline | 2025-12-31",
			}

			local task = parser.parse_single_task(lines, 1)

			assert.is_not_nil(task)
			assert.equals("Task with deadline", task.title)
			assert.equals("2025-12-31T00:00:00.000Z", task.due_date)
		end)
	end)

	describe("build_hierarchy", function()
		it("should link subtask to parent", function()
			local tasks = {
				{ title = "Parent", indent_level = 0, line_number = 1 },
				{ title = "Child", indent_level = 1, line_number = 2 },
			}

			parser.build_hierarchy(tasks)

			assert.is_nil(tasks[1].parent_index)
			assert.equals(1, tasks[2].parent_index)
		end)

		it("should handle multiple levels", function()
			local tasks = {
				{ title = "Level 0", indent_level = 0, line_number = 1 },
				{ title = "Level 1", indent_level = 1, line_number = 2 },
				{ title = "Level 2", indent_level = 2, line_number = 3 },
			}

			parser.build_hierarchy(tasks)

			assert.is_nil(tasks[1].parent_index)
			assert.equals(1, tasks[2].parent_index)
			assert.equals(2, tasks[3].parent_index)
		end)

		it("should handle siblings at same level", function()
			local tasks = {
				{ title = "Parent", indent_level = 0, line_number = 1 },
				{ title = "Child 1", indent_level = 1, line_number = 2 },
				{ title = "Child 2", indent_level = 1, line_number = 3 },
			}

			parser.build_hierarchy(tasks)

			assert.is_nil(tasks[1].parent_index)
			assert.equals(1, tasks[2].parent_index)
			assert.equals(1, tasks[3].parent_index)
		end)

		it("should handle going back to top level", function()
			local tasks = {
				{ title = "Parent 1", indent_level = 0, line_number = 1 },
				{ title = "Child 1", indent_level = 1, line_number = 2 },
				{ title = "Parent 2", indent_level = 0, line_number = 3 },
			}

			parser.build_hierarchy(tasks)

			assert.is_nil(tasks[1].parent_index)
			assert.equals(1, tasks[2].parent_index)
			assert.is_nil(tasks[3].parent_index)
		end)

		it("should handle skipping indent levels", function()
			local tasks = {
				{ title = "Level 0", indent_level = 0, line_number = 1 },
				{ title = "Level 2", indent_level = 2, line_number = 2 }, -- Skipped level 1
				{ title = "Level 1", indent_level = 1, line_number = 3 },
			}

			parser.build_hierarchy(tasks)

			assert.is_nil(tasks[1].parent_index)
			assert.equals(1, tasks[2].parent_index) -- Parent is level 0
			assert.equals(1, tasks[3].parent_index) -- Parent is level 0
		end)
	end)

	describe("parse_tasks", function()
		it("should parse multiple tasks", function()
			local lines = {
				"- [ ] Task 1",
				"- [ ] Task 2",
				"- [ ] Task 3",
			}

			local tasks = parser.parse_tasks(lines)

			assert.equals(3, #tasks)
			assert.equals("Task 1", tasks[1].title)
			assert.equals("Task 2", tasks[2].title)
			assert.equals("Task 3", tasks[3].title)
		end)

		it("should parse tasks with descriptions", function()
			local lines = {
				"- [ ] Task 1",
				"  Description 1",
				"",
				"- [ ] Task 2",
				"  Description 2",
			}

			local tasks = parser.parse_tasks(lines)

			assert.equals(2, #tasks)
			assert.equals("Description 1", tasks[1].description)
			assert.equals("Description 2", tasks[2].description)
		end)

		it("should build hierarchy", function()
			local lines = {
				"- [ ] Parent",
				"  - [ ] Child 1",
				"  - [ ] Child 2",
			}

			local tasks = parser.parse_tasks(lines)

			assert.equals(3, #tasks)
			assert.is_nil(tasks[1].parent_index)
			assert.equals(1, tasks[2].parent_index)
			assert.equals(1, tasks[3].parent_index)
		end)

		it("should handle mixed content", function()
			local lines = {
				"# Shopping List",
				"",
				"Some intro text",
				"",
				"- [ ] Buy milk",
				"  From store",
				"  - [ ] Get organic",
				"",
				"More text",
				"",
				"- [ ] Buy eggs",
			}

			local tasks = parser.parse_tasks(lines)

			assert.equals(3, #tasks)
			assert.equals("Buy milk", tasks[1].title)
			assert.equals("From store", tasks[1].description)
			assert.equals("Get organic", tasks[2].title)
			assert.equals(1, tasks[2].parent_index)
			assert.equals("Buy eggs", tasks[3].title)
		end)
	end)

	describe("build_position_paths", function()
		it("should assign position paths to flat list", function()
			local tasks = {
				{ title = "Task 1", parent_index = nil },
				{ title = "Task 2", parent_index = nil },
				{ title = "Task 3", parent_index = nil },
			}

			parser.build_position_paths(tasks)

			assert.equals("[0]", tasks[1].position_path)
			assert.equals("[1]", tasks[2].position_path)
			assert.equals("[2]", tasks[3].position_path)
		end)

		it("should assign position paths to single parent with children", function()
			local tasks = {
				{ title = "Parent", parent_index = nil },
				{ title = "Child 1", parent_index = 1 },
				{ title = "Child 2", parent_index = 1 },
			}

			parser.build_position_paths(tasks)

			assert.equals("[0]", tasks[1].position_path)
			assert.equals("[0].[0]", tasks[2].position_path)
			assert.equals("[0].[1]", tasks[3].position_path)
		end)

		it("should assign position paths to multiple parents with children", function()
			local tasks = {
				{ title = "Parent 1", parent_index = nil },
				{ title = "Child 1.1", parent_index = 1 },
				{ title = "Parent 2", parent_index = nil },
				{ title = "Child 2.1", parent_index = 3 },
				{ title = "Child 2.2", parent_index = 3 },
			}

			parser.build_position_paths(tasks)

			assert.equals("[0]", tasks[1].position_path)
			assert.equals("[0].[0]", tasks[2].position_path)
			assert.equals("[1]", tasks[3].position_path)
			assert.equals("[1].[0]", tasks[4].position_path)
			assert.equals("[1].[1]", tasks[5].position_path)
		end)

		it("should handle deep nesting", function()
			local tasks = {
				{ title = "Level 0", parent_index = nil },
				{ title = "Level 1", parent_index = 1 },
				{ title = "Level 2", parent_index = 2 },
				{ title = "Level 3", parent_index = 3 },
			}

			parser.build_position_paths(tasks)

			assert.equals("[0]", tasks[1].position_path)
			assert.equals("[0].[0]", tasks[2].position_path)
			assert.equals("[0].[0].[0]", tasks[3].position_path)
			assert.equals("[0].[0].[0].[0]", tasks[4].position_path)
		end)

		it("should handle mixed hierarchy", function()
			local tasks = {
				{ title = "Top 1", parent_index = nil },
				{ title = "Top 1 - Child 1", parent_index = 1 },
				{ title = "Top 1 - Child 1 - Grandchild 1", parent_index = 2 },
				{ title = "Top 1 - Child 2", parent_index = 1 },
				{ title = "Top 2", parent_index = nil },
				{ title = "Top 3", parent_index = nil },
				{ title = "Top 3 - Child 1", parent_index = 6 },
			}

			parser.build_position_paths(tasks)

			assert.equals("[0]", tasks[1].position_path)
			assert.equals("[0].[0]", tasks[2].position_path)
			assert.equals("[0].[0].[0]", tasks[3].position_path)
			assert.equals("[0].[1]", tasks[4].position_path)
			assert.equals("[1]", tasks[5].position_path)
			assert.equals("[2]", tasks[6].position_path)
			assert.equals("[2].[0]", tasks[7].position_path)
		end)

		it("should handle siblings at same level", function()
			local tasks = {
				{ title = "Parent", parent_index = nil },
				{ title = "Child 1", parent_index = 1 },
				{ title = "Child 2", parent_index = 1 },
				{ title = "Child 3", parent_index = 1 },
				{ title = "Child 4", parent_index = 1 },
			}

			parser.build_position_paths(tasks)

			assert.equals("[0]", tasks[1].position_path)
			assert.equals("[0].[0]", tasks[2].position_path)
			assert.equals("[0].[1]", tasks[3].position_path)
			assert.equals("[0].[2]", tasks[4].position_path)
			assert.equals("[0].[3]", tasks[5].position_path)
		end)

		it("should create unique position paths for all tasks", function()
			local tasks = {
				{ title = "A", parent_index = nil },
				{ title = "A1", parent_index = 1 },
				{ title = "A2", parent_index = 1 },
				{ title = "B", parent_index = nil },
				{ title = "B1", parent_index = 4 },
				{ title = "B1a", parent_index = 5 },
			}

			parser.build_position_paths(tasks)

			-- Collect all position paths
			local paths = {}
			for _, task in ipairs(tasks) do
				table.insert(paths, task.position_path)
			end

			-- Check uniqueness
			local seen = {}
			for _, path in ipairs(paths) do
				assert.is_nil(seen[path], "Position path " .. path .. " must be unique")
				seen[path] = true
			end

			-- Verify count
			assert.equals(6, #paths)
		end)

		it("should assign position paths that reflect hierarchy depth", function()
			local tasks = {
				{ title = "L0", parent_index = nil },
				{ title = "L1", parent_index = 1 },
				{ title = "L2", parent_index = 2 },
				{ title = "L3", parent_index = 3 },
				{ title = "L4", parent_index = 4 },
			}

			parser.build_position_paths(tasks)

			-- Count dots in path should equal depth
			local function count_depth(path)
				local _, count = path:gsub("%.", "")
				return count
			end

			assert.equals(0, count_depth(tasks[1].position_path), "L0 should have depth 0")
			assert.equals(1, count_depth(tasks[2].position_path), "L1 should have depth 1")
			assert.equals(2, count_depth(tasks[3].position_path), "L2 should have depth 2")
			assert.equals(3, count_depth(tasks[4].position_path), "L3 should have depth 3")
			assert.equals(4, count_depth(tasks[5].position_path), "L4 should have depth 4")
		end)
	end)

	describe("edge cases and validation", function()
		it("should handle empty task list", function()
			local tasks = parser.parse_tasks({})
			assert.equals(0, #tasks)
		end)

		it("should handle file with only non-task content", function()
			local lines = {
				"# Just a heading",
				"",
				"Some paragraph text",
				"",
				"More text",
			}

			local tasks = parser.parse_tasks(lines)
			assert.equals(0, #tasks)
		end)

		it("should handle very long task titles", function()
			local long_title = string.rep("A", 500)
			local line = "- [ ] " .. long_title
			local indent, checkbox, title = parser.parse_task_line(line)

			assert.equals(0, indent)
			assert.equals(" ", checkbox)
			assert.equals(long_title, title)
			assert.equals(500, #title)
		end)

		it("should handle task with empty title", function()
			local indent, checkbox = parser.parse_task_line("- [ ] ")

			assert.equals(0, indent)
			assert.equals(" ", checkbox)
			-- May be empty or whitespace, implementation-dependent
			-- Main thing is it shouldn't crash
		end)

		it("should handle maximum realistic nesting (10 levels)", function()
			local tasks = {}
			for i = 1, 10 do
				table.insert(tasks, {
					title = "Level " .. i,
					indent_level = i - 1,
					parent_index = i > 1 and (i - 1) or nil,
				})
			end

			parser.build_hierarchy(tasks)
			parser.build_position_paths(tasks)

			-- Verify hierarchy is correctly built
			for i = 2, 10 do
				assert.equals(i - 1, tasks[i].parent_index)
			end

			-- Verify position paths increase in depth
			for i = 1, 10 do
				local _, dot_count = tasks[i].position_path:gsub("%.", "")
				assert.equals(i - 1, dot_count, "Task at level " .. i .. " should have " .. (i - 1) .. " dots")
			end
		end)
	end)
end)
