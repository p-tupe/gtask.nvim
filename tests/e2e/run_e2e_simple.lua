#!/usr/bin/env -S nvim -l

-- Simple E2E Test Runner for gtask.nvim
-- Runs tests directly in Neovim without external dependencies

-- Setup
local project_root = vim.fn.getcwd()
package.path = project_root .. "/lua/?.lua;" .. package.path
vim.cmd("set runtimepath+=" .. project_root)

-- Check authentication
local token_file = vim.fn.stdpath("data") .. "/gtask_tokens.json"
local f = io.open(token_file, "r")
if not f then
	print("  Error: Not Authenticated")
	print('  Please run: nvim -c ":GtaskAuth"')
	os.exit(1)
end
f:close()

-- Initialize plugin
require("gtask").setup({
	markdown_dir = vim.fn.expand("~/gtask-e2e-test"),
	verbosity = "error",
})

-- Simple test framework
local tests_passed = 0
local tests_failed = 0
local tests_pending = 0
local current_suite = ""
local before_each_fns = {}
local after_each_fns = {}

local function describe(name, fn)
	current_suite = name
	print("\n" .. name)
	-- Reset lifecycle hooks for each describe block
	before_each_fns = {}
	after_each_fns = {}
	fn()
end

local function before_each(fn)
	table.insert(before_each_fns, fn)
end

local function after_each(fn)
	table.insert(after_each_fns, fn)
end

local function it(name, fn)
	-- Run all before_each functions
	for _, before_fn in ipairs(before_each_fns) do
		local ok, err = pcall(before_fn)
		if not ok then
			tests_failed = tests_failed + 1
			print("  ✗ " .. name .. " (before_each failed)")
			print("    Error: " .. tostring(err))
			return
		end
	end

	-- Run the actual test
	local ok, err = pcall(fn)

	-- Run all after_each functions
	for _, after_fn in ipairs(after_each_fns) do
		local ok2, err2 = pcall(after_fn)
		if not ok2 then
			print("    Warning: after_each failed: " .. tostring(err2))
		end
	end

	-- Report results
	if ok then
		tests_passed = tests_passed + 1
		print("  ✓ " .. name)
	else
		if err and tostring(err):match("^PENDING:") then
			tests_pending = tests_pending + 1
			print("  ○ " .. name .. " (pending)")
			print("    " .. tostring(err))
		else
			tests_failed = tests_failed + 1
			print("  ✗ " .. name)
			print("    Error: " .. tostring(err))
		end
	end
end

local function pending(msg)
	error("PENDING: " .. msg, 2)
end

-- Save the original assert function
local orig_assert = assert

-- Create a hybrid assert that works both as a function and a table
local test_assert = setmetatable({
	equals = function(expected, actual, msg)
		if expected ~= actual then
			error(
				string.format(
					"%s\nExpected: %s\nActual: %s",
					msg or "Assertion failed",
					tostring(expected),
					tostring(actual)
				)
			)
		end
	end,
	is_true = function(value, msg)
		if not value then
			error(msg or "Expected true but got false")
		end
	end,
	is_false = function(value, msg)
		if value then
			error(msg or "Expected false but got true")
		end
	end,
	is_not_nil = function(value, msg)
		if value == nil then
			error(msg or "Expected non-nil value")
		end
	end,
	is_nil = function(value, msg)
		if value ~= nil then
			error(msg or "Expected nil value")
		end
	end,
}, {
	-- Make it callable like the original assert
	__call = function(_, condition, message)
		return orig_assert(condition, message)
	end,
})

-- Make globals available
_G.describe = describe
_G.it = it
_G.before_each = before_each
_G.after_each = after_each
_G.pending = pending
_G.assert = test_assert

-- Load and run the E2E tests
print("\n======================================================================")
print("  GTASK.NVIM END-TO-END TESTS")
print("  Tests will run against real Google Tasks API")
print("======================================================================")

local ok, err = pcall(dofile, "tests/e2e/e2e_spec.lua")
if not ok then
	print("\nError loading E2E tests: " .. tostring(err))
	os.exit(1)
end

-- Print summary
print("\n======================================================================")
if tests_pending > 0 then
	print(string.format("  Results: %d passed, %d failed, %d pending", tests_passed, tests_failed, tests_pending))
else
	print(string.format("  Results: %d passed, %d failed", tests_passed, tests_failed))
end
print("======================================================================\n")

os.exit(tests_failed == 0 and 0 or 1)
