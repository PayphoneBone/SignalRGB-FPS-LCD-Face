<#
.SYNOPSIS
  Installs the SignalRGB FPS LCD face, the FPS Bridge plugin, and the PresentMon bridge,
  and registers a scheduled task that starts the bridge when the current user signs in.

.PARAMETER InstallDir
  Where the bridge (fps_bridge.ps1 + PresentMon) is installed.
  Default: %LOCALAPPDATA%\SignalRGB-FPS-Bridge

.PARAMETER PresentMonPath
  Path to an existing PresentMon console exe. If omitted, the installer looks next to
  this script and in InstallDir, then offers to download the latest release from GitHub.

.PARAMETER NoTask
  Skip creating the startup scheduled task.

.EXAMPLE
  .\install.ps1
  .\install.ps1 -InstallDir "D:\Tools\FPSBridge"
#>
[CmdletBinding()]
param(
    [string]$InstallDir = "",
    [string]$PresentMonPath = "",
    [switch]$NoTask,
    # Internal: passed through when the script relaunches itself elevated, so the task and
    # Documents folder belong to the user who started the install, not the admin account.
    [string]$TargetUser = "",
    [string]$TargetDocuments = ""
)

$ErrorActionPreference = 'Stop'
$TaskName = 'SignalRGB FPS Bridge'
$repo     = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $TargetUser)      { $TargetUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }
if (-not $TargetDocuments) { $TargetDocuments = [Environment]::GetFolderPath('MyDocuments') }
if (-not $InstallDir)      { $InstallDir = Join-Path $env:LOCALAPPDATA 'SignalRGB-FPS-Bridge' }

