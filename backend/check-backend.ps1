# PowerShell script to check if backend is running on localhost:5001

Write-Host "Checking if backend is running on localhost:5001..." -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Uri "http://localhost:5001/api/health" -Method GET -TimeoutSec 2 -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Backend IS running on localhost:5001!" -ForegroundColor Green
        Write-Host "Response: $($response.Content)" -ForegroundColor Gray
        exit 0
    }
} catch {
    Write-Host "❌ Backend is NOT running on localhost:5001" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To start the backend, run:" -ForegroundColor Cyan
    Write-Host "  npm start" -ForegroundColor White
    Write-Host "  OR" -ForegroundColor White
    Write-Host "  npm run dev  (for development with auto-reload)" -ForegroundColor White
    exit 1
}

