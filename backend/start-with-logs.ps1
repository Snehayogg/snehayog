# PowerShell script to start server with logging
# Usage: .\start-with-logs.ps1

# Create logs directory if it doesn't exist
if (-not (Test-Path logs)) {
    New-Item -ItemType Directory -Path logs
    Write-Host "✅ Created logs directory" -ForegroundColor Green
}

# Start server with output redirected to log file
Write-Host "🚀 Starting server with logging enabled..." -ForegroundColor Cyan
Write-Host "📝 Logs will be saved to: logs/backend.log" -ForegroundColor Yellow
Write-Host "💡 Press Ctrl+C to stop the server" -ForegroundColor Yellow
Write-Host ""

# Start npm and redirect both stdout and stderr to log file
npm start *> logs/backend.log

