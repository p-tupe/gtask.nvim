vim.api.nvim_create_user_command("GtaskAuth", function()
	require("gtask.auth").authenticate()
end, {})

vim.api.nvim_create_user_command("GtaskAuthTest", function()
	require("gtask.auth").authenticate_test()
end, {})

vim.api.nvim_create_user_command("GtaskClearAuth", function()
	local success = require("gtask.auth").clear_auth()
	if success then
		vim.notify("Authentication tokens cleared successfully. You will need to re-authenticate on next API call.")
	else
		vim.notify("Failed to clear authentication tokens", vim.log.levels.ERROR)
	end
end, {})

vim.api.nvim_create_user_command("GtaskGetLists", function()
	require("gtask.api").get_task_lists(function(lists, err)
		if err then
			vim.notify("Error getting task lists: " .. err, vim.log.levels.ERROR)
			return
		end
		vim.notify("Successfully fetched task lists:")
		vim.print(lists)
	end)
end, {})

vim.api.nvim_create_user_command("GtaskGetTasks", function(opts)
	if #opts.fargs == 0 then
		vim.notify("Usage: GtaskGetTasks <task_list_id>", vim.log.levels.ERROR)
		return
	end
	local task_list_id = opts.fargs[1]

	require("gtask.api").get_tasks(task_list_id, function(tasks, err)
		if err then
			vim.notify("Error getting tasks: " .. err, vim.log.levels.ERROR)
			return
		end
		vim.notify("Successfully fetched tasks:")
		vim.print(tasks)
	end)
end, { nargs = 1 })

vim.api.nvim_create_user_command("GtaskView", function(opts)
	if #opts.fargs == 0 then
		vim.notify("Usage: GtaskView <task_list_id>", vim.log.levels.ERROR)
		return
	end
	local task_list_id = opts.fargs[1]

	require("gtask.api").get_tasks(task_list_id, function(tasks, err)
		if err then
			vim.notify("Error getting tasks: " .. err, vim.log.levels.ERROR)
			return
		end

		local lines = require("gtask.view").render_task_view(tasks.items)

		-- Create a new scratch buffer to display the tasks
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
		vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_set_current_buf(buf)
	end)
end, { nargs = 1 })

vim.api.nvim_create_user_command("GtaskSync", function(opts)
	if #opts.fargs == 0 then
		vim.notify("Usage: GtaskSync <task_list_id>", vim.log.levels.ERROR)
		return
	end
	local task_list_id = opts.fargs[1]

	require("gtask.sync").sync_buffer_with_google(task_list_id, function(success)
		if success then
			vim.notify("Sync completed successfully")
		else
			vim.notify("Sync failed", vim.log.levels.ERROR)
		end
	end)
end, { nargs = 1 })
