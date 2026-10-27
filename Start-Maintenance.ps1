$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$ScriptRoot\Modules\Repair.ps1"
. "$ScriptRoot\Modules\WindowsUpdates.ps1"
. "$ScriptRoot\Modules\ApplicationUpdates.ps1"
. "$ScriptRoot\Modules\PrintSpooler.ps1"
. "$ScriptRoot\Modules\RebootStatus.ps1"

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " Windows Maintenance Utility" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "1. Repair Windows" -ForegroundColor Yellow
Write-Host "2. Windows Updates" -ForegroundColor Yellow
Write-Host "3. Application Updates" -ForegroundColor Yellow
Write-Host "4. Reset Print Spooler" -ForegroundColor Yellow
Write-Host "5. Repair + Windows Updates" -ForegroundColor Yellow
Write-Host "6. Run Everything" -ForegroundColor Yellow
Write-Host "7. Exit" -ForegroundColor Yellow
Write-Host ""

do {
    $Selection = Read-Host "Select an option (1-7)"
}
until ($Selection -in @("1","2","3","4","5","6","7"))

switch ($Selection) {

    "1" {
        Invoke-SystemRepair
    }

    "2" {
        Invoke-WindowsUpdates
    }

    "3" {
        Invoke-ApplicationUpdates
    }

    "4" {
        Reset-PrintSpooler
    }

    "5" {
        Invoke-SystemRepair
        Invoke-WindowsUpdates
    }

    "6" {
        Invoke-SystemRepair
        Reset-PrintSpooler
        Invoke-WindowsUpdates
        Invoke-ApplicationUpdates
    }

    "7" {
        return
    }
}

Get-MaintenanceRebootStatus

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " Maintenance Complete" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

Pause
