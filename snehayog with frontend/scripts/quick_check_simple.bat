@echo off
echo.
echo [1/3] Getting dependencies...
flutter pub get
if %errorlevel% neq 0 (
    echo FAILED: Dependencies not resolved
    pause
    exit /b 1
)

echo.
echo [2/3] Running tests...
flutter test --reporter=compact
if %errorlevel% neq 0 (
    echo FAILED: Tests detected issues
    echo Check the output above for details
    pause
    exit /b 1
)

echo.
echo [3/3] Running code analysis...
flutter analyze --no-congratulate
if %errorlevel% neq 0 (
    echo FAILED: Code quality issues found
    echo Check the output above for details
    pause
    exit /b 1
)

echo.
echo SUCCESS: All checks passed!
echo Your code is ready for deployment.
pause
