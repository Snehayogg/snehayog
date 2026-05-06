@echo off
setlocal enabledelayedexpansion

echo 🚀 Starting Centralized Fast Testing...
echo.

:: Ensure we are in the frontend directory
pushd "%~dp0.."

echo 📦 [1/4] Generating Unit/Widget Test Suite...
call dart tool/generate_test_suite.dart test test/all_tests_suite.dart
if !errorlevel! neq 0 (
    echo ❌ Failed to generate unit test suite.
)

echo.
echo 📦 [2/4] Generating Integration Test Suite...
call dart tool/generate_test_suite.dart integration_test integration_test/all_integration_tests.dart
if !errorlevel! neq 0 (
    echo ❌ Failed to generate integration test suite.
)

echo.
echo 🧪 [3/4] Running Unit and Widget Test Suite...
call flutter test test/all_tests_suite.dart --reporter=compact
if !errorlevel! neq 0 (
    echo.
    echo ❌ Unit/Widget tests failed!
) else (
    echo ✅ Unit and Widget tests passed.
)

echo.
echo 🧪 [4/4] Running Integration Test Suite...
echo 💡 Note: Integration tests require a connected device or emulator.
echo ⏳ Starting integration tests (this may take a while)...
call flutter test integration_test/all_integration_tests.dart
if !errorlevel! neq 0 (
    echo.
    echo ❌ Integration tests failed!
) else (
    echo ✅ Integration tests passed.
)

echo.
echo 🎉 Testing process finished!
echo.

popd
pause
