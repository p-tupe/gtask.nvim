.PHONY: test test-unit test-e2e clean install-deps lint

# Run all tests (unit only, not E2E)
test:
	@echo "Running unit tests..."
	@busted tests/unit --pattern=_spec%.lua$

# Run only unit tests
test-unit:
	@echo "Running unit tests..."
	@busted tests/unit --pattern=_spec%.lua$

# Run only E2E tests (requires authentication)
test-e2e:
	@chmod +x tests/e2e/run_e2e_simple.lua
	@nvim -l tests/e2e/run_e2e_simple.lua

# Clean test artifacts
clean:
	@echo "Cleaning test artifacts..."
	@rm -rf /tmp/gtask_test*

# Install test dependencies
install-deps:
	@echo "Installing test dependencies..."
	@luarocks install busted || echo "busted already installed"

# Run linter (if available)
lint:
	@echo "Running linter..."
	@luacheck lua/ tests/ || echo "Install luacheck for linting: luarocks install luacheck"

# Show help
help:
	@echo "Available targets:"
	@echo "  make test          - Run unit tests only"
	@echo "  make test-unit     - Run only unit tests"
	@echo "  make test-e2e      - Run E2E tests (requires authentication)"
	@echo "  make clean         - Clean test artifacts"
	@echo "  make install-deps  - Install test dependencies"
	@echo "  make lint          - Run linter (requires luacheck)"
	@echo "  make help          - Show this help"
