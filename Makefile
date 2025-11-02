.PHONY: test test-unit test-e2e test-verbose test-coverage clean install-deps

# Run all tests
test:
	@echo "Running all tests..."
	@busted --pattern=_spec%.lua$

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
	@echo "  make test          - Run all tests"
	@echo "  make test-unit     - Run only unit tests"
	@echo "  make test-e2e      - Run only E2E tests"
	@echo "  make test-verbose  - Run tests with verbose output"
	@echo "  make test-coverage - Run tests with coverage report"
	@echo "  make clean         - Clean test artifacts"
	@echo "  make install-deps  - Install test dependencies"
	@echo "  make lint          - Run linter (requires luacheck)"
	@echo "  make help          - Show this help"
