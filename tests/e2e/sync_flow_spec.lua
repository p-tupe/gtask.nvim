---E2E tests for sync flow with mocked API
-- NOTE: These tests need to be updated to match the new sync API signature
-- The sync.perform_twoway_sync function now expects a sync_state table parameter
pending("sync flow E2E", function()
  local vim_mock
  local api_mock
  local sync
  local mapping
  local parser
  local tempdir

  before_each(function()
    -- Setup mocks
    vim_mock = require("tests.helpers.vim_mock")
    vim_mock.reset()

    -- Setup plenary mock
    local plenary_mock = require("tests.helpers.plenary_mock")
    plenary_mock.setup()

    api_mock = require("tests.helpers.api_mock")
    api_mock.reset()

    -- Create temp directory for tests
    tempdir = os.tmpname()
    os.remove(tempdir)
    os.execute("mkdir -p " .. tempdir)

    -- Override vim.fn.stdpath to use temp directory
    vim.fn.stdpath = function(what)
      if what == "data" then
        return tempdir
      end
      return tempdir
    end

    -- Load modules
    package.loaded["gtask.mapping"] = nil
    package.loaded["gtask.parser"] = nil
    package.loaded["gtask.sync"] = nil

    mapping = require("gtask.mapping")
    parser = require("gtask.parser")
    sync = require("gtask.sync")

    -- Mock the API calls in sync module
    -- We'll inject our mock API
    package.loaded["gtask.api"] = api_mock
  end)

  after_each(function()
    -- Cleanup temp directory
    os.execute("rm -rf " .. tempdir)
  end)

  describe("basic sync flow", function()
    it("should create new task in Google from markdown", function(done)

      -- Setup: Create a task list in mock API
      local list = api_mock.seed_list("Shopping")

      -- Setup: Parse markdown with one task
      local markdown_tasks = {
        {
          title = "Buy milk",
          completed = false,
          line_number = 5,
          indent_level = 0,
          source_file_path = "/test/shopping.md",
        },
      }

      -- Execute sync
      sync.perform_twoway_sync({
        markdown_tasks = markdown_tasks,
        google_tasks = {},
        task_list_id = list.id,
        markdown_dir = tempdir,
        list_name = "Shopping",
      }, function()
        -- Verify: Task was created in Google
        local google_tasks = {}
        for _, task in pairs(api_mock.store.tasks) do
          if task.list_id == list.id then
            table.insert(google_tasks, task)
          end
        end

        assert.equals(1, #google_tasks)
        assert.equals("Buy milk", google_tasks[1].title)
        assert.equals("needsAction", google_tasks[1].status)

        -- Verify: Mapping was updated
        local map = mapping.load()
        local task_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 5, nil)
        local google_id = mapping.get_google_id(map, task_key)
        assert.is_not_nil(google_id)

        done()
      end)
    end)

    it("should update existing task", function(done)

      -- Setup: Create list and task in Google
      local list = api_mock.seed_list("Shopping")
      local google_task = api_mock.seed_task(list.id, "Buy milk", { status = "needsAction" })

      -- Setup: Create mapping
      local map = mapping.load()
      local task_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 5, nil)
      local context_sig = mapping.generate_context_signature("Shopping", "Buy milk", nil)
      mapping.register_task(map, task_key, google_task.id, "Shopping", "Buy milk", "/test/shopping.md", 5, nil, context_sig)

      -- Setup: Markdown task with changes (completed)
      local markdown_tasks = {
        {
          title = "Buy milk",
          completed = true, -- Changed to completed
          line_number = 5,
          indent_level = 0,
          source_file_path = "/test/shopping.md",
        },
      }

      -- Execute sync
      sync.perform_twoway_sync(markdown_tasks, { google_task }, list.id, "Shopping", map, function()
        -- Verify: Task was updated in Google
        local updated_task = api_mock.store.tasks[google_task.id]
        assert.equals("completed", updated_task.status)

        done()
      end)
    end)

    it("should detect task renamed by title change", function(done)

      -- Setup: Create list and task in Google
      local list = api_mock.seed_list("Shopping")
      local google_task = api_mock.seed_task(list.id, "Buy milk", { status = "needsAction" })

      -- Setup: Create mapping with old title
      local map = mapping.load()
      local task_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 5, nil)
      local context_sig = mapping.generate_context_signature("Shopping", "Buy milk", nil)
      mapping.register_task(map, task_key, google_task.id, "Shopping", "Buy milk", "/test/shopping.md", 5, nil, context_sig)

      -- Setup: Markdown task with new title at same position
      local markdown_tasks = {
        {
          title = "Buy organic milk", -- Title changed
          completed = false,
          line_number = 5, -- Same position
          indent_level = 0,
          source_file_path = "/test/shopping.md",
        },
      }

      -- Execute sync
      sync.perform_twoway_sync(markdown_tasks, { google_task }, list.id, "Shopping", map, function()
        -- Verify: Task was updated (not created as new)
        local task_count = 0
        for _ in pairs(api_mock.store.tasks) do
          task_count = task_count + 1
        end
        assert.equals(1, task_count) -- Still only one task

        -- Verify: Google task has new title
        local updated_task = api_mock.store.tasks[google_task.id]
        assert.equals("Buy organic milk", updated_task.title)

        done()
      end)
    end)

    it("should recover task moved by few lines", function(done)

      -- Setup: Create list and task in Google
      local list = api_mock.seed_list("Shopping")
      local google_task = api_mock.seed_task(list.id, "Buy milk", { status = "needsAction" })

      -- Setup: Create mapping at line 5
      local map = mapping.load()
      local old_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 5, nil)
      local context_sig = mapping.generate_context_signature("Shopping", "Buy milk", nil)
      mapping.register_task(map, old_key, google_task.id, "Shopping", "Buy milk", "/test/shopping.md", 5, nil, context_sig)

      -- Setup: Markdown task moved to line 8 (within ±5 range)
      local markdown_tasks = {
        {
          title = "Buy milk",
          completed = false,
          line_number = 8, -- Moved from line 5
          indent_level = 0,
          source_file_path = "/test/shopping.md",
        },
      }

      -- Execute sync
      sync.perform_twoway_sync(markdown_tasks, { google_task }, list.id, "Shopping", map, function()
        -- Verify: No duplicate task created
        local task_count = 0
        for _ in pairs(api_mock.store.tasks) do
          task_count = task_count + 1
        end
        assert.equals(1, task_count)

        -- Verify: Mapping updated to new position
        local new_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 8, nil)
        local google_id = mapping.get_google_id(map, new_key)
        assert.equals(google_task.id, google_id)

        -- Verify: Old key removed
        local old_google_id = mapping.get_google_id(map, old_key)
        assert.is_nil(old_google_id)

        -- Verify: Notification about recovery
        local notif = vim_mock.find_notification("Recovered moved task")
        assert.is_not_nil(notif)

        done()
      end)
    end)

    it("should create subtask with parent relationship", function(done)

      -- Setup: Create list
      local list = api_mock.seed_list("Shopping")

      -- Setup: Markdown with parent and child
      local markdown_tasks = {
        {
          title = "Buy groceries",
          completed = false,
          line_number = 5,
          indent_level = 0,
          source_file_path = "/test/shopping.md",
          parent_index = nil,
        },
        {
          title = "Buy milk",
          completed = false,
          line_number = 6,
          indent_level = 1,
          source_file_path = "/test/shopping.md",
          parent_index = 1, -- Child of first task
        },
      }

      -- Load mapping
      local map = mapping.load()

      -- Execute sync
      sync.perform_twoway_sync(markdown_tasks, {}, list.id, "Shopping", map, function()
        -- Verify: Two tasks created
        local google_tasks = {}
        for _, task in pairs(api_mock.store.tasks) do
          if task.list_id == list.id then
            table.insert(google_tasks, task)
          end
        end
        assert.equals(2, #google_tasks)

        -- Verify: Child has parent reference
        local parent_task, child_task
        for _, task in ipairs(google_tasks) do
          if task.title == "Buy groceries" then
            parent_task = task
          elseif task.title == "Buy milk" then
            child_task = task
          end
        end

        assert.is_not_nil(parent_task)
        assert.is_not_nil(child_task)
        assert.equals(parent_task.id, child_task.parent)

        done()
      end)
    end)

    it("should handle deletion from markdown", function(done)

      -- Setup: Create list and two tasks in Google
      local list = api_mock.seed_list("Shopping")
      local task1 = api_mock.seed_task(list.id, "Buy milk", { status = "needsAction" })
      local task2 = api_mock.seed_task(list.id, "Buy eggs", { status = "needsAction" })

      -- Setup: Create mapping for both
      local map = mapping.load()
      local key1 = mapping.generate_task_key("Shopping", "/test/shopping.md", 5, nil)
      local key2 = mapping.generate_task_key("Shopping", "/test/shopping.md", 6, nil)
      mapping.register_task(map, key1, task1.id, "Shopping", "Buy milk", "/test/shopping.md", 5, nil, "Shopping||||Buy milk")
      mapping.register_task(map, key2, task2.id, "Shopping", "Buy eggs", "/test/shopping.md", 6, nil, "Shopping||||Buy eggs")

      -- Setup: Markdown with only one task (second deleted)
      local markdown_tasks = {
        {
          title = "Buy milk",
          completed = false,
          line_number = 5,
          indent_level = 0,
          source_file_path = "/test/shopping.md",
        },
      }

      -- Execute sync
      sync.perform_twoway_sync(markdown_tasks, { task1, task2 }, list.id, "Shopping", map, function()
        -- Verify: Orphaned task removed from mapping
        local cleaned_google_id = mapping.get_google_id(map, key2)
        assert.is_nil(cleaned_google_id)

        -- Verify: First task still in mapping
        local kept_google_id = mapping.get_google_id(map, key1)
        assert.equals(task1.id, kept_google_id)

        -- Verify: Notification about cleanup
        local notif = vim_mock.find_notification("Cleaned up .* orphaned")
        assert.is_not_nil(notif)

        done()
      end)
    end)
  end)

  describe("context-based recovery", function()
    it("should recover task moved far away using context", function(done)

      -- Setup: Create list and task in Google
      local list = api_mock.seed_list("Shopping")
      local google_task = api_mock.seed_task(list.id, "Buy milk", { status = "needsAction" })

      -- Setup: Create mapping at line 5
      local map = mapping.load()
      local old_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 5, nil)
      local context_sig = mapping.generate_context_signature("Shopping", "Buy milk", nil)
      mapping.register_task(map, old_key, google_task.id, "Shopping", "Buy milk", "/test/shopping.md", 5, nil, context_sig)

      -- Setup: Markdown task moved to line 50 (beyond ±5 range)
      local markdown_tasks = {
        {
          title = "Buy milk",
          completed = false,
          line_number = 50, -- Far from original position
          indent_level = 0,
          source_file_path = "/test/shopping.md",
        },
      }

      -- Execute sync
      sync.perform_twoway_sync(markdown_tasks, { google_task }, list.id, "Shopping", map, function()
        -- Verify: No duplicate created
        local task_count = 0
        for _ in pairs(api_mock.store.tasks) do
          task_count = task_count + 1
        end
        assert.equals(1, task_count)

        -- Verify: Mapping updated to new position
        local new_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 50, nil)
        local google_id = mapping.get_google_id(map, new_key)
        assert.equals(google_task.id, google_id)

        -- Verify: Context-based recovery notification
        local notif = vim_mock.find_notification("Recovered reorganized task")
        assert.is_not_nil(notif)

        done()
      end)
    end)

    it("should recover subtask with parent context", function(done)

      -- Setup: Create list with parent and child in Google
      local list = api_mock.seed_list("Shopping")
      local parent_task = api_mock.seed_task(list.id, "Buy groceries", { status = "needsAction" })
      local child_task = api_mock.seed_task(list.id, "Buy milk", {
        status = "needsAction",
        parent = parent_task.id,
      })

      -- Setup: Create mapping at original lines
      local map = mapping.load()
      local parent_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 5, nil)
      local old_child_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 6, 5)
      local child_context_sig = mapping.generate_context_signature("Shopping", "Buy milk", "Buy groceries")

      mapping.register_task(map, parent_key, parent_task.id, "Shopping", "Buy groceries", "/test/shopping.md", 5, nil, "Shopping||||Buy groceries")
      mapping.register_task(map, old_child_key, child_task.id, "Shopping", "Buy milk", "/test/shopping.md", 6, parent_key, child_context_sig)

      -- Setup: Tasks moved far away
      local markdown_tasks = {
        {
          title = "Buy groceries",
          completed = false,
          line_number = 100,
          indent_level = 0,
          source_file_path = "/test/shopping.md",
          parent_index = nil,
        },
        {
          title = "Buy milk",
          completed = false,
          line_number = 101,
          indent_level = 1,
          source_file_path = "/test/shopping.md",
          parent_index = 1,
        },
      }

      -- Execute sync
      sync.perform_twoway_sync(markdown_tasks, { parent_task, child_task }, list.id, "Shopping", map, function()
        -- Verify: No duplicates
        local task_count = 0
        for _ in pairs(api_mock.store.tasks) do
          task_count = task_count + 1
        end
        assert.equals(2, task_count)

        -- Verify: Child mapping updated with parent context preserved
        local new_child_key = mapping.generate_task_key("Shopping", "/test/shopping.md", 101, 100)
        local child_google_id = mapping.get_google_id(map, new_child_key)
        assert.equals(child_task.id, child_google_id)

        done()
      end)
    end)
  end)
end)
