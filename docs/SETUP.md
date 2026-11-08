# Setup Guide

**Requirements:** Windows 10/11, [SignalRGB](https://signalrgb.com/) (tested 2.5.86), an account with admin rights.
PresentMon (tested 2.6.0) can be downloaded by the installer.

---

## Option A: Installer (recommended)

1. Download the repo (**Code → Download ZIP**) and extract it, e.g. to your Downloads folder.
2. Double-click **`install.bat`**. Approve the administrator (UAC) prompt.
3. When asked, quit SignalRGB (tray icon → right-click → **Quit**) and press Enter.
4. If PresentMon isn't found, answer **Y** to download the latest release from GitHub.
5. When it says **Done**, start SignalRGB.
6. **Devices** should list an **FPS Bridge** device.
7. Open your LCD layout → add the **FPS Native Sensor** block → set **FPS Sensor → FPS Bridge → Game FPS**.
8. Launch a game, keep it focused for ~10 seconds, and check the LCD.
9. Turn on **Settings → Windows Settings → Startup Behavior** in SignalRGB so it starts with Windows.
10. Reboot to confirm everything starts on its own.

### What the installer does

| Item | Location |
|---|---|
| Bridge script + PresentMon | `%LOCALAPPDATA%\SignalRGB-FPS-Bridge\` |
| Plugin | `<your Documents>\WhirlwindFX\Plugins\FPS_Bridge_Sensor.js` |
| LCD face | `<your Documents>\WhirlwindFX\LCDFaces\FPS Native Sensor.html` |
| Startup task | Task Scheduler → **SignalRGB FPS Bridge** |

The task is created for **the user who ran the installer**. It runs at that user's sign-in (30-second delay) with highest
privileges, in the interactive session, hidden, with no time limit, and only one copy at a time.
A different admin account at the UAC prompt is fine: the installer still targets the original user.

### Installer options

Run from PowerShell in the repo folder:

```powershell
# Install the bridge somewhere else
.\install.ps1 -InstallDir "D:\Tools\FPSBridge"

# Use a PresentMon exe you already have
.\install.ps1 -PresentMonPath "C:\Downloads\PresentMon-2.6.0-x64.exe"

# Install files only, no startup task
.\install.ps1 -NoTask
```

You can rerun the installer to update. It stops the running bridge, replaces the files, and re-creates the task.

### Uninstall

Double-click **`uninstall.bat`** (if you used a custom folder: `.\uninstall.ps1 -InstallDir "D:\Tools\FPSBridge"`).
Add `-KeepSignalRGBFiles` to keep the plugin and face. Then restart SignalRGB.

---

## Option B: Manual install

1. **Bridge:** create any folder (e.g. `C:\FPSBridge`). Copy `bridge\fps_bridge.ps1` and `bridge\start_fps_bridge.bat`
   into it. Put the PresentMon console exe (`PresentMon-x.x.x-x64.exe` from the
   [releases page](https://github.com/GameTechDev/PresentMon/releases)) in the **same folder**.
2. **Unblock:** right-click each file → **Properties** → tick **Unblock** if it's shown.
3. **SignalRGB files:** quit SignalRGB, then copy
   - `signalrgb\Plugins\FPS_Bridge_Sensor.js` → `Documents\WhirlwindFX\Plugins\`
   - `signalrgb\LCDFaces\FPS Native Sensor.html` → `Documents\WhirlwindFX\LCDFaces\`

   The plugin has to end in `.js`. Delete any `.mjs` copy.
4. **Test:** run `start_fps_bridge.bat` and approve the prompt. Then start SignalRGB and follow steps 6–8 of Option A.
5. **Startup task:** open `taskschd.msc` → **Create Task** (not Basic Task):
   - **General:** your account · *Run only when user is logged on* · *Run with highest privileges*
   - **Triggers:** *At log on* · *Specific user* = you · delay 30 seconds
   - **Actions:** Start a program
     - Program: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`
     - Arguments: `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\FPSBridge\fps_bridge.ps1"`
     - Start in: `C:\FPSBridge`
   - **Conditions:** untick *Start only if on AC power*
   - **Settings:** untick *Stop the task if it runs longer than*; *If already running* = *Do not start a new instance*

   Use your own folder path. Don't set the task to run as SYSTEM or "whether user is logged on or not". The bridge has to
   run in your desktop session to see which window is in the foreground.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| FPS block blank after reboot | Known SignalRGB 2.5.86 bug: the layout is restored before custom faces load. **Switch to another LCD profile and back.** Changing the sensor doesn't help. |
| `Game FPS` missing from the picker | Make sure the plugin is `.js` and in your Documents `WhirlwindFX\Plugins` folder. Restart SignalRGB and check the **FPS Bridge** device console for errors. |
| `FPS --` | Reselect **FPS Bridge → Game FPS** in the block settings. |
| `FPS 0` | The game isn't focused, or the bridge isn't running. Check Task Scheduler → **SignalRGB FPS Bridge** → *Last Run Result*, or look for `powershell`/`PresentMon` in Task Manager. |
| Works manually, not after reboot | Check the task's user account, *highest privileges*, logon trigger, and paths. Rerunning the installer re-creates the task. |
| "Failed to fetch" / localhost errors | An old HTTP-based face is installed. SignalRGB blocks LCD faces from reaching localhost. Use `FPS Native Sensor.html`. |
| Installer window closes instantly | Run it from PowerShell instead: `powershell -ExecutionPolicy Bypass -File .\install.ps1` |

The plugin console stays quiet on purpose. It logs errors, not every packet.

## How it works

```
PresentMon ──► fps_bridge.ps1 ──UDP──► FPS_Bridge_Sensor.js ──► "Game FPS" sensor ──► FPS Native Sensor.html
```

SignalRGB blocks LCD faces from making requests to localhost or private addresses. So the bridge sends FPS to a
SignalRGB plugin, and the plugin exposes it as a native sensor the face can read.
Everything stays on `127.0.0.1`: port `41731` carries discovery and `41732` carries FPS values.

`Game FPS` goes through SignalRGB's temperature-sensor API, so other screens may label it °C.
**Don't use it as a fan-curve source.**

## After SignalRGB updates

Updates usually leave `Documents\WhirlwindFX` alone. If FPS stops showing up, rerun `install.bat`, restart SignalRGB,
and reselect `Game FPS`.
