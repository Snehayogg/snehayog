#!/bin/bash

# Ensure we are in the frontend directory
cd "$(dirname "$0")/.."

echo "🚀 Starting Unified Regression Suite..."
echo ""

echo "📦 [1/3] Checking Dependencies..."
flutter pub get || { echo "❌ Failed to get dependencies"; exit 1; }

echo ""
echo "🧪 [2/3] Running Unit & Widget Tests..."
flutter test --reporter=compact || { echo "❌ Unit/Widget tests failed! Stopping suite."; exit 1; }
echo "✅ Unit and Widget tests passed."

echo ""
echo "📱 [3/3] Running Integration Tests..."
echo "💡 Note: Requires a connected device/emulator."
flutter test integration_test || { echo "❌ Integration tests failed!"; exit 1; }

echo ""
echo "🎉 All tests passed successfully! Project is stable."
echo ""
