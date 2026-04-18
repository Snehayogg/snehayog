@echo off
setlocal enabledelayedexpansion

echo 📱 Running Integration Test Suite...
echo 💡 Ensure a device or emulator is connected.
echo.

:: Ensure we are in the frontend directory
pushd "%~dp0.."

call flutter test integration_test

if !errorlevel! neq 0 (
    echo.
    echo ❌ Integration tests failed!
    popd
    exit /b !errorlevel!
)

echo.
echo ✅ Integration tests passed!
echo.

popd
pause
