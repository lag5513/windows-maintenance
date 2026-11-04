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

    & DISM.exe `
        /Online `
        /Cleanup-Image `
        /CheckHealth 2>&1 |
        Tee-Object -Variable CheckHealthOutput |
        Out-Host

    $CheckHealthText = $CheckHealthOutput | Out-String
    $CorruptionDetected = $CheckHealthText -match "repairable"
    
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

        $MinimumNuGetVersion = [version]"2.8.5.201"
        $NuGetProvider = Get-PackageProvider `
            -Name NuGet `
            -ListAvailable `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.Version -ge $MinimumNuGetVersion } |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $NuGetProvider) {
        
            Write-Host "Installing NuGet provider..." -ForegroundColor Yellow
        
            Install-PackageProvider `
                -Name NuGet `
                -MinimumVersion $MinimumNuGetVersion `
                -Force `
                -ForceBootstrap `
                -Scope CurrentUser `
                -Confirm:$false `
                -ErrorAction Stop
        }

        Import-PackageProvider `
            -Name NuGet `
            -MinimumVersion $MinimumNuGetVersion `
            -Force `
            -ErrorAction Stop |
            Out-Null
        
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

        Write-Host "Scanning Windows Update for Updates..." -ForegroundColor Yellow

        $Updates = @(Get-WindowsUpdate -ErrorAction Stop)

        if ($Updates.Count -gt 0) {
            $AvailableUpdates = @(
                foreach ($Update in $Updates) {
                    $KbValues = @($Update.KB)
                    $SizeValues = @($Update.Size)
                    $TitleValues = @($Update.Title)
                    $RowCount = [Math]::Max(
                        $KbValues.Count,
                        [Math]::Max($SizeValues.Count, $TitleValues.Count)
                    )

                    for ($Index = 0; $Index -lt $RowCount; $Index++) {
                        [pscustomobject]@{
                            KB = if ($Index -lt $KbValues.Count) { $KbValues[$Index] } else { "" }
                            Size = if ($Index -lt $SizeValues.Count) { $SizeValues[$Index] } else { "" }
                            Title = if ($Index -lt $TitleValues.Count) { $TitleValues[$Index] } else { "" }
                        }
                    }
                }
            )
            $Count = $AvailableUpdates.Count

            Write-Host ""
            Write-Host "Available updates:" -ForegroundColor Cyan

            foreach ($Update in $AvailableUpdates) {
                Write-Host ("  {0}  {1}  {2}" -f $Update.KB, $Update.Size, $Update.Title)
            }

            Write-Host "$($Count) Update(s) Found" -ForegroundColor Green
            Read-Host "Press Enter to install these updates"
            Write-Host "Installing updates..." -ForegroundColor Yellow

            Install-WindowsUpdate `
                -AcceptAll `
                -IgnoreReboot `
                -Confirm:$false `
                -Verbose |
                Out-Host

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

function Test-DiskHealth {

    Write-Host ""
    Write-Host "===== DISK HEALTH CHECK =====" -ForegroundColor Cyan

    $IssuesFound = $false
    $CheckFailed = $false

    try {
        $PhysicalDisks = @(Get-PhysicalDisk -ErrorAction Stop)

        if ($PhysicalDisks.Count -gt 0) {
            Write-Host "Physical disk status:" -ForegroundColor Yellow

            foreach ($Disk in $PhysicalDisks) {
                $OperationalStatus = @($Disk.OperationalStatus) -join ", "
                Write-Host ("  {0}: Health={1}; Operational={2}" -f $Disk.FriendlyName, $Disk.HealthStatus, $OperationalStatus)

                if ($Disk.HealthStatus -in @("Warning", "Unhealthy") -or
                    $OperationalStatus -match "Degraded|Lost Communication|Failed") {
                    $IssuesFound = $true
                }
            }
        }
        else {
            Write-Host "No physical disks were reported by Windows Storage Management." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Unable to query physical disk status: $($_.Exception.Message)" -ForegroundColor Red
        $CheckFailed = $true
    }

    try {
        $Volumes = @(
            Get-Volume -ErrorAction Stop |
                Where-Object { $_.DriveLetter -and $_.FileSystem -eq "NTFS" }
        )

        if ($Volumes.Count -eq 0) {
            Write-Host "No drive-letter NTFS volumes found for an online file-system scan." -ForegroundColor Yellow
            $CheckFailed = $true
        }

        foreach ($Volume in $Volumes) {
            $Drive = "$($Volume.DriveLetter):"
            Write-Host ""
            Write-Host "Scanning $Drive with CHKDSK..." -ForegroundColor Yellow

            try {
                & chkdsk.exe $Drive /scan 2>&1 | Out-Host

                if ($LASTEXITCODE -ne 0) {
                    Write-Host "CHKDSK reported a problem on $Drive (exit code $LASTEXITCODE)." -ForegroundColor Red
                    $IssuesFound = $true
                }
            }
            catch {
                Write-Host "Unable to scan $Drive`: $($_.Exception.Message)" -ForegroundColor Red
                $CheckFailed = $true
            }
        }
    }
    catch {
        Write-Host "Unable to enumerate volumes: $($_.Exception.Message)" -ForegroundColor Red
        $CheckFailed = $true
    }

    if ($IssuesFound) {
        Write-Host "Disk health check found issues." -ForegroundColor Red
        return "Issues Found"
    }

    if ($CheckFailed) {
        return "Check Incomplete"
    }

    Write-Host "Disk health check completed." -ForegroundColor Green
    return "Healthy"
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
    Write-Host " 7. Check Disk Health"      -ForegroundColor Yellow
    Write-Host " 8. Exit"                   -ForegroundColor Yellow
    Write-Host ""

    $ValidOptions = @("1","2","3","4","5","6","7","8")

    $Selections = (
        (Read-Host "Select option(s) (example: 1,2,5,7)") -split ','
    ).Trim() | Select-Object -Unique
    
    $InvalidOptions = $Selections | Where-Object { $_ -notin $ValidOptions }
    
    if ($InvalidOptions) {
    
        Write-Host ""
        Write-Host "Invalid option(s): $($InvalidOptions -join ', ')" -ForegroundColor Red
        Read-Host "Press Enter to continue"
    
        return
    }

    $StartTime = Get-Date
    $RepairStatus = ""
    [int]$UpdateCount = 0
    $SpoolerStatus = ""
    $AppsStatus = ""
    $ClockStatus = ""
    $DiskStatus = ""

    foreach ($Selection in $Selections) {

    switch ($Selection) {

        "1" {
            $RepairStatus = Invoke-SystemRepair
        }

        "2" {
            $UpdateCount = Invoke-WindowsUpdates | Select-Object -Last 1
        }

        "3" {
            $RepairStatus = Invoke-SystemRepair
            $UpdateCount = Invoke-WindowsUpdates | Select-Object -Last 1
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
            $DiskStatus = Test-DiskHealth
        }

        "8" {
            exit
        }
    }
}

    if ($Selection -ne "8") {

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

        if ($DiskStatus) {
            Write-Host "Disk Health : $DiskStatus"
        }

        if ($AppsStatus) {
            Write-Host "Applications: $AppsStatus"
        }

        Write-Host "Updates     : $UpdateCount"

        Write-Host ""
        Read-Host "Press Enter to return to the menu"
    }

} while ($Selection -ne "8")

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
