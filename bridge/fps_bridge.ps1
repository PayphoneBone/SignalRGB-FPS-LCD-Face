# fps_bridge.ps1
# Reads live frame data from Intel PresentMon and sends the FPS of the
# foreground window to SignalRGB once per second:
#   http://localhost:16034/canvas/event?sender=fpsbridge&event=<fps>
# Put this file in the same folder as PresentMon-x.x.x-x64.exe.
# Needs admin (or membership in "Performance Log Users") for PresentMon.

param(
    [string]$PresentMon = "",
    [int]$Port = 16034,
    [string]$Sender = "fpsbridge"
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $PresentMon) {
    $pm = Get-ChildItem -Path $here -Filter "PresentMon*.exe" -ErrorAction SilentlyContinue |
          Sort-Object Name -Descending | Select-Object -First 1
    if (-not $pm) {
        Write-Host "Couldn't find PresentMon*.exe in $here" -ForegroundColor Red
        Write-Host "Download the console exe from https://github.com/GameTechDev/PresentMon/releases and put it next to this script."
        Read-Host "Press Enter to exit"
        exit 1
    }
    $PresentMon = $pm.FullName
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FgWin {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    public static uint Pid() { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid; }
}
"@

$baseUrl = "http://localhost:$Port/canvas/event?sender=$Sender&event="
$web = New-Object System.Net.WebClient

function Send-Fps([int]$value) {
    $u = $baseUrl + $value
    try { [void]$web.UploadString($u, "POST", "") }
    catch {
        # Docs show both POST and GET; fall back to GET if POST is refused.
        try { [void]$web.DownloadString($u) } catch { }
    }
}

# UDP feed for the FPS_Bridge_Sensor SignalRGB plugin
$udp = New-Object System.Net.Sockets.UdpClient
$announce = [System.Text.Encoding]::UTF8.GetBytes('{"service":"fps-bridge-local","command":"device"}')
$lastAnnounce = [DateTime]::MinValue
function Send-Udp([int]$value) {
    try {
        if (([DateTime]::Now - $script:lastAnnounce).TotalSeconds -ge 2) {
            [void]$udp.Send($announce, $announce.Length, "127.0.0.1", 41731)
            $script:lastAnnounce = [DateTime]::Now
        }
        $b = [System.Text.Encoding]::ASCII.GetBytes([string]$value)
        [void]$udp.Send($b, $b.Length, "127.0.0.1", 41732)
    } catch { }
}

# fps.txt next to the LCD face, as a fallback data path
$fpsFile = $null
try {
    $facesDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WhirlwindFX\LCDFaces'
    if (Test-Path $facesDir) { $fpsFile = Join-Path $facesDir 'fps.txt' }
} catch { }

# Local endpoint for the LCD face: http://127.0.0.1:16035/fps -> "144"
$script:currentFps = 0
$listener = $null
$ctxTask = $null
try {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:16035/")
    $listener.Start()
    $ctxTask = $listener.GetContextAsync()
} catch {
    Write-Host "Couldn't open http://127.0.0.1:16035/ (run as admin). LCD face polling won't work." -ForegroundColor Yellow
    $listener = $null
}

Add-Type -AssemblyName System.Drawing

# PNG whose width = fps + 1 (height 1). Lets the face read FPS via <img>.
function Get-FpsPng([int]$fps) {
    $w = [Math]::Min([Math]::Max($fps + 1, 1), 4000)
    $bmp = New-Object System.Drawing.Bitmap($w, 1)
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $ms.ToArray()
}

function Serve-Requests {
    if ($null -eq $listener) { return }
    while ($script:ctxTask.IsCompleted) {
        try {
            $ctx = $script:ctxTask.Result
            $req = $ctx.Request
            $res = $ctx.Response
            # CORS + Private Network Access so a sandboxed page may call localhost
            $res.AddHeader("Access-Control-Allow-Origin", "*")
            $res.AddHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
            $res.AddHeader("Access-Control-Allow-Headers", "*")
            $res.AddHeader("Access-Control-Allow-Private-Network", "true")
            $res.AddHeader("Cache-Control", "no-store")

            if ($req.HttpMethod -eq "OPTIONS") {
                $res.StatusCode = 204
                $res.Close()
            }
            else {
                if ($req.Url.AbsolutePath -like "*.png") {
                    $bytes = Get-FpsPng $script:currentFps
                    $res.ContentType = "image/png"
                } else {
                    $bytes = [System.Text.Encoding]::ASCII.GetBytes([string]$script:currentFps)
                    $res.ContentType = "text/plain"
                }
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                $res.Close()
            }
        } catch { }
        $script:ctxTask = $listener.GetContextAsync()
    }
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $PresentMon
$psi.Arguments = "--output_stdout --no_console_stats --stop_existing_session --session_name FpsBridge"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.CreateNoWindow = $true

Write-Host "Starting $($PresentMon | Split-Path -Leaf) ..."
$p = [System.Diagnostics.Process]::Start($psi)

$pidCol  = -1
$counts  = @{}
$window  = [System.Diagnostics.Stopwatch]::StartNew()
$task    = $p.StandardOutput.ReadLineAsync()

try {
    while (-not $p.HasExited) {
        Serve-Requests
        if ($task.Wait(200)) {
            $line = $task.Result
            if ($null -eq $line) { break }
            $task = $p.StandardOutput.ReadLineAsync()

            if ($pidCol -lt 0) {
                if ($line -match "ProcessID") {
                    $cols = @($line.Split(',') | ForEach-Object { $_.Trim().Trim('"') })
                    $pidCol = [Array]::IndexOf($cols, "ProcessID")
                    Write-Host "Capturing. Leave this window open. Ctrl+C to stop." -ForegroundColor Green
                }
                continue
            }

            $f = $line.Split(',')
            if ($f.Length -gt $pidCol) {
                $k = $f[$pidCol].Trim().Trim('"')
                if ($counts.ContainsKey($k)) { $counts[$k]++ } else { $counts[$k] = 1 }
            }
        }

        if ($window.Elapsed.TotalMilliseconds -ge 1000) {
            $secs = $window.Elapsed.TotalSeconds
            $fg   = [string][FgWin]::Pid()
            $fps  = 0
            if ($counts.ContainsKey($fg)) { $fps = [int][Math]::Round($counts[$fg] / $secs) }
            $script:currentFps = $fps
            Send-Udp $fps
            if ($fpsFile) { try { [System.IO.File]::WriteAllText($fpsFile, [string]$fps) } catch { } }
            Send-Fps $fps
            Write-Host ("`rFPS: {0,5}   (foreground pid {1})      " -f $fps, $fg) -NoNewline
            $counts.Clear()
            $window.Restart()
        }
    }
}
finally {
    Send-Fps 0
    if ($listener) { try { $listener.Stop() } catch { } }
    if (-not $p.HasExited) { try { $p.Kill() } catch { } }
}

Write-Host ""
Write-Host "PresentMon stopped (exit code $($p.ExitCode))." -ForegroundColor Yellow
Write-Host "If it said 'access denied', run start_fps_bridge.bat (it asks for admin)."
Read-Host "Press Enter to exit"
