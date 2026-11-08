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

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*fps_bridge.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-Process -Name 'PresentMon*' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($InstallDir, [StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force; Write-Host "Removed $InstallDir" }

if (-not $KeepSignalRGBFiles) {
    foreach ($f in @("WhirlwindFX\Plugins\FPS_Bridge_Sensor.js", "WhirlwindFX\LCDFaces\FPS Native Sensor.html")) {
        $p = Join-Path $TargetDocuments $f
        if (Test-Path $p) { Remove-Item $p -Force; Write-Host "Removed $p" }
    }
    Write-Host "Restart SignalRGB to unload the plugin."
}
Write-Host "Uninstall complete."
