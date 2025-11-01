# gtask.nvim Tests

This directory contains the test suite for gtask.nvim, including unit tests and end-to-end tests.

## Structure

```
tests/
├── unit/               # Unit tests for individual modules
│   ├── mapping_spec.lua       # Tests for mapping.lua
│   ├── parser_spec.lua        # Tests for parser.lua
│   └── sync_similarity_spec.lua  # Tests for sync similarity functions
├── e2e/                # End-to-end integration tests
│   └── sync_flow_spec.lua     # Tests for complete sync flows
├── helpers/            # Test utilities and mocks
│   ├── vim_mock.lua           # Mock vim API
│   ├── json.lua               # Simple JSON encoder/decoder
│   └── api_mock.lua           # Mock Google Tasks API
└── fixtures/           # Test data files (if needed)
```

## Prerequisites

Install busted (Lua testing framework):

```bash
# Using luarocks
luarocks install busted

# Or with Homebrew on macOS
brew install luarocks
luarocks install busted
```

## Running Tests

### Run all tests
```bash
busted
```

### Run only unit tests
```bash
busted --pattern=_spec%.lua$ tests/unit
```

### Run only E2E tests
```bash
busted --pattern=_spec%.lua$ tests/e2e
```

### Run specific test file
```bash
busted tests/unit/mapping_spec.lua
```

### Run with verbose output
```bash
busted --verbose
```

### Run with coverage (requires luacov)
```bash
busted --coverage
luacov
cat luacov.report.out
```

## Writing Tests

### Unit Tests

Unit tests focus on testing individual functions in isolation:

```lua
describe("module_name", function()
  local module
  local vim_mock

  before_each(function()
    vim_mock = require("tests.helpers.vim_mock")
    vim_mock.reset()
    module = require("gtask.module_name")
  end)

  it("should do something", function()
    local result = module.some_function()
    assert.equals(expected, result)
  end)
end)
```

### E2E Tests

E2E tests verify complete workflows with mocked external dependencies:

```lua
describe("feature E2E", function()
  local api_mock
  local sync

  before_each(function()
    api_mock = require("tests.helpers.api_mock")
    api_mock.reset()

    -- Mock the API module
    package.loaded["gtask.api"] = api_mock
    sync = require("gtask.sync")
  end)

  it("should complete full sync flow", function(done)
    async()
    -- Setup test data
    -- Execute operation
    -- Verify results
    done()
  end)
end)
```

## Test Helpers

### vim_mock.lua

Provides mock vim API for testing:

```lua
local vim_mock = require("tests.helpers.vim_mock")

-- Reset state between tests
vim_mock.reset()

-- Access notifications
local notifications = vim_mock.get_notifications()
local notif = vim_mock.find_notification("pattern")
```

### api_mock.lua

Provides mock Google Tasks API:

```lua
local api_mock = require("tests.helpers.api_mock")

-- Reset API state
api_mock.reset()

-- Seed test data
local list = api_mock.seed_list("Shopping")
local task = api_mock.seed_task(list.id, "Buy milk")

-- Use like real API
api_mock.get_tasks(list.id, function(response, err)
  -- Test callback
end)
```

## CI Integration

To run tests in CI (GitHub Actions example):

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Lua
        run: |
          sudo apt-get update
          sudo apt-get install -y lua5.1 luarocks
      - name: Install busted
        run: luarocks install busted
      - name: Run tests
        run: busted --verbose
```

## Test Coverage

Current test coverage includes:

- ✅ Mapping module (53 passing tests)
  - Position-based key generation
  - Context signature generation
  - Tiered matching (exact, nearby, context)
  - Task registration and lookup
  - Position updates and orphan cleanup
- ✅ Parser module (53 passing tests)
  - Task line parsing with dates/times
  - Description parsing with indentation
  - Hierarchy building
  - Full document parsing
- ⏸️  E2E sync flow (pending - needs API signature updates)
- ⏸️  Similarity functions (pending - local functions, need export or indirect testing)
- ❌ API module (uses real HTTP, needs separate integration tests)
- ❌ Auth module (uses real HTTP, needs separate integration tests)

**Test Results:** 53 successes / 0 failures / 0 errors / 8 pending

## Known Limitations

1. **Local Functions**: Some internal functions (like `calculate_similarity` in sync.lua) are local and can't be tested directly. They're tested indirectly through the public API.

2. **Async Operations**: Busted's async support requires callbacks with `done()`. Real async/await patterns may behave differently.

3. **File I/O**: File system operations use real `io.open()`. For true isolation, consider mocking the file system.

4. **HTTP Requests**: The API and auth modules make real HTTP requests. These are not covered by the current test suite and should be tested separately with VCR-style fixtures or integration tests.

## Future Improvements

- [ ] Add integration tests for API module with recorded HTTP fixtures
- [ ] Add integration tests for auth flow
- [ ] Extract local functions to testable utility modules
- [ ] Add property-based testing for parsers
- [ ] Add performance benchmarks
- [ ] Add mutation testing to verify test quality
