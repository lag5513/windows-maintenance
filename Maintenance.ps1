function Start-WindowsMaintenance {
    param(
        [ValidateSet("Repair","Updates","Both")]
        [string]$Mode
    )
# ============================================================
# MODE SELECTION
# ============================================================

if ([string]::IsNullOrWhiteSpace($Mode)) {

    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host " Windows Maintenance Utility" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Repair Only" -ForegroundColor Yellow
    Write-Host "2. Updates Only" -ForegroundColor Yellow
    Write-Host "3. Repair + Updates" -ForegroundColor Yellow
    Write-Host ""

    do {
        $Selection = Read-Host "Select an option (1-3)"
    }
    until ($Selection -in @("1","2","3"))

    switch ($Selection) {
        "1" { $Mode = "Repair" }
        "2" { $Mode = "Updates" }
        "3" { $Mode = "Both" }
    }
}

# ============================================================
# SETTINGS
# ============================================================

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$ConfirmPreference = "None"

try {
    Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop
    Write-Host "    Execution Policy set to Bypass for current session." -ForegroundColor Green
}
catch {
    Write-Warning "Unable to modify execution policy."
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RunRepair = $Mode -in @("Repair","Both")
$RunUpdates = $Mode -in @("Updates","Both")

$StartTime = Get-Date
$CorruptionDetected = $false
$Updates = $null

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " Windows Maintenance Started" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Green

# ============================================================
# REPAIR PHASE
# ============================================================

if ($RunRepair) {

    Write-Host ""
    Write-Host "===== SYSTEM REPAIR PHASE =====" -ForegroundColor Cyan

    Write-Host "[1/10] Running SFC Scan..." -ForegroundColor Yellow
    Write-Host "    Scanning protected system files..." -ForegroundColor Gray

    $SFCStart = Get-Date
    sfc /scannow
    $SFCEnd = Get-Date

    Write-Host ("    SFC completed in {0} minute(s)." -f `
        [math]::Round(($SFCEnd - $SFCStart).TotalMinutes,2)) -ForegroundColor Green

    Write-Host ""
    Write-Host "[2/10] Running DISM CheckHealth..." -ForegroundColor Yellow
    Write-Host "    Checking component store health..." -ForegroundColor Gray

    $CheckHealthOutput = dism /Online /Cleanup-Image /CheckHealth | Out-String

    if (
        $CheckHealthOutput -match "repairable" -or
        $CheckHealthOutput -match "component store is repairable"
    ) {
        $CorruptionDetected = $true
    }

    if ($CorruptionDetected) {

        Write-Host "[3/10] Running RestoreHealth..." -ForegroundColor Yellow
        Write-Host "    Repairing Windows component store..." -ForegroundColor Gray

        $RestoreStart = Get-Date

        dism /Online /Cleanup-Image /RestoreHealth

        $RestoreEnd = Get-Date

        Write-Host ("    RestoreHealth completed in {0} minute(s)." -f `
            [math]::Round(($RestoreEnd - $RestoreStart).TotalMinutes,2)) -ForegroundColor Green

        Write-Host ""
        Write-Host "[4/10] Running Validation SFC..." -ForegroundColor Yellow
        Write-Host "    Verifying repair results..." -ForegroundColor Gray

        $SFC2Start = Get-Date

        sfc /scannow

        $SFC2End = Get-Date

        Write-Host ("    Validation SFC completed in {0} minute(s)." -f `
            [math]::Round(($SFC2End - $SFC2Start).TotalMinutes,2)) -ForegroundColor Green
    }
    else {

        Write-Host "    No component store corruption detected." -ForegroundColor Green
        Write-Host "    Repair phase completed." -ForegroundColor Green
    }
}

# ============================================================
# WINDOWS UPDATE PHASE
# ============================================================

if ($RunUpdates) {

    Write-Host ""
    Write-Host "===== WINDOWS UPDATE PHASE =====" -ForegroundColor Cyan

    Write-Host "[5/10] Configuring PowerShell Gallery..." -ForegroundColor Yellow
    Write-Host "    Configuring trusted repository..." -ForegroundColor Gray

    try {
        Set-PSRepository `
            -Name PSGallery `
            -InstallationPolicy Trusted `
            -ErrorAction SilentlyContinue
    }
    catch {}

    Write-Host "[6/10] Checking NuGet Provider..." -ForegroundColor Yellow
    Write-Host "    Verifying package provider..." -ForegroundColor Gray

    try {

        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {

            Install-PackageProvider `
                -Name NuGet `
                -MinimumVersion 2.8.5.201 `
                -Force `
                -Scope AllUsers `
                -Confirm:$false

            Write-Host "    NuGet provider installed." -ForegroundColor Green
        }
        else {
            Write-Host "    NuGet provider already installed." -ForegroundColor Green
        }
    }
    catch {
        Write-Warning $_.Exception.Message
    }

    Write-Host "[7/10] Checking PSWindowsUpdate..." -ForegroundColor Yellow
    Write-Host "    Verifying update module..." -ForegroundColor Gray

    try {

        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {

            Install-Module `
                -Name PSWindowsUpdate `
                -Repository PSGallery `
                -Force `
                -AllowClobber `
                -Scope AllUsers `
                -Confirm:$false

            Write-Host "    PSWindowsUpdate module installed." -ForegroundColor Green
        }
        else {

            Write-Host "    PSWindowsUpdate module already installed." -ForegroundColor Green
        }

        Import-Module PSWindowsUpdate -Force -ErrorAction Stop

        try {
            Add-WUServiceManager `
                -MicrosoftUpdate `
                -Confirm:$false `
                -ErrorAction SilentlyContinue | Out-Null
        }
        catch {}

        Write-Host "    Update module loaded successfully." -ForegroundColor Green
    }
    catch {

        Write-Host "    Failed to load PSWindowsUpdate." -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "[8/10] Scanning for Updates..." -ForegroundColor Yellow
    Write-Host "    Searching Microsoft Update catalog..." -ForegroundColor Gray

    try {

        $Updates = Get-WindowsUpdate `
            -MicrosoftUpdate `
            -ErrorAction Stop
    }
    catch {

        Write-Warning "Initial scan failed."

        Write-Host "    Resetting Windows Update Components..." -ForegroundColor Yellow

        Reset-WUComponents -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 15

        Write-Host "    Retrying scan..." -ForegroundColor Yellow

        $Updates = Get-WindowsUpdate `
            -MicrosoftUpdate `
            -ErrorAction Stop
    }

    if ($Updates -and $Updates.Count -gt 0) {

        Write-Host "    Found $($Updates.Count) update(s)." -ForegroundColor Green

        foreach ($Update in $Updates) {
            Write-Host "        - $($Update.Title)" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "[9/10] Installing Updates..." -ForegroundColor Yellow
        Write-Host "    Installing updates. This may take some time..." -ForegroundColor Gray

        Install-WindowsUpdate `
            -MicrosoftUpdate `
            -AcceptAll `
            -IgnoreReboot `
            -Confirm:$false

        Write-Host "    Update installation completed." -ForegroundColor Green
    }
    else {

        Write-Host "    No updates available." -ForegroundColor Green
    }
}

# ============================================================
# REBOOT CHECK
# ============================================================

Write-Host ""
Write-Host "[10/10] Checking reboot status..." -ForegroundColor Yellow
Write-Host "    Checking if restart is required..." -ForegroundColor Gray

try {

    if (Get-Command Get-WURebootStatus -ErrorAction SilentlyContinue) {

        if (Get-WURebootStatus -Silent) {

            Write-Host ""
            Write-Host "****************************************" -ForegroundColor Red
            Write-Host "* REBOOT REQUIRED                      *" -ForegroundColor Red
            Write-Host "****************************************" -ForegroundColor Red
        }
        else {

            Write-Host "    No reboot required." -ForegroundColor Green
        }
    }
    else {

        Write-Host "    Unable to determine reboot status." -ForegroundColor Yellow
    }
}
catch {

    Write-Host "    Unable to determine reboot status." -ForegroundColor Yellow
}

# ============================================================
# SUMMARY
# ============================================================

$EndTime = Get-Date

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " MAINTENANCE SUMMARY" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

Write-Host "Mode       : $Mode"
Write-Host "Start Time : $StartTime"
Write-Host "End Time   : $EndTime"
Write-Host ("Duration   : {0} minutes" -f `
    [math]::Round(($EndTime - $StartTime).TotalMinutes,2))

if ($RunRepair) {
    if ($CorruptionDetected) {
        Write-Host "OS Repair      : Corruption repaired" -ForegroundColor Green
    }
    else {
        Write-Host "OS Repair      : No corruption detected" -ForegroundColor Green
    }
}

if ($RunUpdates -and $Updates) {
    Write-Host "Updates Found  : $($Updates.Count)"
}

Write-Host "======================================" -ForegroundColor Cyan
Write-Host " Windows Maintenance Complete" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

}

Start-WindowsMaintenance
