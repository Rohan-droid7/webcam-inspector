<#
.SYNOPSIS
    Educational script demonstrating how to modify Windows Registry values to spoof an external webcam's identity.

.DESCRIPTION
    This script is a companion to the "Camera Spoofing Guide". It demonstrates how a script would programmatically 
    alter the registry keys of the external camera (HD camera) to make it mimic the built-in HP camera.
    
    SECURITY WARNING:
    The keys targeted by this script (under HKLM\SYSTEM\CurrentControlSet\Enum) are protected by the Windows Kernel.
    By default, even the Administrator account only has Read access. Modifying them requires the script to run as 
    NT AUTHORITY\SYSTEM, or requires temporarily taking ownership of the registry keys and altering their ACLs 
    (Access Control Lists). 

    WHAT THIS SCRIPT DOES (Dry-Run by default):
    1. Identifies the target external camera by its known VID/PID (0x349C / 0x2317).
    2. Identifies the target registry paths for the device node.
    3. Prints out the exact registry modifications it WOULD make to spoof the identity:
       - FriendlyName -> "HP Wide Vision HD Camera"
       - Device Parameters -> Adds OEM-specific DMFT keys
       - RemovalPolicy -> 1 (ExpectNoRemoval)
       - ContainerID -> {00000000-0000-0000-FFFF-FFFFFFFFFFFF}
    
    This script is completely safe to run as-is. It operates in "WhatIf" mode and will NOT modify your registry.

.EXAMPLE
    .\Spoof-WebcamRegistry.ps1
#>

[CmdletBinding()]
param(
    # Set to $true to actually perform the modifications. (Requires running as SYSTEM)
    [switch]$ApplyChanges
)

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  WEBCAM IDENTITY SPOOFER (Registry Phase)" -ForegroundColor Cyan
Write-Host "  Educational Demonstration" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

if ($ApplyChanges) {
    Write-Host "[WARNING] -ApplyChanges flag provided. The script will attempt to modify the registry." -ForegroundColor Red
    Write-Host "This requires running as NT AUTHORITY\SYSTEM. If you are just an Administrator, access will be denied." -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "[INFO] Running in DRY-RUN mode. No changes will be made to your system." -ForegroundColor Green
    Write-Host ""
}

# The target external camera based on previous hardware scan
$targetVid = "349C"
$targetPid = "2317"
$targetInstanceIdPattern = "USB\VID_${targetVid}&PID_${targetPid}&MI_00\*"

Write-Host "1. Searching for target device (VID: $targetVid, PID: $targetPid)..."
$targetDevice = Get-PnpDevice -Status OK -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -like $targetInstanceIdPattern
}

if (-not $targetDevice) {
    Write-Host "  [!] Target external camera not found. Is it plugged in?" -ForegroundColor Yellow
    exit
}

Write-Host "  [+] Found target: $($targetDevice.FriendlyName)" -ForegroundColor Green
Write-Host "  [+] Instance ID: $($targetDevice.InstanceId)" -ForegroundColor DarkGray
Write-Host ""

# Construct the base registry path
$baseRegPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($targetDevice.InstanceId)"
$devParamsPath = "$baseRegPath\Device Parameters"

# Define the spoofing payload
$spoofFriendlyName = "HP Wide Vision HD Camera"
$spoofRemovalPolicy = 1 # ExpectNoRemoval

# Fake OEM Device Parameters
$spoofParams = @{
    "UVC-FSSensorGroupID" = "{78DCB7D0-33EA-458B-B98A-56E9A3A40B50}"
    "UVC-FSSensorGroupName" = "Rts-DMFT-Group"
    "UVC-EnablePlatformDmft" = 1
    "EnableDshowRedirection" = 1
}

# The Local Machine Container ID (indicates physically built-in)
$localMachineContainerID = "{00000000-0000-0000-FFFF-FFFFFFFFFFFF}"
# Container ID property key path (requires deep SYSTEM access)
$containerIdPropKey = "{8c7ed206-3f8a-4827-b3ab-ae9e1faefc6c}\0002"
$propsPath = "$baseRegPath\Properties\$containerIdPropKey"

Write-Host "2. Proposed Registry Modifications:" -ForegroundColor White

Write-Host "`n  [A] FriendlyName Modification" -ForegroundColor Magenta
Write-Host "      Path: $baseRegPath"
Write-Host "      Property: FriendlyName"
Write-Host "      Change: '$($targetDevice.FriendlyName)' -> '$spoofFriendlyName'"
Write-Host "      Impact: Apps and browsers (enumerateDevices) will see it as the HP camera." -ForegroundColor DarkGray

