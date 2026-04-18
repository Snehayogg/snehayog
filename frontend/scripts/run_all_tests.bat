@echo off
setlocal enabledelayedexpansion

echo 🚀 Starting Unified Regression Suite...
echo.

:: Ensure we are in the frontend directory
pushd "%~dp0.."

echo 📦 [1/3] Checking Dependencies...
call flutter pub get
if !errorlevel! neq 0 (
    echo ❌ Failed to get dependencies.
    popd
    exit /b !errorlevel!
)

echo.
echo 🧪 [2/3] Running Unit & Widget Tests...
call flutter test --reporter=compact
if !errorlevel! neq 0 (
    echo.
    echo ❌ Unit/Widget tests failed! Stopping suite to prevent regression.
    popd
    exit /b !errorlevel!
)
echo ✅ Unit and Widget tests passed.

echo.
echo 📱 [3/3] Running Integration Tests...
echo 💡 Note: Requires a connected device/emulator.
call flutter test integration_test
if !errorlevel! neq 0 (
    echo.
    echo ❌ Integration tests failed!
    popd
    exit /b !errorlevel!
)

echo.
echo 🎉 All tests passed successfully! Project is stable.
echo.

popd
pause
