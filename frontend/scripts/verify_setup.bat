@echo off
echo.
echo 🔍 Verifying Vayu Flutter Setup...
echo.

REM Check if we're in the frontend directory
if not exist "pubspec.yaml" (
    echo ❌ Error: Not in frontend directory!
    echo    Please run this script from: snehayog\frontend\
    exit /b 1
)

REM Check if snehayog_monetization exists
set PACKAGE_PATH=..\packages\snehayog_monetization
if not exist "%PACKAGE_PATH%" (
    echo ❌ Error: snehayog_monetization package not found!
    echo    Expected location: %PACKAGE_PATH%
    echo.
    echo 📁 Your folder structure should be:
    echo    snehayog\
    echo    ├── backend\
    echo    ├── frontend\ ^(you are here^)
    echo    └── packages\
    echo        └── snehayog_monetization\ ^(MISSING!^)
    echo.
    echo 💡 Solution:
    echo    1. Make sure you cloned the complete repository
    echo    2. Or copy snehayog_monetization folder to the correct location
    exit /b 1
)

echo ✅ snehayog_monetization package found!

REM Check if package has pubspec.yaml
if not exist "%PACKAGE_PATH%\pubspec.yaml" (
    echo ❌ Error: snehayog_monetization\pubspec.yaml not found!
    exit /b 1
)

echo ✅ snehayog_monetization\pubspec.yaml exists!

REM Check Flutter installation
where flutter >nul 2>&1
if errorlevel 1 (
    echo ❌ Error: Flutter is not installed or not in PATH!
    echo    Install Flutter from: https://flutter.dev/docs/get-started/install
    exit /b 1
)

echo ✅ Flutter is installed
flutter --version | findstr /C:"Flutter"

REM All checks passed
echo.
echo 🎉 Setup verification passed!
echo ✅ All dependencies are in place
echo.
echo 📝 Next steps:
echo    1. Run: flutter pub get
echo    2. Run: flutter run
echo.

pause

