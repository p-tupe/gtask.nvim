---End-to-End Tests for gtask.nvim
---These tests perform real operations against Google Tasks API
---Requires valid authentication and internet connection

local sync = require("gtask.sync")
local store = require("gtask.store")
local api = require("gtask.api")

-- E2E test configuration
local test_dir = vim.fn.expand("~/gtask-e2e-test"):gsub("\n", "")
local md_to_google_list = "E2E_MD_to_Google_" .. os.time()
local google_to_md_list = "E2E_Google_to_MD_" .. os.time()

-- Helper to get tomorrow's date in YYYY-MM-DD format
local function get_tomorrow_date()
	local tomorrow = os.time() + 86400 -- Add 24 hours in seconds
	return os.date("%Y-%m-%d", tomorrow)
end

-- Helper to get date N days from now
local function get_future_date(days)
	local future = os.time() + (days * 86400)
	return os.date("%Y-%m-%d", future)
end

-- Helper to wait for async operations
local function wait_for_completion(max_wait_ms)
	max_wait_ms = max_wait_ms or 30000
	local start = vim.loop.now()
	while vim.loop.now() - start < max_wait_ms do
		vim.wait(100)
	end
end

-- Helper to read file contents
local function read_file(filepath)
	local file = io.open(filepath, "r")
	if not file then
		return nil
	end
	local content = file:read("*all")
	file:close()
	return content
end

-- Helper to write file contents
local function write_file(filepath, content)
	local dir = vim.fn.fnamemodify(filepath, ":h")
	vim.fn.mkdir(dir, "p")
	local file, err = io.open(filepath, "w")
	if not file then
		error(string.format("Failed to write file: %s (error: %s)", filepath, tostring(err)))
	end
	file:write(content)
	file:close()
end

-- Helper to create test markdown file
local function create_test_file(filename, content)
	local filepath = test_dir .. "/" .. filename
	write_file(filepath, content)
	return filepath
end

-- Helper to sync and wait
local function sync_and_wait(timeout_ms)
	timeout_ms = timeout_ms or 60000 -- Default 60 seconds
	local done = false
	local sync_error = nil

	sync.sync_directory_with_google(function(success)
		if not success then
			sync_error = "Sync returned false"
		end
		done = true
	end)

	local start = vim.loop.now()
	local last_msg_time = start
	while not done and (vim.loop.now() - start) < timeout_ms do
		vim.wait(100)
		-- Print progress every 10 seconds
		if (vim.loop.now() - last_msg_time) > 10000 then
			print(string.format("Still waiting for sync... (%ds elapsed)", math.floor((vim.loop.now() - start) / 1000)))
			last_msg_time = vim.loop.now()
		end
	end

	if sync_error then
		error("Sync failed: " .. sync_error)
	end

	if not done then
		error(string.format("Sync timed out after %d seconds", timeout_ms / 1000))
	end

	print("Sync completed successfully")
end

-- Helper to delete all tasks in a list
local function delete_all_tasks_in_list(list_name, callback)
	api.get_or_create_list(list_name, function(list, err)
		if err or not list then
			callback(err or "Failed to get list")
			return
		end

		api.get_tasks(list.id, function(response, err2)
			if err2 then
				callback(err2)
				return
			end

			local tasks = response.items or {}
			if #tasks == 0 then
				callback(nil)
				return
			end

			local delete_count = 0
			local total = #tasks
			local callback_called = false
			local errors = {}

			for _, task in ipairs(tasks) do
				api.delete_task(list.id, task.id, function(_, err3)
					if err3 then
						table.insert(errors, err3)
					end
					delete_count = delete_count + 1
					if delete_count == total and not callback_called then
						callback_called = true
						if #errors > 0 then
							callback("Deletion errors: " .. table.concat(errors, ", "))
						else
							callback(nil)
						end
					end
				end)
			end
		end)
	end)
end

