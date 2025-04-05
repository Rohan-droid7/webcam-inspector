<#
.SYNOPSIS
    Deep kernel-level hardware inspection of connected webcam/camera devices.

.DESCRIPTION
    Extracts information that browser APIs CANNOT access:
    - PnP device node properties (instance ID, hardware IDs, compatible IDs)
    - USB VID/PID/REV and interface numbers
    - Driver stack: function driver, upper/lower filter drivers
    - Driver version, provider, INF file, driver date
    - Device location, topology, PDO name
    - Power capabilities and current D-state
    - Security descriptors and capability flags
    - Registry configuration (Device Parameters)
    - USB parent device (composite device info)
    - Child devices
    - Complete raw property dump

.NOTES
    Run as Administrator for full access to all device properties.
    Usage: Right-click PowerShell -> Run as Administrator -> .\Get-WebcamHardwareInfo.ps1

.EXAMPLE
    .\Get-WebcamHardwareInfo.ps1
#>

[CmdletBinding()]
param()

# -- Banner --
Write-Host ""
Write-Host "  ========================================================" -ForegroundColor Cyan
Write-Host "    WEBCAM HARDWARE INSPECTOR                             " -ForegroundColor Cyan
Write-Host "    Kernel, Driver and USB Level Analysis                  " -ForegroundColor Cyan
Write-Host "    Windows 11                                            " -ForegroundColor Cyan
Write-Host "  ========================================================" -ForegroundColor Cyan
Write-Host ""

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  [!] Not running as Administrator. Some properties may be inaccessible." -ForegroundColor Yellow
    Write-Host "      Recommend: Right-click PowerShell -> Run as Administrator" -ForegroundColor DarkGray
    Write-Host ""
}

# -- Find Camera Devices --
$cameraDevices = @()

# Class: Camera (Windows 10 1709+)
$cam = Get-PnpDevice -Class 'Camera' -Status OK -ErrorAction SilentlyContinue
if ($cam) { $cameraDevices += $cam }

# Class: Image (legacy webcams, scanners)
$img = Get-PnpDevice -Class 'Image' -Status OK -ErrorAction SilentlyContinue
if ($img) { $cameraDevices += $img }

# Also find USB Video class devices that might be in Media class
$media = Get-PnpDevice -Status OK -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -match 'USB' -and $_.Class -eq 'Media'
}
if ($media) {
    foreach ($d in $media) {
        $compatIds = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_CompatibleIds' -EA SilentlyContinue).Data
        if ($compatIds -and ($compatIds -join ',') -match 'Class_0e') {
            if ($cameraDevices.InstanceId -notcontains $d.InstanceId) {
                $cameraDevices += $d
            }
        }
    }
}

# Deduplicate
$cameraDevices = $cameraDevices | Sort-Object InstanceId -Unique

if ($cameraDevices.Count -eq 0) {
    Write-Host "  [!] No camera devices found." -ForegroundColor Red
    Write-Host "      Ensure a webcam is connected and recognized by Windows." -ForegroundColor DarkGray
    Write-Host "      Check Device Manager -> Cameras / Imaging Devices" -ForegroundColor DarkGray
    Write-Host ""
    exit
}

Write-Host "  Found $($cameraDevices.Count) camera device(s)" -ForegroundColor Green
Write-Host ""

# -- Helper function --
function Get-DevProp {
    param([string]$InstanceId, [string]$KeyName)
    $result = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction SilentlyContinue
    if ($result -and $null -ne $result.Data) { return $result.Data }
    return $null
}

# Regex patterns stored as variables to avoid parsing issues
$vidPattern = 'VID_([0-9a-fA-F]{4})'
$pidPattern = 'PID_([0-9a-fA-F]{4})'
$revPattern = 'REV_([0-9a-fA-F]{4})'
$miPattern  = 'MI_(\d{2})'
$usbVidPidPattern = "USB\\\\VID_([0-9a-fA-F]{4})" + "&" + "PID_([0-9a-fA-F]{4})"