Write-Host "`n  [B] OEM Device Parameters Injection" -ForegroundColor Magenta
Write-Host "      Path: $devParamsPath"
Write-Host "      Changes:"
foreach ($key in $spoofParams.Keys) {
    Write-Host "        + $key = $($spoofParams[$key])"
}
Write-Host "      Impact: Makes the camera driver stack look like it has OEM-specific processing pipelines." -ForegroundColor DarkGray

Write-Host "`n  [C] Removal Policy Spoofing" -ForegroundColor Magenta
Write-Host "      Path: $baseRegPath"
Write-Host "      Property: RemovalPolicy"
Write-Host "      Change: 3 (SurpriseRemoval) -> 1 (ExpectNoRemoval)"
Write-Host "      Impact: Tells the kernel the device is hardwired and shouldn't be safely removable." -ForegroundColor DarkGray

Write-Host "`n  [D] Container ID Spoofing (Volatile)" -ForegroundColor Magenta
Write-Host "      Path: $propsPath"
Write-Host "      Property: (Default)"
Write-Host "      Change: Current unique GUID -> $localMachineContainerID"
Write-Host "      Impact: Flips DEVPKEY_Device_InLocalMachineContainer to True. This is the ultimate 'built-in' check." -ForegroundColor DarkGray
Write-Host "      Note: This change will be overwritten by the PnP manager upon next replug/reboot." -ForegroundColor Yellow

Write-Host ""
if (-not $ApplyChanges) {
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host " DRY RUN COMPLETE. NO CHANGES MADE." -ForegroundColor Green
    Write-Host " To execute these changes, you would need a tool like PsExec to run"
    Write-Host " PowerShell as SYSTEM, e.g.: psexec -i -s powershell.exe"
    Write-Host "========================================================" -ForegroundColor Cyan
    exit
}

# --- DANGER ZONE: Actual execution logic below ---

Write-Host "3. Attempting to apply changes..." -ForegroundColor Yellow

try {
    # Backup existing values to a file first
    $backupFile = "$env:TEMP\WebcamSpoofBackup.json"
    $backupData = @{
        FriendlyName = (Get-ItemProperty $baseRegPath -Name FriendlyName -ErrorAction SilentlyContinue).FriendlyName
        RemovalPolicy = (Get-ItemProperty $baseRegPath -Name RemovalPolicy -ErrorAction SilentlyContinue).RemovalPolicy
    }
    $backupData | ConvertTo-Json | Set-Content $backupFile
    Write-Host "  [+] Backup saved to $backupFile" -ForegroundColor Green

    # Apply Friendly Name
    Set-ItemProperty -Path $baseRegPath -Name "FriendlyName" -Value $spoofFriendlyName -ErrorAction Stop
    Write-Host "  [+] FriendlyName spoofed successfully." -ForegroundColor Green

    # Apply Removal Policy
    Set-ItemProperty -Path $baseRegPath -Name "RemovalPolicy" -Value $spoofRemovalPolicy -ErrorAction Stop
    Write-Host "  [+] RemovalPolicy spoofed successfully." -ForegroundColor Green

    # Apply Device Parameters
    if (-not (Test-Path $devParamsPath)) {
        New-Item -Path $devParamsPath -Force | Out-Null
    }
    foreach ($key in $spoofParams.Keys) {
        Set-ItemProperty -Path $devParamsPath -Name $key -Value $spoofParams[$key] -ErrorAction Stop
    }
    Write-Host "  [+] Device Parameters injected successfully." -ForegroundColor Green

    # Apply Container ID (Highly likely to fail without SYSTEM)
    # The property store stores the GUID as binary or string depending on the exact schema, 
    # but typically it's REG_BINARY or a specific structured type. For simplicity, we just try to write a string.
    # If it fails, we catch it.
    if (Test-Path $propsPath) {
        Set-ItemProperty -Path $propsPath -Name "(Default)" -Value $localMachineContainerID -ErrorAction Stop
        Write-Host "  [+] Container ID spoofed successfully." -ForegroundColor Green
    } else {
        Write-Host "  [!] Container ID property path not found, skipping." -ForegroundColor Yellow
    }

    Write-Host "`n  [SUCCESS] Spoofing applied! You may need to disable/enable the camera in Device Manager for changes to reflect." -ForegroundColor Green

} catch {
    Write-Host "`n  [FAILED] Could not apply changes." -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Reason: You likely do not have SYSTEM privileges, or the registry keys are locked by the kernel." -ForegroundColor Yellow
}
