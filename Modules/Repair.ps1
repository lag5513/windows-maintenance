function Invoke-SystemRepair {

    Write-Host ""
    Write-Host "===== SYSTEM REPAIR =====" -ForegroundColor Cyan

    Write-Host "Running SFC..." -ForegroundColor Yellow
    sfc /scannow

    Write-Host ""
    Write-Host "Running DISM CheckHealth..." -ForegroundColor Yellow

    $CheckHealth =
        dism /Online /Cleanup-Image /CheckHealth |
        Out-String

    if ($CheckHealth -match "repairable") {

        Write-Host ""
        Write-Host "Corruption detected." -ForegroundColor Yellow

        Write-Host "Running DISM RestoreHealth..." -ForegroundColor Yellow

        dism /Online /Cleanup-Image /RestoreHealth

        Write-Host "Running validation SFC..." -ForegroundColor Yellow

        sfc /scannow
    }
    else {

        Write-Host "No corruption detected." -ForegroundColor Green
    }
}
