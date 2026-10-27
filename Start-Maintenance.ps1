param(
    [ValidateSet("Repair","Updates","Apps","Spooler","Both","All")]
    [string]$Mode
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$ScriptRoot\Modules\Repair.ps1"
. "$ScriptRoot\Modules\WindowsUpdates.ps1"
. "$ScriptRoot\Modules\ApplicationUpdates.ps1"
. "$ScriptRoot\Modules\PrintSpooler.ps1"
. "$ScriptRoot\Modules\RebootStatus.ps1"

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

if (:IsNullOrWhiteSpace($Mode)) {

    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host " Windows Maintenance Utility" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "1. Repair Only" -ForegroundColor Yellow
    Write-Host "2. Windows Updates Only" -ForegroundColor Yellow
    Write-Host "3. Application Updates Only" -ForegroundColor Yellow
    Write-Host "4. Reset Print Spooler" -ForegroundColor Yellow
    Write-Host "5. Repair + Windows Updates" -ForegroundColor Yellow
    Write-Host "6. All Tasks" -ForegroundColor Yellow

    do {
        $Selection = Read-Host "Select an option (1-6)"
    }
    until ($Selection -in @("1","2","3","4","5","6"))

    switch ($Selection) {
        "1" {$Mode = "Repair"}
        "2" {$Mode = "Updates"}
        "3" {$Mode = "Apps"}
        "4" {$Mode = "Spooler"}
        "5" {$Mode = "Both"}
        "6" {$Mode = "All"}
    }
}

Write-Host ""
Write-Host "Starting maintenance..." -ForegroundColor Cyan

switch ($Mode) {

    "Repair" {
        Invoke-SystemRepair
    }

    "Updates" {
        Invoke-WindowsUpdates
    }

    "Apps" {
        Invoke-ApplicationUpdates
    }

    "Spooler" {
        Reset-PrintSpooler
    }

    "Both" {
        Invoke-SystemRepair
        Invoke-WindowsUpdates
    }

    "All" {
        Invoke-SystemRepair
        Reset-PrintSpooler
        Invoke-WindowsUpdates
        Invoke-ApplicationUpdates
    }
}

Get-MaintenanceRebootStatus
