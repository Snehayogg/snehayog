#!/bin/bash

# Ensure we are in the frontend directory
cd "$(dirname "$0")/.."

echo "📱 Running Integration Test Suite..."
echo "💡 Ensure a device or emulator is connected."
echo ""

flutter test integration_test || { echo "❌ Integration tests failed!"; exit 1; }

echo ""
echo "✅ Integration tests passed!"
echo ""
