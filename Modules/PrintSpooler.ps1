function Reset-PrintSpooler {

    Write-Host ""
    Write-Host "===== PRINT SPOOLER RESET =====" -ForegroundColor Cyan

    try {

        Stop-Service Spooler -Force

        Start-Sleep 3

        $SpoolFolder =
            "$env:SystemRoot\System32\spool\PRINTERS"

        if (Test-Path $SpoolFolder) {

            Get-ChildItem `
                $SpoolFolder `
                -Force `
                -ErrorAction SilentlyContinue |
                Remove-Item `
                -Force `
                -Recurse `
                -ErrorAction SilentlyContinue
        }

        Start-Service Spooler

        Write-Host "Print spooler reset completed." -ForegroundColor Green
    }
    catch {

        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}
