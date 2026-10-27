function Get-MaintenanceRebootStatus {

    Write-Host ""
    Write-Host "===== REBOOT STATUS =====" -ForegroundColor Cyan

    try {

        if (Get-Command Get-WURebootStatus -ErrorAction SilentlyContinue) {

            if (Get-WURebootStatus -Silent) {

                Write-Host ""
                Write-Host "REBOOT REQUIRED" -ForegroundColor Red
            }
            else {

                Write-Host "No reboot required." -ForegroundColor Green
            }
        }
        else {

            $PendingReboot = Test-Path `
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

            if ($PendingReboot) {

                Write-Host "REBOOT REQUIRED" -ForegroundColor Red
            }
            else {

                Write-Host "No reboot required." -ForegroundColor Green
            }
        }
    }
    catch {

        Write-Host "Unable to determine reboot status." -ForegroundColor Yellow
    }
}
