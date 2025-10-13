@echo off
echo.
echo ========================================
echo 🚀 Snehayog Flutter Quick Setup
echo ========================================
echo.

REM Step 1: Verify setup
echo [1/3] Verifying dependencies...
call verify_setup.bat
if errorlevel 1 (
    echo.
    echo ❌ Setup verification failed!
    echo Please fix the errors above and try again.
    pause
    exit /b 1
)

echo.
echo [2/3] Running flutter clean...
cd ..
flutter clean

echo.
echo [3/3] Getting dependencies...
flutter pub get

echo.
echo ========================================
echo ✅ Setup Complete!
echo ========================================
echo.
echo 📱 To run the app:
echo    flutter run
echo.
pause

