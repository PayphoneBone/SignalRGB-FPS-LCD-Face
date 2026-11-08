<#
.SYNOPSIS
  Removes the SignalRGB FPS Bridge task, bridge files, plugin, and LCD face.
.PARAMETER InstallDir
  Bridge folder used at install time. Default: %LOCALAPPDATA%\SignalRGB-FPS-Bridge
.PARAMETER KeepSignalRGBFiles
  Leave the plugin and LCD face in Documents\WhirlwindFX.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = "",
    [switch]$KeepSignalRGBFiles,
    [string]$TargetDocuments = ""
)
$ErrorActionPreference = 'Continue'
$TaskName = 'SignalRGB FPS Bridge'
if (-not $TargetDocuments) { $TargetDocuments = [Environment]::GetFolderPath('MyDocuments') }
if (-not $InstallDir)      { $InstallDir = Join-Path $env:LOCALAPPDATA 'SignalRGB-FPS-Bridge' }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',"`"$($MyInvocation.MyCommand.Path)`"",
              '-InstallDir',"`"$InstallDir`"",'-TargetDocuments',"`"$TargetDocuments`"")
    if ($KeepSignalRGBFiles) { $argList += '-KeepSignalRGBFiles' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask       -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed task '$TaskName'"
}

# Stop the bridge, then PresentMon (it keeps its exe locked while running)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*fps_bridge.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$pmProcs = Get-CimInstance Win32_Process -Filter "Name LIKE 'PresentMon%'" |
    Where-Object { -not $_.ExecutablePath -or $_.ExecutablePath.StartsWith($InstallDir, [StringComparison]::OrdinalIgnoreCase) }
foreach ($p in $pmProcs) {
    Write-Host "Stopping PresentMon (PID $($p.ProcessId))"
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $p.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
}
if (Test-Path $InstallDir) {
    for ($i = 0; $i -lt 10 -and (Test-Path $InstallDir); $i++) {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $InstallDir) { Start-Sleep -Seconds 1 }
    }
    if (Test-Path $InstallDir) {
        Write-Host "Could not fully remove $InstallDir (a file is still in use). Reboot and delete it manually." -ForegroundColor Yellow
    } else {
        Write-Host "Removed $InstallDir"
    }
}

if (-not $KeepSignalRGBFiles) {
    foreach ($f in @("WhirlwindFX\Plugins\FPS_Bridge_Sensor.js", "WhirlwindFX\LCDFaces\FPS Native Sensor.html", "WhirlwindFX\LCDFaces\fps.txt")) {
        $p = Join-Path $TargetDocuments $f
        if (Test-Path $p) { Remove-Item $p -Force; Write-Host "Removed $p" }
    }
    Write-Host "Restart SignalRGB to unload the plugin."
}
Write-Host "Uninstall complete."
