# Tidebar

**English** | [简体中文](README.zh-CN.md)

A tiny capsule that lives in the corner of your desktop. It stays one line tall, expands into a full dashboard when you hover over it, and gets out of the way when you go fullscreen for a movie or a game.

Built for people who keep several AI agent windows open at once: CPU, memory, network, file sync and your Claude Code usage, all at a glance.

**Native on both macOS and Windows. Nothing to install: download, unzip, double-click.**

<p align="center">
  <img src="docs/capsule.png" alt="Collapsed capsule" width="470"><br>
  <sub>Most of the time: one line in the corner</sub>
</p>
<p align="center">
  <img src="docs/expanded.png" alt="Expanded dashboard" width="430"><br>
  <sub>Hover to expand (Windows, private names masked)</sub>
</p>

## Download

Grab the latest version from the [Releases](../../releases/latest) page:

| System | File | Requirements |
|---|---|---|
| Windows | `Tidebar-windows.zip` | Windows 10 / 11 (uses the built-in .NET Framework 4.8, nothing extra to install) |
| macOS | `Tidebar-mac.zip` | macOS 13 or later, Apple silicon and Intel |

### The first launch gets blocked (this is expected)

The app is not signed with a paid developer certificate, so your system will warn you the first time:

- **Windows**: "Windows protected your PC" → click **More info** → **Run anyway**.
- **macOS**: "cannot verify the developer" → open **System Settings → Privacy & Security**, scroll down to Tidebar and click **Open Anyway**.

All the source code is in this repository, so you can read it or build it yourself (see below).

## What it shows

| Module | What you see | Default |
|---|---|---|
| System | CPU, memory (plus the app using the most), free space on the system drive, uptime | On |
| GPU (Windows) | NVIDIA GPU load, temperature, VRAM (hidden automatically if there is no NVIDIA card) | Auto |
| Network | Live speed, traffic this session, latency | On |
| Claude Code | Active windows, today / 5-hour usage; on macOS also a weekly ledger and a context-size traffic light for each window | Shown if installed |
| Syncthing | Sync progress, which devices are online, one-click rescan | Shown if installed |
| Antigravity (macOS) | Tasks running / waiting for you / idle | Shown if installed |

Everything is read and displayed locally on your own machine. **Nothing is uploaded anywhere.** The only network request is the latency check (by default to `cp.cloudflare.com/generate_204`), which you can change or turn off in the config.

The interface is currently in Chinese; English UI is planned.

## Settings

Right-click the capsule (on macOS, use the menu) → **Open config file**, edit, then choose **Reload config**.

- Windows: `%APPDATA%\Tidebar\config.ini`
- macOS: `~/Library/Application Support/Tidebar/config.json`

Every module can be turned off on its own. For latency you can change the test URL or route it through a local proxy.

## Build it yourself

- **Windows**: no Visual Studio needed, it uses the compiler that ships with Windows:
  ```powershell
  powershell -ExecutionPolicy Bypass -File windows\build.ps1
  ```
  Output: `windows\dist\Tidebar.exe`.
- **macOS**: with the Xcode command line tools installed:
  ```bash
  cd mac && ./build.sh
  ```
  Output: `mac/dist/Tidebar.app`.

## License

MIT
