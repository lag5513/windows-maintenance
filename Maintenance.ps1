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

#$ErrorActionPreference = "Continue"


Write-Host "Configuring PowerShell execution policy..." -ForegroundColor Yellow

try {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "Unable to modify execution policy."
}

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

    Write-Host ""
    Write-Host "[2/4] Running DISM CheckHealth..." -ForegroundColor Yellow

   $CheckHealthOutput = & DISM.exe `
    /Online `
    /Cleanup-Image `
    /CheckHealth 2>&1 |
    Out-String

    $CorruptionDetected = $false

    $CorruptionDetected = $CheckHealthOutput -match "repairable"
    
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
        
            Write-Host "Installing NuGet provider..." -ForegroundColor Yellow
        
            Install-PackageProvider `
                -Name NuGet `
                -MinimumVersion 2.8.5.201 `
                -Force `
                -Scope CurrentUser `
                -Confirm:$false
        
            Import-PackageProvider NuGet -Force
        }
        
        Write-Host "NuGet provider ready." -ForegroundColor Green

        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {

            Install-Module `
                -Name PSWindowsUpdate `
                -Force `
                -AllowClobber `
                -Confirm:$false
        }

        $ModulePath = Get-Module `
                    -ListAvailable `
                    -Name PSWindowsUpdate |
                    Sort-Object Version -Descending |
                    Select-Object -First 1

        if ($ModulePath) {
        
            Unblock-File `
                -Path $ModulePath.Path `
                -ErrorAction SilentlyContinue
        
            Import-Module `
                $ModulePath.Path `
                -Force `
                -DisableNameChecking `
                -ErrorAction Stop
        }
        else {
        
            throw "PSWindowsUpdate module not found."
        }

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
                -Confirm:$false `
                -Verbose | Out-Null

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

function Repair-SystemClock {

    Write-Host ""
    Write-Host "===== SYSTEM CLOCK REPAIR =====" -ForegroundColor Cyan
    Write-Host ""

    try {

        $CurrentSource = (w32tm /query /source 2>&1)

        Write-Host "Current Time Source:" -ForegroundColor Yellow
        Write-Host "   $CurrentSource" -ForegroundColor Green
        Write-Host ""

        $Proceed = Read-Host "Do you want to repair Windows Time Service? (Y/N)"

        if ($Proceed -notmatch '^(Y|y)$') {

            Write-Host "Clock repair cancelled." -ForegroundColor Yellow
            return $false
        }

        $DomainJoined = (Get-CimInstance Win32_ComputerSystem).PartOfDomain

        Write-Host ""
        Write-Host "Restarting Windows Time Service..." -ForegroundColor Yellow

        Stop-Service w32time -Force -ErrorAction SilentlyContinue

        w32tm /unregister | Out-Null
        w32tm /register | Out-Null

        Start-Service w32time

        if ($DomainJoined) {

            Write-Host ""
            Write-Host "Domain-joined computer detected." -ForegroundColor Cyan
            Write-Host "Configuring domain hierarchy synchronization..." -ForegroundColor Yellow

            w32tm /config /syncfromflags:domhier
            w32tm /config /update

        }
        else {

            Write-Host ""
            Write-Host "Standalone computer detected." -ForegroundColor Cyan
            Write-Host "Configuring public NTP servers..." -ForegroundColor Yellow

            w32tm /config /manualpeerlist:"0.pool.ntp.org,1.pool.ntp.org" | Out-Null
            w32tm /config /syncfromflags:manual | Out-Null
            w32tm /config /update | Out-Null
        }

        Write-Host ""
        Write-Host "Forcing time synchronization..." -ForegroundColor Yellow

        w32tm /resync

        Start-Sleep -Seconds 3

        Write-Host ""
        Write-Host "Updated Time Source:" -ForegroundColor Yellow

        w32tm /query /source

        Write-Host ""
        Write-Host "Clock repair completed successfully." -ForegroundColor Green

        return $true
    }
    catch {

        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Red

        return $false
    }
}

# ============================================================
# MENU
# ============================================================

do {

    Clear-Host

    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host " Windows Maintenance Utility" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host " 1. Repair Windows"         -ForegroundColor Yellow
    Write-Host " 2. Update Windows"         -ForegroundColor Yellow
    Write-Host " 3. Repair + Update Windows"-ForegroundColor Yellow
    Write-Host " 4. Update Applications"    -ForegroundColor Yellow
    Write-Host " 5. Reset Print Spooler"    -ForegroundColor Yellow
    Write-Host " 6. Repair System Clock"    -ForegroundColor Yellow
    Write-Host " 7. Exit"                   -ForegroundColor Yellow
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
    $ClockStatus = ""

    switch ($Selection) {

        "1" {
            $RepairStatus = Invoke-SystemRepair
        }

        "2" {
            $UpdateCount = [int](Invoke-WindowsUpdates | Select-Object -Last 1)
        }

        "3" {
            $RepairStatus = Invoke-SystemRepair
            $UpdateCount = [int](Invoke-WindowsUpdates | Select-Object -Last 1)
        }

        "4" {
            Invoke-ApplicationUpdates
            $AppsStatus = "Completed"
        }

        "5" {
            $SpoolerStatus = if (Reset-PrintSpooler) { "Completed" } else { "Failed" }
        }

        "6" {
            $ClockStatus = if (Repair-SystemClock) { "Completed" } else { "Failed" }
        }
        
        "7" {
            Write-Host ""
            Write-Host "Exiting..." -ForegroundColor Yellow
            Read-Host "Press Enter to close"
            exit
        }
    }

    if ($Selection -ne "7") {

        $EndTime = Get-Date

        Write-Host ""
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host " MAINTENANCE SUMMARY" -ForegroundColor Cyan
        Write-Host "======================================" -ForegroundColor Cyan

        Write-Host "Start Time  : $StartTime"
        Write-Host "End Time    : $EndTime"

        if ($RepairStatus) {
            Write-Host "Repair      : $RepairStatus"
        }

        if ($SpoolerStatus) {
            Write-Host "Spooler     : $SpoolerStatus"
        }
        if ($ClockStatus) {
            Write-Host "Clock       : $ClockStatus"
        }

        if ($AppsStatus) {
            Write-Host "Applications: $AppsStatus"
        }

        Write-Host "Updates     : $UpdateCount"

        Write-Host ""
        Read-Host "Press Enter to return to the menu"
    }

} while ($Selection -ne "7")

Read-Host "Press Enter to close"


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