# ---- Elevate (needed for a "highest privileges" task; PresentMon also needs admin) ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting administrator rights..." -ForegroundColor Yellow
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',"`"$($MyInvocation.MyCommand.Path)`"",
              '-InstallDir',"`"$InstallDir`"",'-TargetUser',"`"$TargetUser`"",'-TargetDocuments',"`"$TargetDocuments`"")
    if ($PresentMonPath) { $argList += @('-PresentMonPath',"`"$PresentMonPath`"") }
    if ($NoTask)         { $argList += '-NoTask' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

Write-Host ""
Write-Host "SignalRGB FPS LCD - installer" -ForegroundColor Cyan
Write-Host "  User:        $TargetUser"
Write-Host "  Documents:   $TargetDocuments"
Write-Host "  Bridge dir:  $InstallDir"
Write-Host ""

# ---- SignalRGB must be closed so it picks up the plugin/face ----
$srgb = Get-Process -Name 'SignalRgb*','SignalRGB*' -ErrorAction SilentlyContinue
if ($srgb) {
    Write-Host "SignalRGB is running. Quit it from the tray icon (right-click > Quit)." -ForegroundColor Yellow
    Read-Host  "Press Enter once SignalRGB is closed"
}

# ---- Stop an existing bridge so files can be replaced ----
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*fps_bridge.ps1*' } |
    ForEach-Object { Write-Host "Stopping running bridge (PID $($_.ProcessId))"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# ---- Bridge files ----
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item (Join-Path $repo 'bridge\fps_bridge.ps1')       $InstallDir -Force
Copy-Item (Join-Path $repo 'bridge\start_fps_bridge.bat') $InstallDir -Force

# ---- PresentMon ----
function Find-PresentMon([string[]]$dirs) {
    foreach ($d in $dirs) {
        if ($d -and (Test-Path $d)) {
            $f = Get-ChildItem -Path $d -Filter 'PresentMon*.exe' -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($f) { return $f.FullName }
        }
    }
    return $null
}

if ($PresentMonPath) {
    if (-not (Test-Path $PresentMonPath)) { throw "PresentMon not found at $PresentMonPath" }
    $pm = (Resolve-Path $PresentMonPath).Path
} else {
    $pm = Find-PresentMon @($InstallDir, $repo, (Join-Path $repo 'bridge'))
}

if (-not $pm) {
    $ans = Read-Host "PresentMon console exe not found. Download the latest from github.com/GameTechDev/PresentMon? [Y/n]"
    if ($ans -notmatch '^[nN]') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $rel   = Invoke-RestMethod 'https://api.github.com/repos/GameTechDev/PresentMon/releases/latest' -Headers @{ 'User-Agent' = 'signalrgb-fps-lcd' }
        $asset = $rel.assets | Where-Object { $_.name -match '^PresentMon-[\d.]+-x64\.exe$' } | Select-Object -First 1
        if (-not $asset) { throw "Couldn't find a PresentMon x64 console exe in release $($rel.tag_name). Download it manually and rerun with -PresentMonPath." }
        $pm = Join-Path $InstallDir $asset.name
        Write-Host "Downloading $($asset.name)..."
        Invoke-WebRequest $asset.browser_download_url -OutFile $pm -UseBasicParsing
    } else {
        throw "PresentMon is required. Download it from https://github.com/GameTechDev/PresentMon/releases and rerun with -PresentMonPath."
    }
}
if ((Split-Path -Parent $pm) -ne $InstallDir.TrimEnd('\')) {
    Copy-Item $pm $InstallDir -Force
    $pm = Join-Path $InstallDir (Split-Path -Leaf $pm)
}
Write-Host "PresentMon:  $pm" -ForegroundColor Green

# ---- SignalRGB plugin + LCD face ----
$plugins = Join-Path $TargetDocuments 'WhirlwindFX\Plugins'
$faces   = Join-Path $TargetDocuments 'WhirlwindFX\LCDFaces'
New-Item -ItemType Directory -Force -Path $plugins, $faces | Out-Null

# Remove an old .mjs copy that would conflict
$oldMjs = Join-Path $plugins 'FPS_Bridge_Sensor.mjs'
if (Test-Path $oldMjs) { Move-Item $oldMjs "$oldMjs.bak" -Force; Write-Host "Renamed old FPS_Bridge_Sensor.mjs to .bak" }

Copy-Item (Join-Path $repo 'signalrgb\Plugins\FPS_Bridge_Sensor.js')      $plugins -Force
Copy-Item (Join-Path $repo 'signalrgb\LCDFaces\FPS Native Sensor.html')   $faces   -Force
Write-Host "Plugin:      $plugins\FPS_Bridge_Sensor.js" -ForegroundColor Green
Write-Host "LCD face:    $faces\FPS Native Sensor.html" -ForegroundColor Green

# Clear "downloaded from the internet" flags
Get-ChildItem $InstallDir -File | Unblock-File
Unblock-File (Join-Path $plugins 'FPS_Bridge_Sensor.js')
Unblock-File (Join-Path $faces   'FPS Native Sensor.html')

# ---- Scheduled task (current user, at logon, elevated, interactive session) ----
if (-not $NoTask) {
    $script  = Join-Path $InstallDir 'fps_bridge.ps1'
    $action  = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
                 -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`"" `
                 -WorkingDirectory $InstallDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $TargetUser
    $trigger.Delay = 'PT30S'
    $principal = New-ScheduledTaskPrincipal -UserId $TargetUser -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                   -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Description 'Feeds PresentMon FPS to the SignalRGB FPS Bridge plugin.' -Force | Out-Null
    Write-Host "Task:        '$TaskName' (runs at sign-in for $TargetUser)" -ForegroundColor Green

    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Bridge started." -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Next:" -ForegroundColor Cyan
Write-Host "  1. Start SignalRGB (Settings > Windows Settings > Startup Behavior = on, to launch with Windows)."
Write-Host "  2. In your LCD layout add 'FPS Native Sensor' and set FPS Sensor = FPS Bridge > Game FPS."
Write-Host "  3. Launch a game and keep it focused."
Write-Host ""