-- Helper to prompt user and wait for manual confirmation
local function prompt_user_action(instruction)
	print("\n" .. string.rep("=", 70))
	print("USER ACTION REQUIRED:")
	print(instruction)
	print(string.rep("=", 70))

	-- Use a simple loop waiting for a file to be created as confirmation
	local confirm_file = "/tmp/gtask_e2e_continue"
	print(string.format("\nWhen done, run this command to continue:"))
	print(string.format("  touch %s", confirm_file))
	print("")

	-- Wait for confirmation file
	while vim.fn.filereadable(confirm_file) == 0 do
		vim.wait(1000)
	end

	-- Clean up confirmation file
	vim.fn.delete(confirm_file)
	print("Continuing with test...\n")
end

-- Helper to delete old E2E test lists from Google Tasks
local function cleanup_old_e2e_lists(callback)
	api.get_task_lists(function(response, err)
		if err then
			print("Warning: Could not fetch task lists for cleanup: " .. err)
			callback()
			return
		end

		local lists = response.items or {}
		local e2e_lists = {}
		for _, list in ipairs(lists) do
			if list.title:match("^E2E_") then
				table.insert(e2e_lists, list)
			end
		end

		if #e2e_lists == 0 then
			callback()
			return
		end

		print(string.format("Deleting %d old E2E test list(s)...", #e2e_lists))
		local deleted = 0
		for _, list in ipairs(e2e_lists) do
			api.delete_task_list(list.id, function(success, err2)
				deleted = deleted + 1
				if not success then
					print(string.format("Warning: Failed to delete list '%s': %s", list.title, err2 or "unknown"))
				end
				if deleted == #e2e_lists then
					print(string.format("Deleted %d old E2E test list(s)", #e2e_lists))
					callback()
				end
			end)
		end
	end)
end

-- One-time setup: Delete old E2E test lists before all tests
print("\nSetting up E2E tests...")
local cleanup_done = false
cleanup_old_e2e_lists(function()
	cleanup_done = true
end)

local start = vim.loop.now()
while not cleanup_done and (vim.loop.now() - start) < 30000 do
	vim.wait(100)
end

if not cleanup_done then
	print("Warning: Cleanup timed out after 30 seconds")
end
print("E2E setup complete\n")

describe("gtask.nvim E2E", function()
	-- Setup: Configure plugin for E2E testing
	before_each(function()
		vim.fn.mkdir(test_dir, "p")

		-- Clean up any existing test files
		local files = vim.fn.glob(test_dir .. "/*.md", false, true)
		for _, file in ipairs(files) do
			vim.fn.delete(file)
		end

		-- Configure for E2E testing
		require("gtask").setup({
			markdown_dir = test_dir,
			verbosity = "info", -- Use "info" to see sync progress
		})
	end)

	-- Cleanup after each test
	after_each(function()
		vim.fn.delete(test_dir, "rf")
		-- Rate limiting: wait 3 seconds between tests
		vim.wait(3000)
	end)

	describe("1. Authentication", function()
		it("should have valid authentication", function()
			local has_tokens = store.has_tokens()

			if not has_tokens then
				pending("Authentication required. Run :GtaskAuth first before E2E tests.")
			end

			assert.is_true(has_tokens)

			local tokens = store.load_tokens()
			assert.is_not_nil(tokens)
			assert.is_not_nil(tokens.access_token)
		end)
	end)

	-- describe("2. Markdown to Google (and back to Markdown)", function()
	-- 	-- Clean up before and after this entire suite
	-- 	before_each(function()
	-- 		local cleanup_done = false
	-- 		local cleanup_error = nil
	-- 		delete_all_tasks_in_list(md_to_google_list, function(err)
	-- 			cleanup_error = err
	-- 			cleanup_done = true
	-- 		end)
	--
	-- 		local start = vim.loop.now()
	-- 		while not cleanup_done and (vim.loop.now() - start) < 15000 do
	-- 			vim.wait(100)
	-- 		end
	--
	-- 		if not cleanup_done then
	-- 			error("Pre-test cleanup timed out after 15 seconds")
	-- 		end
	--
	-- 		if cleanup_error then
	-- 			error("Pre-test cleanup failed: " .. cleanup_error)
	-- 		end
	-- 	end)
	--
	-- 	after_each(function()
	-- 		local done = false
	-- 		delete_all_tasks_in_list(md_to_google_list, function(err)
	-- 			done = true
	-- 		end)
	--
	-- 		local start = vim.loop.now()
	-- 		while not done and (vim.loop.now() - start) < 10000 do
	-- 			vim.wait(100)
	-- 		end
	-- 	end)
	--
	-- 	it("should create all task variations from markdown", function()
	-- 		if not store.has_tokens() then
	-- 			pending("Authentication required")
	-- 		end
	--
	-- 		local content = string.format(
	-- 			[[# %s
	--
	-- - [ ] Simple Task
	-- - [ ] Task with Due Date | 2025-12-25
	-- - [x] Completed Task
	-- - [ ] Task with Description
	--
	--   This is a description.
	--   Multiple lines supported.
	--
	-- - [ ] Task with All Properties | 2025-12-31
	--
	--   Complete task with everything.
	--
	-- - [ ] Parent Task
	--   - [ ] Subtask 1
	--   - [ ] Subtask with Description
	--
	--     Subtask description here.
	--
	--   - [ ] Subtask with Due Date | 2026-01-15
	-- ]],
	-- 			md_to_google_list
	-- 		)
	--
	-- 		create_test_file("test.md", content)
	-- 		sync_and_wait()
	--
	-- 		-- Verify all tasks in Google
	-- 		local verified = false
	-- 		api.get_or_create_list(md_to_google_list, function(list)
	-- 			api.get_tasks(list.id, function(response)
	-- 				local tasks = response.items or {}
	-- 				assert.equals(9, #tasks, string.format("Expected 9 tasks, got %d", #tasks))
	--
	-- 				local task_map = {}
	-- 				for _, task in ipairs(tasks) do
	-- 					task_map[task.title] = task
	-- 				end
	--
	-- 				-- Verify each task variation
	-- 				assert.is_not_nil(task_map["Simple Task"])
	-- 				assert.equals("needsAction", task_map["Simple Task"].status)
	--
	-- 				assert.is_not_nil(task_map["Task with Due Date"])
	-- 				assert.is_true(task_map["Task with Due Date"].due:match("2025%-12%-25"))
	--
	-- 				assert.is_not_nil(task_map["Completed Task"])
	-- 				assert.equals("completed", task_map["Completed Task"].status)
	--
	-- 				assert.is_not_nil(task_map["Task with Description"])
	-- 				assert.is_true(task_map["Task with Description"].notes:match("This is a description"))
	--
	-- 				assert.is_not_nil(task_map["Task with All Properties"])
	-- 				assert.is_true(task_map["Task with All Properties"].due:match("2025%-12%-31"))
	-- 				assert.is_true(task_map["Task with All Properties"].notes:match("Complete task with everything"))
	--
	-- 				assert.is_not_nil(task_map["Parent Task"])
	-- 				assert.is_nil(task_map["Parent Task"].parent)
	--
	-- 				assert.is_not_nil(task_map["Subtask 1"])
	-- 				assert.equals(task_map["Parent Task"].id, task_map["Subtask 1"].parent)
	--
	-- 				assert.is_not_nil(task_map["Subtask with Description"])
	-- 				assert.equals(task_map["Parent Task"].id, task_map["Subtask with Description"].parent)
	-- 				assert.is_true(task_map["Subtask with Description"].notes:match("Subtask description here"))
	--
	-- 				assert.is_not_nil(task_map["Subtask with Due Date"])
	-- 				assert.equals(task_map["Parent Task"].id, task_map["Subtask with Due Date"].parent)
	-- 				assert.is_true(task_map["Subtask with Due Date"].due:match("2026%-01%-15"))
	--
	-- 				verified = true
	-- 			end)
	-- 		end)
	--
	-- 		wait_for_completion(10000)
	-- 		assert.is_true(verified)
	-- 	end)
	--
	-- 	it("should update task title from markdown to Google", function()
	-- 		if not store.has_tokens() then
	-- 			pending("Authentication required")
	-- 		end
	--
	-- 		local content = string.format(
	-- 			[[# %s
	--
	-- - [ ] Original Title
	-- ]],
	-- 			md_to_google_list
	-- 		)
	--
	-- 		local filepath = create_test_file("test.md", content)
	-- 		sync_and_wait()
	-- 		vim.wait(1000)
	--
	-- 		-- Read UUID
	-- 		local file_content = read_file(filepath)
	-- 		assert.is_true(file_content:match("<!%-%- gtask:"))
	-- 		local uuid = file_content:match("<!%-%- gtask:([%w%-]+)%s*%-%->")
	-- 		assert.is_not_nil(uuid)
	--
	-- 		-- Update title
	-- 		local updated_content = string.format(
	-- 			[[# %s
	--
	-- - [ ] Updated Title
	-- <!-- gtask:%s -->
	-- ]],
	-- 			md_to_google_list,
	-- 			uuid
	-- 		)
	-- 		write_file(filepath, updated_content)
	-- 		vim.wait(2000)
	-- 		sync_and_wait()
	--
	-- 		-- Verify in Google
	-- 		local verified = false
	-- 		api.get_or_create_list(md_to_google_list, function(list)
	-- 			api.get_tasks(list.id, function(response)
	-- 				local tasks = response.items or {}
	-- 				assert.equals(1, #tasks)
	-- 				assert.equals("Updated Title", tasks[1].title)
	-- 				verified = true
	-- 			end)
	-- 		end)
	--
	-- 		wait_for_completion(10000)
	-- 		assert.is_true(verified)
	-- 	end)
	--
	-- 	it("should sync from Google back to markdown (round-trip)", function()
	-- 		if not store.has_tokens() then
	-- 			pending("Authentication required")
	-- 		end
	--
	-- 		local content = string.format(
	-- 			[[# %s
	--
	-- - [ ] Round Trip Task | 2025-12-25
	--
	--   Task description here
	-- ]],
	-- 			md_to_google_list
	-- 		)
	--
	-- 		local filepath = create_test_file("test.md", content)
	-- 		sync_and_wait()
	--
	-- 		-- Delete markdown file
	-- 		vim.fn.delete(filepath)
	--
	-- 		-- Sync should recreate from Google
	-- 		sync_and_wait()
	--
	-- 		-- Verify file recreated
	-- 		local normalized_name = md_to_google_list:lower():gsub("[%s_]+", "-"):gsub('[/:*?"<>|\\]', "")
	-- 		local expected_file = test_dir .. "/" .. normalized_name .. ".md"
	-- 		assert.equals(1, vim.fn.filereadable(expected_file))
	--
	-- 		local recreated_content = read_file(expected_file)
	-- 		assert.is_not_nil(recreated_content)
	-- 		assert.is_true(recreated_content:match("Round Trip Task"))
	-- 		assert.is_true(recreated_content:match("Task description here"))
	-- 		assert.is_true(recreated_content:match("2025%-12%-25"))
	-- 	end)
	-- end)

	describe("3. Google to Markdown (Manual Actions)", function()
		-- Clean up before and after this entire suite
		before_each(function()
			local cleanup_done = false
			delete_all_tasks_in_list(google_to_md_list, function(err)
				cleanup_done = true
			end)

			local start = vim.loop.now()
			while not cleanup_done and (vim.loop.now() - start) < 15000 do
				vim.wait(100)
			end
		end)

		after_each(function()
			local done = false
			delete_all_tasks_in_list(google_to_md_list, function(err)
				done = true
			end)

			local start = vim.loop.now()
			while not done and (vim.loop.now() - start) < 10000 do
				vim.wait(100)
			end
		end)

		it("should sync all task variations from Google to markdown", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			-- Ensure list exists
			local list_ready = false
			api.get_or_create_list(google_to_md_list, function(list)
				list_ready = true
			end)
			wait_for_completion(5000)
			assert.is_true(list_ready)

			local tomorrow = get_tomorrow_date()
			prompt_user_action(
				string.format(
					"1. Open Google Tasks (https://tasks.google.com)\n   2. Find list: %s\n   3. Create these tasks:\n      - Manual Task\n      - Task with Description (add description: 'Test description')\n      - Completed Task (mark as complete)\n      - Task with Due Date (set to tomorrow: %s)\n      - Parent from Google (with SUBTASK under it: Child from Google)",
					google_to_md_list,
					tomorrow
				)
			)

			sync_and_wait(300000) -- 5 minute timeout for manual actions

			local normalized_name = google_to_md_list:lower():gsub("[%s_]+", "-"):gsub('[/:*?"<>|\\]', "")
			local expected_file = test_dir .. "/" .. normalized_name .. ".md"
			assert.equals(1, vim.fn.filereadable(expected_file))

			local content = read_file(expected_file)
			assert.is_not_nil(content)

			-- Verify basic tasks
			assert.is_true(content:match("Manual Task"))

			-- Verify task with description
			assert.is_true(content:match("Task with Description"))
			assert.is_true(content:match("Test description"))

			-- Verify completed task
			assert.is_true(content:match("Completed Task"))
			assert.is_true(content:match("%- %[x%]"))

			-- Verify task with due date
			assert.is_true(content:match("Task with Due Date"))
			assert.is_true(content:match(tomorrow:gsub("%-", "%%-")))

			-- Verify parent-child hierarchy
			assert.is_true(content:match("Parent from Google"))
			assert.is_true(content:match("Child from Google"))

			-- Verify subtask indentation
			local lines = {}
			for line in content:gmatch("[^\r\n]+") do
				table.insert(lines, line)
			end

			local parent_line, child_line
			for i, line in ipairs(lines) do
				if line:match("Parent from Google") then
					parent_line = i
				end
				if line:match("Child from Google") then
					child_line = i
				end
			end

			assert.is_not_nil(parent_line, "Parent task not found")
			assert.is_not_nil(child_line, "Child task not found")

			local parent_indent = lines[parent_line]:match("^(%s*)")
			local child_indent = lines[child_line]:match("^(%s*)")
			assert.is_true(#child_indent > #parent_indent, "Child should be indented more than parent")
		end)

		it("should sync changes from markdown back to Google (round-trip)", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			-- First, get the synced file from the previous test
			local normalized_name = google_to_md_list:lower():gsub("[%s_]+", "-"):gsub('[/:*?"<>|\\]', "")
			local markdown_file = test_dir .. "/" .. normalized_name .. ".md"

			-- Read the file and modify it
			local content = read_file(markdown_file)
			assert.is_not_nil(content, "Markdown file should exist from previous test")

			-- Change the description and due date
			local new_date = get_future_date(7) -- 7 days from now
			content = content:gsub("Test description", "Updated description from markdown")
			content = content:gsub("Task with Due Date", "Task with Due Date | " .. new_date)

			-- Write the modified content back
			write_file(markdown_file, content)

			print("Modified markdown file, syncing changes back to Google...")
			sync_and_wait(60000) -- Normal 60 second timeout

			-- Verify changes in Google
			local verified = false
			api.get_or_create_list(google_to_md_list, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					local task_map = {}
					for _, task in ipairs(tasks) do
						task_map[task.title] = task
					end

					-- Verify description was updated
					assert.is_not_nil(task_map["Task with Description"], "Task with Description should exist")
					assert.is_not_nil(task_map["Task with Description"].notes, "Description should exist")
					assert.is_true(
						task_map["Task with Description"].notes:match("Updated description from markdown"),
						"Description should be updated"
					)

					-- Verify due date was updated
					assert.is_not_nil(task_map["Task with Due Date"], "Task with Due Date should exist")
					assert.is_not_nil(task_map["Task with Due Date"].due, "Due date should exist")
					assert.is_true(
						task_map["Task with Due Date"].due:match(new_date:gsub("%-", "%%-")),
						"Due date should be updated to " .. new_date
					)

					verified = true
				end)
			end)

			wait_for_completion(10000)
			assert.is_true(verified, "Changes should be verified in Google")
		end)
	end)
end)