# -- Analyze Each Device --
$deviceIndex = 0
foreach ($device in $cameraDevices) {
    $deviceIndex++

    Write-Host ("=" * 64) -ForegroundColor Yellow
    Write-Host "  DEVICE ${deviceIndex}: $($device.FriendlyName)" -ForegroundColor Yellow
    Write-Host ("=" * 64) -ForegroundColor Yellow

    # -- 1. PnP Device Information --
    Write-Host ""
    Write-Host "  [PnP Device Information]" -ForegroundColor Green
    Write-Host "    Friendly Name     : $($device.FriendlyName)"
    Write-Host "    Instance ID       : $($device.InstanceId)"
    Write-Host "    Device ID         : $($device.DeviceID)"
    Write-Host "    Class             : $($device.Class)"
    Write-Host "    Class GUID        : $($device.ClassGuid)"
    Write-Host "    Status            : $($device.Status)"
    Write-Host "    Problem Code      : $($device.Problem)"
    Write-Host "    Present           : $($device.Present)"
    Write-Host "    Manufacturer      : $($device.Manufacturer)"

    # -- 2. Hardware IDs --
    $hwIds = Get-DevProp $device.InstanceId 'DEVPKEY_Device_HardwareIds'
    if ($hwIds) {
        Write-Host ""
        Write-Host "  [Hardware IDs]" -ForegroundColor Green
        foreach ($id in $hwIds) {
            Write-Host "    $id" -ForegroundColor White
            if ($id -match $vidPattern) {
                $vid = $Matches[1]
                Write-Host "      -> Vendor ID (VID)    : 0x${vid} (dec: $([Convert]::ToInt32($vid, 16)))" -ForegroundColor DarkCyan
            }
            if ($id -match $pidPattern) {
                $pidVal = $Matches[1]
                Write-Host "      -> Product ID (PID)   : 0x${pidVal} (dec: $([Convert]::ToInt32($pidVal, 16)))" -ForegroundColor DarkCyan
            }
            if ($id -match $revPattern) {
                Write-Host "      -> Revision           : 0x$($Matches[1])" -ForegroundColor DarkCyan
            }
            if ($id -match $miPattern) {
                Write-Host "      -> USB Interface #    : $($Matches[1])" -ForegroundColor DarkCyan
            }
        }
    }

    # -- 3. Compatible IDs --
    $compatIds = Get-DevProp $device.InstanceId 'DEVPKEY_Device_CompatibleIds'
    if ($compatIds) {
        Write-Host ""
        Write-Host "  [Compatible IDs]" -ForegroundColor Green
        foreach ($id in $compatIds) {
            Write-Host "    $id"
            if ($id -match 'Class_0e') {
                Write-Host "      -> USB Video Class (UVC) compliant" -ForegroundColor DarkCyan
            }
            if ($id -match 'SubClass_01') {
                Write-Host "      -> Video Control interface" -ForegroundColor DarkCyan
            }
            if ($id -match 'SubClass_02') {
                Write-Host "      -> Video Streaming interface" -ForegroundColor DarkCyan
            }
            if ($id -match 'SubClass_03') {
                Write-Host "      -> Video Interface Collection" -ForegroundColor DarkCyan
            }
        }
    }

    # -- 4. Driver Information --
    Write-Host ""
    Write-Host "  [Driver Information]" -ForegroundColor Green

    $driverProps = @(
        @('DEVPKEY_Device_DriverDesc',          'Driver Description'),
        @('DEVPKEY_Device_DriverVersion',       'Driver Version'),
        @('DEVPKEY_Device_DriverDate',          'Driver Date'),
        @('DEVPKEY_Device_DriverProvider',      'Driver Provider'),
        @('DEVPKEY_Device_DriverInfPath',       'INF File'),
        @('DEVPKEY_Device_DriverInfSection',    'INF Section'),
        @('DEVPKEY_Device_DriverInfSectionExt', 'INF Section Ext'),
        @('DEVPKEY_Device_Service',             'Service Name')
    )

    foreach ($prop in $driverProps) {
        $val = Get-DevProp $device.InstanceId $prop[0]
        if ($val) {
            $displayVal = if ($val -is [DateTime]) { $val.ToString('yyyy-MM-dd HH:mm:ss') } else { $val }
            Write-Host "    $($prop[1].PadRight(22)): $displayVal"
        }
    }

    $svc = Get-DevProp $device.InstanceId 'DEVPKEY_Device_Service'
    if ($svc -eq 'usbvideo') {
        Write-Host ""
        Write-Host "    * Uses standard USB Video Class driver (usbvideo.sys)" -ForegroundColor DarkCyan
        Write-Host "      This is Microsoft's in-box UVC driver." -ForegroundColor DarkGray
    }

    # -- 5. Device Stack (Filters) --
    Write-Host ""
    Write-Host "  [Device Stack / Filter Drivers]" -ForegroundColor Green

    $upperFilters = Get-DevProp $device.InstanceId 'DEVPKEY_Device_UpperFilters'
    $lowerFilters = Get-DevProp $device.InstanceId 'DEVPKEY_Device_LowerFilters'
    $service      = Get-DevProp $device.InstanceId 'DEVPKEY_Device_Service'

    if ($upperFilters) {
        Write-Host "    Upper Filters     : $($upperFilters -join ', ')" -ForegroundColor Magenta
        foreach ($f in $upperFilters) {
            Write-Host "      ^ $f.sys" -ForegroundColor DarkMagenta
        }
    } else {
        Write-Host "    Upper Filters     : (none)"
    }

    if ($service) {
        Write-Host "    Function Driver   : ${service}.sys  <-- handles I/O" -ForegroundColor White
    }

    if ($lowerFilters) {
        Write-Host "    Lower Filters     : $($lowerFilters -join ', ')" -ForegroundColor Magenta
        foreach ($f in $lowerFilters) {
            Write-Host "      v $f.sys" -ForegroundColor DarkMagenta
        }
    } else {
        Write-Host "    Lower Filters     : (none)"
    }

    $enum = Get-DevProp $device.InstanceId 'DEVPKEY_Device_EnumeratorName'
    if ($enum) {
        Write-Host "    Bus Enumerator    : $enum" -ForegroundColor DarkGray
    }

    # -- 6. Device Location and Topology --
    Write-Host ""
    Write-Host "  [Device Location and Topology]" -ForegroundColor Green

    $locProps = @(
        @('DEVPKEY_Device_LocationInfo',             'Location Info'),
        @('DEVPKEY_Device_PDOName',                  'PDO Name'),
        @('DEVPKEY_Device_BusReportedDeviceDesc',    'Bus Reported Name'),
        @('DEVPKEY_Device_ContainerId',              'Container ID'),
        @('DEVPKEY_Device_Parent',                   'Parent Device'),
        @('DEVPKEY_Device_EnumeratorName',           'Enumerator')
    )

    foreach ($prop in $locProps) {
        $val = Get-DevProp $device.InstanceId $prop[0]
        if ($val) {
            Write-Host "    $($prop[1].PadRight(22)): $val"
        }
    }

    $locPaths = Get-DevProp $device.InstanceId 'DEVPKEY_Device_LocationPaths'
    if ($locPaths) {
        Write-Host "    Location Paths    :"
        foreach ($lp in $locPaths) {
            Write-Host "      $lp" -ForegroundColor DarkGray
        }
    }

    # -- 7. Power Capabilities --
    Write-Host ""
    Write-Host "  [Power Capabilities]" -ForegroundColor Green

    $powerData = Get-DevProp $device.InstanceId 'DEVPKEY_Device_PowerData'
    if ($powerData) {
        Write-Host "    Power Data         : [Binary payload, $($powerData.Length) bytes]"
    }

    $powerRelations = Get-DevProp $device.InstanceId 'DEVPKEY_Device_PowerRelations'
    if ($powerRelations) {
        Write-Host "    Power Relations    : $($powerRelations -join ', ')"
    }

    # -- 8. Security and Capabilities --
    Write-Host ""
    Write-Host "  [Security and Device Capabilities]" -ForegroundColor Green

    $capsMask = Get-DevProp $device.InstanceId 'DEVPKEY_Device_Capabilities'
    if ($null -ne $capsMask) {
        $capFlags = @()
        if ($capsMask -band 0x01) { $capFlags += 'LockSupported' }
        if ($capsMask -band 0x02) { $capFlags += 'EjectSupported' }
        if ($capsMask -band 0x04) { $capFlags += 'Removable' }
        if ($capsMask -band 0x08) { $capFlags += 'DockDevice' }
        if ($capsMask -band 0x10) { $capFlags += 'UniqueID' }
        if ($capsMask -band 0x20) { $capFlags += 'SilentInstall' }
        if ($capsMask -band 0x40) { $capFlags += 'RawDeviceOK' }
        if ($capsMask -band 0x80) { $capFlags += 'SurpriseRemovalOK' }
        Write-Host ("    Capabilities Mask  : 0x{0:X2}" -f $capsMask)
        foreach ($cf in $capFlags) {
            Write-Host "      [+] $cf" -ForegroundColor DarkCyan
        }
    }

    $installState = Get-DevProp $device.InstanceId 'DEVPKEY_Device_InstallState'
    if ($null -ne $installState) {
        $stateMap = @{ 0 = 'Installed'; 1 = 'NeedsReinstall'; 2 = 'FailedInstall'; 3 = 'FinishInstall' }
        $stateName = $stateMap[[int]$installState]
        Write-Host "    Install State      : $installState ($stateName)"
    }

    $configFlags = Get-DevProp $device.InstanceId 'DEVPKEY_Device_ConfigFlags'
    if ($null -ne $configFlags) {
        Write-Host ("    Config Flags       : 0x{0:X8}" -f $configFlags)
    }

    $sds = Get-DevProp $device.InstanceId 'DEVPKEY_Device_SecuritySDS'
    if ($sds) {
        $sdsShort = if ($sds.Length -gt 60) { $sds.Substring(0, 60) + '...' } else { $sds }
        Write-Host "    Security (SDDL)    : $sdsShort" -ForegroundColor DarkGray
    }

    # -- 9. USB-Specific Details --
    if ($device.InstanceId -match '^USB') {
        Write-Host ""
        Write-Host "  [USB Device Details]" -ForegroundColor Green

        if ($device.InstanceId -match $usbVidPidPattern) {
            $vid = $Matches[1]
            $pidVal = $Matches[2]
            Write-Host "    USB Vendor ID      : 0x${vid} (decimal: $([Convert]::ToInt32($vid, 16)))"
            Write-Host "    USB Product ID     : 0x${pidVal} (decimal: $([Convert]::ToInt32($pidVal, 16)))"
        }

        # Serial number / instance portion
        $parts = $device.InstanceId -split '\\'
        if ($parts.Count -ge 3) {
            Write-Host "    Serial / Instance  : $($parts[2])"
        }

        # Parent device (USB composite or hub)
        $parentId = Get-DevProp $device.InstanceId 'DEVPKEY_Device_Parent'
        if ($parentId) {
            Write-Host "    Parent Device      : $parentId"

            $parentDesc = Get-DevProp $parentId 'DEVPKEY_Device_BusReportedDeviceDesc'
            if ($parentDesc) {
                Write-Host "    USB Product String : $parentDesc" -ForegroundColor DarkCyan
            }

            $parentMfg = Get-DevProp $parentId 'DEVPKEY_Device_Manufacturer'
            if ($parentMfg) {
                Write-Host "    USB Manufacturer   : $parentMfg" -ForegroundColor DarkCyan
            }

            # Check if parent is a composite device
            $parentSvc = Get-DevProp $parentId 'DEVPKEY_Device_Service'
            if ($parentSvc -eq 'usbccgp') {
                Write-Host "    * Parent is a USB Composite Device (usbccgp.sys)" -ForegroundColor DarkCyan
                Write-Host "      Camera is one interface of a multi-function USB device" -ForegroundColor DarkGray
            }

            # Grandparent (likely USB hub or root hub)
            $grandparent = Get-DevProp $parentId 'DEVPKEY_Device_Parent'
            if ($grandparent) {
                Write-Host "    USB Hub / Root     : $grandparent" -ForegroundColor DarkGray
            }
        }

        # Bus relations (sibling interfaces on composite device)
        $busRelations = Get-DevProp $device.InstanceId 'DEVPKEY_Device_BusRelations'
        if ($busRelations) {
            Write-Host "    Bus Relations      :"
            foreach ($rel in $busRelations) {
                $relDev = Get-PnpDevice -InstanceId $rel -EA SilentlyContinue
                $relName = if ($relDev) { " ($($relDev.FriendlyName))" } else { '' }
                Write-Host "      $rel$relName" -ForegroundColor DarkGray
            }
        }
    }

    # -- 10. Registry Configuration --
    Write-Host ""
    Write-Host "  [Registry Configuration]" -ForegroundColor Green

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($device.InstanceId)"
    if (Test-Path $regPath) {
        Write-Host "    Registry Path      :"
        Write-Host "      $regPath" -ForegroundColor DarkGray

        # Device Parameters subkey
        $paramPath = "$regPath\Device Parameters"
        if (Test-Path $paramPath) {
            Write-Host ""
            Write-Host "    Device Parameters  :" -ForegroundColor DarkCyan
            $params = Get-ItemProperty -Path $paramPath -EA SilentlyContinue
            if ($params) {
                $skipProps = @('PSPath','PSDrive','PSProvider','PSParentPath','PSChildName')
                foreach ($p in $params.PSObject.Properties) {
                    if ($p.Name -notin $skipProps) {
                        $valStr = if ($p.Value -is [byte[]]) {
                            "[Binary $($p.Value.Length) bytes]"
                        } elseif ($p.Value -is [Array]) {
                            $p.Value -join ', '
                        } else {
                            [string]$p.Value
                        }
                        Write-Host "      $($p.Name.PadRight(26)): $valStr"
                    }
                }
            }
        }

        # Check for class-specific subkeys
        $subKeys = Get-ChildItem -Path $regPath -EA SilentlyContinue
        if ($subKeys) {
            $interestingKeys = $subKeys | Where-Object { $_.PSChildName -notin @('Device Parameters', 'Properties') }
            if ($interestingKeys) {
                Write-Host ""
                Write-Host "    Other Registry Subkeys:" -ForegroundColor DarkCyan
                foreach ($sk in $interestingKeys) {
                    Write-Host "      $($sk.PSChildName)" -ForegroundColor DarkGray
                }
            }
        }
    } else {
        Write-Host "    Registry path not found (may need elevated access)"
    }

    # -- 11. Child Devices --
    $children = Get-DevProp $device.InstanceId 'DEVPKEY_Device_Children'
    if ($children) {
        Write-Host ""
        Write-Host "  [Child Devices]" -ForegroundColor Green
        foreach ($child in $children) {
            $childDev = Get-PnpDevice -InstanceId $child -EA SilentlyContinue
            if ($childDev) {
                Write-Host "    $($childDev.FriendlyName) [$($childDev.Class)]"
            }
            Write-Host "      $child" -ForegroundColor DarkGray
        }
    }

    # -- 12. All Properties (Raw Dump) --
    Write-Host ""
    Write-Host "  [Complete Property Dump]" -ForegroundColor Green

    $allProps = Get-PnpDeviceProperty -InstanceId $device.InstanceId -EA SilentlyContinue
    $shown = @{}
    $propCount = 0

    foreach ($p in $allProps) {
        if ($null -ne $p.Data -and -not $shown.ContainsKey($p.KeyName)) {
            $shown[$p.KeyName] = $true
            $propCount++

            $valStr = if ($p.Data -is [byte[]]) {
                "[Binary $($p.Data.Length)B]"
            } elseif ($p.Data -is [Array]) {
                $joined = ($p.Data | Select-Object -First 3) -join ', '
                if ($p.Data.Count -gt 3) { "$joined (+$($p.Data.Count - 3) more)" } else { $joined }
            } elseif ($p.Data -is [DateTime]) {
                $p.Data.ToString('yyyy-MM-dd HH:mm:ss')
            } else {
                $s = [string]$p.Data
                if ($s.Length -gt 50) { $s.Substring(0, 50) + '...' } else { $s }
            }

            $keyShort = $p.KeyName -replace 'DEVPKEY_', ''
            Write-Host "    $($keyShort.PadRight(42)) $valStr" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "    Total properties: $propCount" -ForegroundColor DarkCyan
    Write-Host ""
}

# -- Summary --
Write-Host ("=" * 64) -ForegroundColor Cyan
Write-Host "  ANALYSIS COMPLETE -- $($cameraDevices.Count) device(s) inspected" -ForegroundColor Cyan
Write-Host ("=" * 64) -ForegroundColor Cyan
Write-Host ""
Write-Host "  For even deeper analysis:" -ForegroundColor DarkGray
Write-Host "    - USB descriptor dumps    -> USBView.exe (Windows SDK)" -ForegroundColor DarkGray
Write-Host "    - Driver stack inspection -> WinDbg: !devstack, !devnode" -ForegroundColor DarkGray
Write-Host "    - Real-time I/O tracing   -> Process Monitor (Sysinternals)" -ForegroundColor DarkGray
Write-Host "    - UVC descriptor parsing  -> USBTreeView (Uwe Sieber)" -ForegroundColor DarkGray
Write-Host "    - Media Foundation types  -> MFCaptureD3D sample (Windows SDK)" -ForegroundColor DarkGray
Write-Host ""
