function Invoke-WindowsUpdates {

    Write-Host ""
    Write-Host "===== WINDOWS UPDATE =====" -ForegroundColor Cyan

    try {

        Set-PSRepository `
            -Name PSGallery `
            -InstallationPolicy Trusted `
            -ErrorAction SilentlyContinue

        if (-not (Get-PackageProvider NuGet -ErrorAction SilentlyContinue)) {

            Install-PackageProvider `
                -Name NuGet `
                -Force `
                -Confirm:$false
        }

        if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {

            Install-Module `
                PSWindowsUpdate `
                -Force `
                -AllowClobber `
                -Confirm:$false
        }

        Import-Module PSWindowsUpdate -Force

        Add-WUServiceManager `
            -MicrosoftUpdate `
            -Confirm:$false `
            -ErrorAction SilentlyContinue | Out-Null

        $Updates = Get-WindowsUpdate -MicrosoftUpdate

        if ($Updates) {

            Write-Host ""
            Write-Host "$($Updates.Count) updates found." -ForegroundColor Green

            Install-WindowsUpdate `
                -MicrosoftUpdate `
                -AcceptAll `
                -IgnoreReboot `
                -Confirm:$false
        }
        else {

            Write-Host "No updates available." -ForegroundColor Green
        }
    }
    catch {

        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}
