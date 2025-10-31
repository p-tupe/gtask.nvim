local function cmd_auth()
	require("gtask.auth").authenticate()
end

local function cmd_sync()
	require("gtask.sync").sync_directory_with_google(function(success)
		if success then
			vim.notify("Sync completed successfully")
		else
			vim.notify("Sync failed", vim.log.levels.ERROR)
		end
	end)
end

vim.api.nvim_create_user_command("GtaskAuth", cmd_auth, {})
vim.api.nvim_create_user_command("GtaskSync", cmd_sync, {})
