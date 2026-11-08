# SignalRGB FPS LCD Face

Shows your live game FPS on a SignalRGB LCD as a single line — `FPS 144` — using Intel PresentMon.

SignalRGB has no built-in FPS sensor, and LCD faces are blocked from calling localhost
(`blocked face request to 127.0.0.1: private, loopback or link-local address`). This project
works around that by feeding FPS into SignalRGB as a native sensor:

```
PresentMon ──► fps_bridge.ps1 ──UDP 41732──► FPS_Bridge_Sensor.js ──► "Game FPS" sensor ──► FPS Native Sensor.html (LCD)
```

## Quick install

1. Download this repo (**Code → Download ZIP**) and extract it anywhere.
2. Double-click **`install.bat`** and approve the admin prompt.
3. In SignalRGB, add the **FPS Native Sensor** block to your LCD and set **FPS Sensor → FPS Bridge → Game FPS**.

The installer works on any PC and any account. It needs no particular drive letters or usernames:

- finds your real Documents folder (including OneDrive-redirected ones)
- installs the bridge to `%LOCALAPPDATA%\SignalRGB-FPS-Bridge` (or a folder you choose)
- finds PresentMon, or offers to download the latest from [GameTechDev/PresentMon](https://github.com/GameTechDev/PresentMon/releases)
- registers a startup task for **whoever runs the installer**

Full guide, manual install, and troubleshooting: **[docs/SETUP.md](docs/SETUP.md)**

## Repo contents

| Path | Purpose |
|---|---|
| `install.bat` / `install.ps1` | One-step installer |
| `uninstall.bat` / `uninstall.ps1` | Removes the task, bridge, plugin, and face |
| `bridge/fps_bridge.ps1` | Runs PresentMon, measures the foreground app's FPS, sends it over local UDP |
| `bridge/start_fps_bridge.bat` | Optional manual launcher (runs the bridge as admin from its own folder) |
| `signalrgb/Plugins/FPS_Bridge_Sensor.js` | SignalRGB plugin that publishes the `Game FPS` sensor |
| `signalrgb/LCDFaces/FPS Native Sensor.html` | LCD face showing `FPS xxx` |

PresentMon isn't bundled here. Get it from Intel's official releases.

Tested with SignalRGB 2.5.86 and PresentMon 2.6.0 on Windows 11.

## Known limitations

- **Foreground app only.** FPS is measured for whatever window has focus. Alt-tabbing changes what's measured.
- **Temperature-sensor transport.** `Game FPS` is reported through SignalRGB's temperature-sensor API, so it may show a °C unit elsewhere. **Never use it as a fan-curve source.**
- **Startup ordering bug (SignalRGB 2.5.86).** SignalRGB can restore the LCD layout before custom faces are loaded, so the FPS block is blank after boot. Workaround: switch to another LCD profile and back. See [Troubleshooting](docs/SETUP.md#troubleshooting).
- Present-rate FPS, roughly 1-second updates; not a replacement for a frame-time overlay.

## License

MIT
