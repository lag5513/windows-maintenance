# ============================================================
# ELEVATION CHECK
# ============================================================

$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$ProgressPreference = "Continue"
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)

if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Host ""
    Write-Host "ERROR: Administrator privileges are required." -ForegroundColor Red
    Write-Host "Please reopen PowerShell as Administrator and run the script again." -ForegroundColor Yellow
    Write-Host ""

    Read-Host "Press Enter to close this window"

    exit 1
}

# ============================================================
# Windows Maintenance Utility
# ============================================================

$ErrorActionPreference = "Continue"


try {
    Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction
} catch {}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================================================
# FUNCTIONS
# ============================================================

function Invoke-SystemRepair {

    Write-Host ""
    Write-Host "===== SYSTEM REPAIR =====" -ForegroundColor Cyan

    Write-Host "[1/4] Running SFC Scan..." -ForegroundColor Yellow
    Start-Process cmd.exe `
    -ArgumentList '/c sfc /scannow' `
    -Wait `
    -NoNewWindow

Write-Host "    SFC Exit Code: $($sfc.ExitCode)" -ForegroundColor Gray

    Write-Host ""
    Write-Host "[2/4] Running DISM CheckHealth..." -ForegroundColor Yellow
    
    $proc = Start-Process `
    -FilePath "DISM.exe" `
    -ArgumentList "/Online /Cleanup-Image /CheckHealth" `
    -Wait `
    -NoNewWindow `
    -PassThru

    if ($proc.ExitCode -eq 0) {
        Write-Host "    DISM completed successfully." -ForegroundColor Green
    }
    else {
        Write-Host "    DISM returned exit code $($proc.ExitCode)." -ForegroundColor Yellow
    }

    if (
        $CheckHealthOutput -match "repairable" -or
        $CheckHealthOutput -match "The component store is repairable"
    ) {
        $CorruptionDetected = $true
    }
    
    if ($CorruptionDetected) {
    
        Write-Host ""
        Write-Host "[3/4] Component Store Corruption Detected" -ForegroundColor Yellow
    
        Start-Process cmd.exe `
        -ArgumentList '/c DISM /Online /Cleanup-Image /RestoreHealth' `
        -Wait `
        -NoNewWindow
    
        Write-Host ""
        Write-Host "[4/4] Running Validation SFC..." -ForegroundColor Yellow
    
        Start-Process cmd.exe `
        -ArgumentList '/c sfc /scannow' `
        -Wait `
        -NoNewWindow
    
        Write-Host "    SFC Exit Code: $($sfc.ExitCode)" -ForegroundColor Gray
    
        return "Corruption Repaired"
    }
    
    Write-Host "No corruption detected." -ForegroundColor Green
    return "No Corruption Detected"
}

function Reset-PrintSpooler {

    Write-Host ""
    Write-Host "===== PRINT SPOOLER RESET =====" -ForegroundColor Cyan

    try {

        Write-Host "Stopping Spooler Service..." -ForegroundColor Yellow

        Stop-Service Spooler -Force -ErrorAction Stop

        Start-Sleep 3

        Write-Host "Clearing Print Queue..." -ForegroundColor Yellow

        $SpoolPath = "$env:SystemRoot\System32\spool\PRINTERS"

        if (Test-Path $SpoolPath) {

            Get-ChildItem $SpoolPath -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }

        Write-Host "Starting Spooler Service..." -ForegroundColor Yellow

        Start-Service Spooler -ErrorAction Stop

        Start-Sleep 2

        if ((Get-Service Spooler).Status -eq "Running") {

            Write-Host "Print Spooler Reset Successful" -ForegroundColor Green
            return $true
        }

        return $false
    }
    catch {

        Write-Host $_.Exception.Message -ForegroundColor Red
        return $false
    }
}

function Invoke-WindowsUpdates {

    Write-Host ""
    Write-Host "===== WINDOWS UPDATES =====" -ForegroundColor Cyan

    try {

        Set-PSRepository `
            -Name PSGallery `
            -InstallationPolicy Trusted `
            -ErrorAction SilentlyContinue

        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {

            Install-PackageProvider `
                -Name NuGet `
                -MinimumVersion 2.8.5.201 `
                -Force `
                -Confirm:$false
        }

        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {

            Install-Module `
                -Name PSWindowsUpdate `
                -Force `
                -AllowClobber `
                -Confirm:$false
        }

        Import-Module PSWindowsUpdate -Force

        try {
            Add-WUServiceManager `
                -MicrosoftUpdate `
                -Confirm:$false `
                -ErrorAction SilentlyContinue | Out-Null
        }
        catch {}

        Write-Host "Scanning for Updates..." -ForegroundColor Yellow

        $Updates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction SilentlyContinue

        if ($Updates) {
            $Count = @($Updates).Count

            Write-Host "$($Count) Update(s) Found" -ForegroundColor Green

            Install-WindowsUpdate `
                -MicrosoftUpdate `
                -AcceptAll `
                -IgnoreReboot `
                -Confirm:$false

            return $Count
        }

        Write-Host "No Updates Available" -ForegroundColor Green
        return 0
    }
    catch {

        Write-Host $_.Exception.Message -ForegroundColor Red
        return 0
    }
}

