function Invoke-ApplicationUpdates {

    Write-Host ""
    Write-Host "===== APPLICATION UPDATES =====" -ForegroundColor Cyan

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {

        Write-Host "WinGet is not available." -ForegroundColor Red
        return
    }

    try {

        winget source update

        winget upgrade `
            --all `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements `
            --disable-interactivity

        Write-Host "Application updates completed." -ForegroundColor Green
    }
    catch {

        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}
