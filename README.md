# Dynamic Island for Windows 🏝️

A sleek, macOS-inspired **Dynamic Island & Dashboard overlay** built natively for Windows 10/11 using PowerShell and WPF with hardware acceleration.

Features an ultra-responsive compact pill that expands into a modern frosted Hitodama-style dashboard with live circular telemetry rings, 60 FPS animated audio equalizer, system controls, and one-click aura color customization.

---

## ✨ Features

- **🏝️ Dynamic Compact Pill**: Floats at the top of your screen showing time, battery status with charging glyph, and live CPU load.
- **⚡ 60 FPS Zero-Lag Animation**: Hardware-accelerated expand/collapse using `CubicEase` curves with zero stutter.
- **📊 Circular Ring Gauges (Hitodama UI)**:
  - **CPU Load %** (Cyan aura arc)
  - **GPU Utilization %** (Purple aura arc)
  - **RAM Memory %** (Emerald aura arc)
- **🎵 Animated Audio Visualizer**:
  - Live 7-bar audio visualizer with dynamic heights while music is playing.
  - Smooth undulating spline waveform curve under the track title.
  - Native Windows SMTC (System Media Transport Controls) integration with Spotify, YouTube, and media players.
  - Play, Pause, Previous, Next pill buttons.
- **🎛️ Quick Control Dashboard**:
  - One-click shortcuts for Wi-Fi and Bluetooth settings.
  - **Real Dark Mode toggle** (switches Windows Apps Theme between Dark and Light mode live).
  - Quick Task Manager launch.
  - Interactive master volume slider.
- **🖱️ Quick Volume Scroll**: Scroll your mouse wheel anywhere over the island to smoothly raise or lower master volume.
- **⚙️ Inline Customization Suite**:
  - 6 live one-click Aura Glow Presets: Cyan, Magenta, Purple, Emerald, Amber, and Crimson Red.
  - Live Glow Radius and Opacity sliders.
  - Enable/disable individual tabs (`Today`, `Media`, `Stats`, `Controls`, `Power`) or rings (`CPU`, `GPU`, `RAM`).
- **📍 Free Dragging & Memory**: Left-click and drag the island anywhere on screen. Position coordinates are automatically saved to `config.json` and restored on startup.
- **⏻ Power Center**: Quick tiles for Workstation Lock, Sleep, Restart, and Shutdown.
- **🚀 Background Runspace Engine**: All heavy hardware counters (CPU, GPU, RAM) and SMTC queries run in an isolated background runspace thread, keeping the UI at a buttery 60 FPS.
- **🛡️ Crash-Proof & Silent**: Uses preserved-signature COM interfaces (`[PreserveSig]`) to eliminate audio disconnect crashes, and launches completely hidden with zero console blips.

---

## 🚀 Quick Start

### 1. Run Silently (No Console Window)
Double-click:
```cmd
LaunchIsland.vbs
```

Or from terminal:
```cmd
wscript.exe "G:\island\LaunchIsland.vbs"
```

### 2. Autostart on Windows Logon
To have the island automatically start when you log into Windows:
```powershell
.\Install-Autostart.ps1
```
To remove from startup:
```powershell
.\Install-Autostart.ps1 -Uninstall
```

---

## 🛠️ File Structure

| File | Description |
|---|---|
| `Island.ps1` | Core WPF application engine with background runspace telemetry |
| `LaunchIsland.vbs` | Silent launcher script that hides the PowerShell console |
| `Install-Autostart.ps1` | Configures `shell:startup` shortcut targeting `wscript.exe` |
| `config.json` | Active user configuration (screen position, aura colors, module toggles) |
| `config.example.json` | Default reference configuration |

---

## 🎨 Customization

Click the **Gear icon (`⚙`)** in the expanded header to open the inline customization panel:
- **Aura Color Presets**: Switch between Cyan (`#00E5FF`), Magenta (`#FF007F`), Purple (`#A855F7`), Emerald (`#10B981`), Amber (`#FF9100`), and Crimson (`#FF1744`).
- **Glow Radius**: Adjust between `10px` and `45px`.
- **Glow Opacity**: Adjust between `20%` and `90%`.
- **Module Visibility**: Toggle individual navigation tabs and telemetry ring gauges on or off.

---

## 📄 License

MIT License. Free for personal and commercial use.
