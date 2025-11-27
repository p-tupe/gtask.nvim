---End-to-End Tests for gtask.nvim
---These tests perform real operations against Google Tasks API
---Requires valid authentication and internet connection

local sync = require("gtask.sync")
local store = require("gtask.store")
local api = require("gtask.api")

-- E2E test configuration
local test_dir = vim.fn.expand("~/gtask-e2e-test"):gsub("\n", "")
local test_list_name = "E2E_Test_List_" .. os.time()

-- Helper to log test progress (only for important events)
local function log(msg)
	-- Only log errors and warnings, not progress
	if msg:match("^ERROR:") or msg:match("^Warning:") then
		print("  [E2E] " .. msg)
	end
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
	-- Ensure parent directory exists
	local dir = vim.fn.fnamemodify(filepath, ":h")
	vim.fn.mkdir(dir, "p")

	local file, err = io.open(filepath, "w")
	if not file then
		error(string.format("Failed to write file: %s (error: %s)", filepath, tostring(err)))
	end
	file:write(content)
	file:close()
end

-- Helper to delete file
local function delete_file(filepath)
	os.remove(filepath)
end

-- Helper to create test markdown file
local function create_test_file(filename, content)
	local filepath = test_dir .. "/" .. filename
	write_file(filepath, content)
	return filepath
end

-- Helper to sync and wait
local function sync_and_wait()
	local done = false
	local sync_error = nil

	sync.sync_directory_with_google(function(err)
		-- Only capture actual errors (strings), not success values (true/nil)
		if type(err) == "string" then
			sync_error = err
		end
		done = true
	end)

	-- Wait for sync to complete (max 30 seconds)
	local start = vim.loop.now()
	while not done and (vim.loop.now() - start) < 30000 do
		vim.wait(100)
	end

	if sync_error then
		error("Sync failed: " .. sync_error)
	end

	if not done then
		error("Sync timed out after 30 seconds")
	end
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

			for _, task in ipairs(tasks) do
				api.delete_task(list.id, task.id, function(_, err3)
					if err3 then
						callback(err3)
						return
					end
					delete_count = delete_count + 1
					if delete_count == total then
						callback(nil)
					end
				end)
			end
		end)
	end)
end

