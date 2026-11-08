# Dynamic Island for Windows 🏝️

A sleek, macOS-inspired **Dynamic Island & Dashboard overlay** built natively for Windows 10/11 using PowerShell and WPF with hardware acceleration.

Features an ultra-responsive compact pill that expands into a modern frosted glass Hitodama-style dashboard with live circular telemetry rings, 60 FPS animated audio equalizer, system controls, interactive app launcher, stealth Game Mode HUD, and one-click aura color customization.

---

## ✨ Features

- **🏝️ Dynamic Compact Pill**: Floats seamlessly at the top or docked edges of your screen, displaying time, battery with live charging indicator, and real-time CPU load.
- **⚡ 60 FPS Zero-Lag Animation**: Hardware-accelerated expand/collapse using smooth `CubicEase` curves with zero stutter.
- **📱 Apps Launcher**:
  - 3-column glass app launcher tab (`Today · Apps · Media · Stats · Controls · Power`).
  - Automatically extracts high-resolution icons directly from application `.exe` binaries.
  - One-click launch with process working directory binding.
  - Interactive `+ Add App` modal dialog with file picker.
- **🎮 Stealth Game Mode HUD & Hover Dropdown**:
  - Automatically detects when a game launches into fullscreen or borderless window (e.g. *VALORANT*, *CS2*, *GTA V*).
  - Compact 46px stealth capsule showing live title badge (`● LIVE VALORANT`), CPU/GPU temperatures and loads, and system clock.
  - **Interactive Hover Dropdown**: Hovering over the Game HUD for 180ms smoothly expands an in-depth overlay featuring session duration, display resolution & refresh rate (e.g. `2560x1600 @ 240Hz`), FPS and frame time, live network ping, mini hardware progress bars (CPU, GPU, RAM, VRAM), thermal warning alerts, and quick gaming toggles (**Mute Mic**, **Mute Audio**, **Screenshot**, **Turbo Mode**, and **Pin HUD**).
  - Instant toggle anytime via global hotkey <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>G</kbd> or right-click context menu.
- **📊 Circular Ring Gauges (Hitodama UI)**:
  - **CPU Load %** (Cyan aura arc with clock speed and temperatures)
  - **GPU Utilization %** (Purple aura arc with clock speed and VRAM usage)
  - **RAM Memory %** (Emerald aura arc with used/total gigabytes)
- **🎵 Animated Audio Visualizer & Media Hub**:
  - Live 7-bar audio visualizer with dynamic heights while music is playing.
  - High-resolution track album artwork with automatic iTunes Search API fallback and local caching.
  - Native Windows SMTC (System Media Transport Controls) integration supporting Spotify, YouTube, web browsers, and desktop players.
  - Play, Pause, Previous, Next pill buttons.
- **🎛️ Quick Control Surface**:
  - Real hardware display brightness slider supporting laptop panels (`WmiSetBrightness`), external monitors (`dxva2.dll` DDC/CI), and smooth software gamma ramps.
  - Master volume slider with mouse-wheel volume scroll anywhere over the island.
  - Dark mode toggle, Night Light toggle, and one-click shortcuts to Windows Settings and Task Manager.
- **🛡️ Safe Power Management**:
  - 2.0-second safety hold-to-confirm timer for **Restart** and **Shutdown** actions to prevent accidental triggers.
  - Instant workstation lock and sleep tiles.
- **📍 Free Dragging & Screen Clamping**: Left-click and drag the island anywhere on screen. Position coordinates are automatically saved to `config.json` and restored on startup with screen-edge boundary clamping.
- **🎨 Inline Customization Suite**:
  - 6 live one-click Aura Glow Presets: Cyan, Magenta, Purple, Emerald, Amber, and Crimson Red.
  - Glow Radius and Opacity sliders.
  - Module and tab visibility toggles.
- **🚀 Isolated Background Runspace Engine**: All heavy hardware counters (CPU, GPU, RAM, VRAM) and SMTC queries run in an isolated background thread, guaranteeing fluid 60 FPS UI performance.

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

## ⌨️ Shortcuts & Hotkeys

| Hotkey | Action |
|---|---|
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>G</kbd> | Toggle Game Mode HUD & Dropdown |
| <kbd>Ctrl</kbd> + <kbd>R</kbd> | Hot-reload Dynamic Island |
| <kbd>Esc</kbd> | Collapse expanded island / close dropdown |
| Scroll Wheel over Island | Increase / decrease master volume |

---

## 🛠️ File Structure

| File | Description |
|---|---|
| `Island.ps1` | Core WPF application engine with background runspace telemetry and Game HUD |
| `LaunchIsland.vbs` | Silent launcher script that hides the PowerShell console |
| `Install-Autostart.ps1` | Configures `shell:startup` shortcut targeting `wscript.exe` |
| `config.json` | Active user configuration (screen position, aura colors, apps list, module toggles) |
| `config.example.json` | Default reference configuration |
| `LICENSE` | Proprietary software license & terms of use |

---

## 📄 License & Terms of Use

Copyright © 2026. All Rights Reserved.

This software is provided for personal, non-commercial use only. Modification, decompilation, redistribution of modified versions, and unauthorized derivation or redistribution are strictly prohibited. See [LICENSE](LICENSE) for full details.
