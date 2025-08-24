@echo off
echo 🚀 Running quick regression check...
echo.

echo 📦 Getting dependencies...
flutter pub get
if %errorlevel% neq 0 (
    echo ❌ Failed to get dependencies
    exit /b 1
)

echo.
echo 🧪 Running tests...
flutter test --reporter=compact
if %errorlevel% neq 0 (
    echo ❌ Tests failed - potential regression detected!
    exit /b 1
)

echo.
echo 🔍 Running static analysis...
flutter analyze --fatal-infos --no-congratulate
if %errorlevel% neq 0 (
    echo ❌ Static analysis failed - code quality issues detected!
    exit /b 1
)

echo.
echo ✅ All checks passed! No regressions detected.
echo 💡 Tip: Run this script before committing code to prevent regressions.
