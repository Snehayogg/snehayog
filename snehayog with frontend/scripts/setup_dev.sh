#!/bin/bash

# Development setup script to prevent regressions
set -e

echo "🚀 Setting up development environment..."

# Install pre-commit if not installed
if ! command -v pre-commit &> /dev/null; then
    echo "Installing pre-commit..."
    pip install pre-commit
fi

# Install pre-commit hooks
echo "Installing pre-commit hooks..."
pre-commit install

# Get Flutter dependencies
echo "Getting Flutter dependencies..."
flutter pub get

# Run build runner for generated files
echo "Running build runner..."
flutter packages pub run build_runner build

# Run initial tests to ensure everything works
echo "Running initial tests..."
flutter test

# Check for any analysis issues
echo "Running static analysis..."
flutter analyze

echo "✅ Development environment setup complete!"
echo ""
echo "📋 To prevent regressions:"
echo "1. Pre-commit hooks will run automatically before each commit"
echo "2. Run 'flutter test' before pushing changes"
echo "3. Use 'flutter analyze' to catch potential issues"
echo "4. Follow the established architecture patterns in ARCHITECTURE.md"
echo ""
echo "🎯 Key commands:"
echo "  flutter test                     # Run all tests"
echo "  flutter test --coverage         # Run tests with coverage"
echo "  flutter analyze                 # Static analysis"
echo "  dart format .                   # Format code"
echo "  pre-commit run --all-files      # Run all pre-commit hooks"