function Invoke-ApplicationUpdates {

    Write-Host ""
    Write-Host "===== APPLICATION UPDATES =====" -ForegroundColor Cyan

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {

        Write-Host "Winget Not Installed" -ForegroundColor Red
        return
    }

    try {

        winget source update

        winget upgrade `
            --all `
            --silent `
            --accept-source-agreements `
            --accept-package-agreements `
            --disable-interactivity

        Write-Host "Application Updates Completed" -ForegroundColor Green
    }
    catch {

        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

function Get-RebootStatus {

    try {

        if (Get-Command Get-WURebootStatus -ErrorAction SilentlyContinue) {

            return (Get-WURebootStatus -Silent)
        }

        $Keys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        )

        foreach ($Key in $Keys) {

            if (Test-Path $Key) {
                return $true
            }
        }

        return $false
    }
    catch {
        return $false
    }
}

# ============================================================
# MENU
# ============================================================

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " Windows Maintenance Utility" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "1. Repair Windows" -ForegroundColor Yellow
Write-Host "2. Update Windows" -ForegroundColor Yellow
Write-Host "3. Repair + Update Windows" -ForegroundColor Yellow
Write-Host "4. Update Applications" -ForegroundColor Yellow
Write-Host "5. Reset Print Spooler" -ForegroundColor Yellow
Write-Host "6. Run All" -ForegroundColor Yellow
Write-Host "7. Exit" -ForegroundColor Yellow
Write-Host ""

do {
    $Selection = Read-Host "Select an option (1-7)"
}
until ($Selection -in @("1","2","3","4","5","6","7"))

$StartTime = Get-Date

$RepairStatus = ""
[int]$UpdateCount = 0
$SpoolerStatus = ""
$AppsStatus = ""

switch ($Selection) {

    "1" {
        $RepairStatus = Invoke-SystemRepair
    }

    "2" {
        $UpdateCount = Invoke-WindowsUpdates
    }

    "3" {
        $RepairStatus = Invoke-SystemRepair
        $UpdateCount = Invoke-WindowsUpdates
    }

    "4" {
        Invoke-ApplicationUpdates
        $AppsStatus = "Completed"
    }

    "5" {
        $SpoolerStatus = if (Reset-PrintSpooler) { "Completed" } else { "Failed" }
    }

    "6" {
        $RepairStatus = Invoke-SystemRepair
        $UpdateCount = Invoke-WindowsUpdates

        Invoke-ApplicationUpdates
        $AppsStatus = "Completed"

        $SpoolerStatus = if (Reset-PrintSpooler) { "Completed" } else { "Failed" }
    }

    "7" {
        Write-Host ""
        Write-Host "Exiting..." -ForegroundColor Yellow
        Read-Host "Press Enter to close"
        exit
    }
}

# ============================================================
# REBOOT STATUS
# ============================================================

$RebootRequired = Get-RebootStatus

Write-Host ""
Write-Host "===== REBOOT STATUS =====" -ForegroundColor Cyan

if ($RebootRequired) {

    Write-Host ""
    Write-Host "****************************************" -ForegroundColor Red
    Write-Host "* REBOOT REQUIRED                      *" -ForegroundColor Red
    Write-Host "****************************************" -ForegroundColor Red
}
else {

    Write-Host "No Reboot Required" -ForegroundColor Green
}

# ============================================================
# SUMMARY
# ============================================================

$EndTime = Get-Date

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " MAINTENANCE SUMMARY" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

Write-Host "Start Time  : $StartTime"
Write-Host "End Time    : $EndTime"

Write-Host ("Duration    : {0} Minutes" -f `
        [math]::Round(($EndTime - $StartTime).TotalMinutes,2))

if ($RepairStatus) {
    Write-Host "Repair      : $RepairStatus"
}

if ($SpoolerStatus) {
    Write-Host "Spooler     : $SpoolerStatus"
}

if ($AppsStatus) {
    Write-Host "Applications: $AppsStatus"
}

Write-Host "Updates     : $UpdateCount"

Write-Host "Reboot Req. : $RebootRequired"

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " Maintenance Complete" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