describe("gtask.nvim E2E", function()
	-- Setup: Configure plugin for E2E testing
	before_each(function()
		log("Setting up test environment")
		log("Test directory: " .. test_dir)
		log("Test list name: " .. test_list_name)

		-- Create test directory using vim functions
		vim.fn.mkdir(test_dir, "p")

		-- Clean up any existing test files
		local files = vim.fn.glob(test_dir .. "/*.md", false, true)
		for _, file in ipairs(files) do
			vim.fn.delete(file)
		end

		-- Configure for E2E testing
		require("gtask").setup({
			markdown_dir = test_dir,
			verbosity = "error",
		})

		-- Clean up any existing tasks in the test list (from previous test)
		local cleanup_done = false
		delete_all_tasks_in_list(test_list_name, function(err)
			if err then
				log("Warning: Pre-test cleanup failed: " .. err)
			else
				log("Pre-test cleanup successful")
			end
			cleanup_done = true
		end)

		-- Wait for cleanup to complete
		local start = vim.loop.now()
		while not cleanup_done and (vim.loop.now() - start) < 5000 do
			vim.wait(50)
		end

		log("Setup complete")
	end)

	-- Cleanup after each test
	after_each(function()
		log("Cleaning up test files")
		-- Clean up test files using vim function
		vim.fn.delete(test_dir, "rf")
		log("Local cleanup complete")
	end)

	-- Final cleanup: Delete test list from Google Tasks
	after_each(function()
		log("Cleaning up test list from Google Tasks")
		local done = false
		delete_all_tasks_in_list(test_list_name, function(err)
			if err then
				log("Warning: Failed to cleanup test list: " .. err)
			else
				log("Google Tasks cleanup successful")
			end
			done = true
		end)

		-- Wait for cleanup
		local start = vim.loop.now()
		while not done and (vim.loop.now() - start) < 10000 do
			vim.wait(100)
		end

		if not done then
			log("Warning: Cleanup timed out")
		end

		-- Rate limiting: wait 3 seconds between tests to avoid quota issues
		vim.wait(3000)
	end)

	describe("1. Authentication", function()
		it("should have valid authentication", function()
			log("Checking authentication status")
			-- Check if tokens exist
			local has_tokens = store.has_tokens()

			if not has_tokens then
				log("ERROR: No authentication tokens found")
				log("Please run: nvim -c ':GtaskAuth'")
				pending("Authentication required. Run :GtaskAuth first before E2E tests.")
			end

			log("Authentication tokens found")
			assert.is_true(has_tokens)

			-- Verify tokens are loadable
			local tokens = store.load_tokens()
			assert.is_not_nil(tokens)
			assert.is_not_nil(tokens.access_token)
			log("Token validation successful")
		end)
	end)

	describe("2. Basic Task Creation - Markdown to Google", function()
		it("should create a single task from markdown", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			log("Creating test file with single task")
			-- Create markdown file with single task
			local content = string.format(
				[[# %s

	- [ ] Test Task A
	]],
				test_list_name
			)

			create_test_file("test.md", content)

			-- Sync
			sync_and_wait()

			-- Verify task was created in Google Tasks
			log("Verifying task in Google Tasks")
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					log("Found " .. #tasks .. " task(s) in Google Tasks")
					assert.equals(1, #tasks)
					assert.equals("Test Task A", tasks[1].title)
					assert.equals("needsAction", tasks[1].status)
					verified = true
				end)
			end)

			-- Wait for verification
			wait_for_completion(5000)
			assert.is_true(verified)
			log("Task verification successful")
		end)

		it("should create multiple tasks", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			local content = string.format(
				[[# %s

	- [ ] Task A
	- [ ] Task B
	- [ ] Task C
	]],
				test_list_name
			)

			create_test_file("test.md", content)
			sync_and_wait()

			-- Verify
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(3, #tasks)
					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)

		it("should create task with description", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			local content = string.format(
				[[# %s

	- [ ] Task with Description

	  This is the description.
	  It has multiple lines.
	]],
				test_list_name
			)

			create_test_file("test.md", content)
			sync_and_wait()

			-- Verify
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(1, #tasks)
					assert.is_not_nil(tasks[1].notes)
					assert.is_true(tasks[1].notes:match("This is the description"))
					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)

		it("should create task with due date", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			local content = string.format(
				[[# %s

	- [ ] Task with Date | 2025-12-25
	]],
				test_list_name
			)

			create_test_file("test.md", content)
			sync_and_wait()

			-- Verify
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(1, #tasks)
					assert.is_not_nil(tasks[1].due)
					assert.is_true(tasks[1].due:match("2025%-12%-25"))
					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)

		it("should create completed task", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			local content = string.format(
				[[# %s

	- [x] Completed Task
	]],
				test_list_name
			)

			create_test_file("test.md", content)
			sync_and_wait()

			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(1, #tasks)
					assert.equals("completed", tasks[1].status)
					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)
	end)

	describe("3. Subtasks and Hierarchy", function()
		it("should create subtasks with proper parent relationship", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			local content = string.format(
				[[# %s

	- [ ] Parent Task
	  - [ ] Subtask 1
	  - [ ] Subtask 2
	]],
				test_list_name
			)

			create_test_file("test.md", content)
			sync_and_wait()

			-- Verify hierarchy
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(3, #tasks)

					-- Find parent and subtasks
					local parent = nil
					local subtasks = {}

					for _, task in ipairs(tasks) do
						if task.title == "Parent Task" then
							parent = task
						elseif task.parent then
							table.insert(subtasks, task)
						end
					end

					assert.is_not_nil(parent)
					assert.equals(2, #subtasks)

					-- Verify subtasks have correct parent
					for _, subtask in ipairs(subtasks) do
						assert.equals(parent.id, subtask.parent)
					end

					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)

    --
		-- TODO: The one below fails, needs work to handle 2+ level heirarchy
    --

		it("should handle nested subtasks", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			local content = string.format(
				[[# %s

	- [ ] Parent
	  - [ ] Child
	    - [ ] Grandchild
	]],
				test_list_name
			)

			create_test_file("test.md", content)
			sync_and_wait()

			-- Verify three-level hierarchy
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(3, #tasks)

					-- Build hierarchy map
					local task_map = {}
					for _, task in ipairs(tasks) do
						task_map[task.title] = task
					end

					-- Verify hierarchy
					assert.is_nil(task_map["Parent"].parent)
					assert.equals(task_map["Parent"].id, task_map["Child"].parent)
					assert.equals(task_map["Child"].id, task_map["Grandchild"].parent)

					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)

		------------------------
	end)

	describe("4. Task Updates", function()
		--
		-- TODO: The one below deletes and creates new task, needs to work with gtask ids
		--
		it("should update task title", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			-- Create initial task
			local content = string.format(
				[[# %s

	- [ ] Original Title
	]],
				test_list_name
			)

			local filepath = create_test_file("test.md", content)
			sync_and_wait()

			-- Update title
			content = string.format(
				[[# %s

	- [ ] Updated Title
	]],
				test_list_name
			)
			write_file(filepath, content)
			sync_and_wait()

			-- Verify update
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(1, #tasks)
					assert.equals("Updated Title", tasks[1].title)
					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)

		--
		-- TODO: The one below deletes the task and doesn't sync completed one, needs to work with gtask ids
		--
		it("should update completion status", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			-- Create incomplete task
			local content = string.format(
				[[# %s

	- [ ] Task to Complete
	]],
				test_list_name
			)

			local filepath = create_test_file("test.md", content)
			sync_and_wait()

			content = string.format(
				[[# %s

	- [x] Task to Complete
	]],
				test_list_name
			)
			write_file(filepath, content)
			sync_and_wait()

			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(1, #tasks)
					assert.equals("completed", tasks[1].status)
					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)
	end)

	describe("5. Google to Markdown Sync", function()
		it("should sync tasks created in Google to markdown", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			-- Create task directly in Google Tasks
			local task_created = false
			api.get_or_create_list(test_list_name, function(list)
				api.create_task(list.id, {
					title = "Google Task",
					status = "needsAction",
				}, function()
					task_created = true
				end)
			end)

			-- Wait for task creation
			wait_for_completion(5000)
			assert.is_true(task_created)

			-- Sync to markdown
			sync_and_wait()

			--
			-- TODO: This does not check for an exact list name, just matches task title
			--
			-- Verify markdown file was created
			local expected_file = test_dir .. "/e2e_test_list_" .. os.time() .. ".md"
			-- The filename is normalized, we need to find it
			local files = vim.fn.glob(test_dir .. "/*.md", false, true)
			assert.is_true(#files > 0)

			-- Read and verify content
			local found_task = false
			for _, file in ipairs(files) do
				local content = read_file(file)
				if content and content:match("Google Task") then
					found_task = true
					break
				end
			end

			assert.is_true(found_task)
		end)
	end)

	describe("6. Task Deletion", function()
		it("should delete task from Google when removed from markdown", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			-- Create task
			local content = string.format(
				[[# %s

	- [ ] Task to Delete
	]],
				test_list_name
			)

			local filepath = create_test_file("test.md", content)
			sync_and_wait()

			-- Verify task exists
			local task_exists = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					task_exists = #(response.items or {}) == 1
				end)
			end)
			wait_for_completion(5000)
			assert.is_true(task_exists)

			-- Delete task from markdown
			content = string.format(
				[[# %s
	]],
				test_list_name
			)
			write_file(filepath, content)
			sync_and_wait()

			-- Verify task deleted from Google
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(0, #tasks)
					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)
	end)

	describe("7. Edge Cases", function()
		it("should handle special characters in task title", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			local content = string.format(
				[[# %s

	- [ ] Task with "quotes" and 'apostrophes'
	]],
				test_list_name
			)

			create_test_file("test.md", content)
			sync_and_wait()

			-- Verify
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(1, #tasks)
					assert.is_true(tasks[1].title:match("quotes"))
					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)

		it("should handle unicode characters", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			local content = string.format(
				[[# %s

	- [ ] Task with émojis 🎉 and 中文字符
	]],
				test_list_name
			)

			create_test_file("test.md", content)
			sync_and_wait()

			-- Verify
			local verified = false
			api.get_or_create_list(test_list_name, function(list)
				api.get_tasks(list.id, function(response)
					local tasks = response.items or {}
					assert.equals(1, #tasks)
					assert.is_true(tasks[1].title:match("émojis"))
					verified = true
				end)
			end)

			wait_for_completion(5000)
			assert.is_true(verified)
		end)
	end)

	describe("8. Round-Trip Tests", function()
		--
		-- TODO: This one is a bug - it deletes all tasks if a list is deleted
		-- The list should be recreated
		--
		it("should preserve data through Markdown→Google→Markdown cycle", function()
			if not store.has_tokens() then
				pending("Authentication required")
			end

			local original_content = string.format(
				[[# %s

		- [ ] Round Trip Task | 2025-12-25

		  Task description here
		]],
				test_list_name
			)

			local filepath = create_test_file("test.md", original_content)
			sync_and_wait()

			-- Delete markdown file
			delete_file(filepath)

			-- Sync again (should recreate from Google)
			sync_and_wait()

			-- Verify file was recreated
			local files = vim.fn.glob(test_dir .. "/*.md", false, true)
			assert.is_true(#files > 0)

			-- Verify content
			local found = false
			for _, file in ipairs(files) do
				local content = read_file(file)
				if content and content:match("Round Trip Task") then
					assert.is_true(content:match("Task description here"))
					assert.is_true(content:match("2025%-12%-25"))
					found = true
					break
				end
			end

			assert.is_true(found)
		end)
	end)
end)
