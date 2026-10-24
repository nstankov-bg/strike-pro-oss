# strike-pro-oss

Community tooling that keeps the discontinued **Alesis Strike** drum module editor usable on modern macOS (Apple Silicon, macOS 26).

> **Unofficial.** Not affiliated with, endorsed by or supported by Alesis or inMusic. "Alesis" and "Strike" are trademarks of their owners. This repository contains **no** Alesis code, binaries, images or other assets. Everything works on a copy of the editor you already own, and the build it produces is for your personal use. Don't redistribute it.

## What's here

| Path | What it does |
|---|---|
| `build.sh` | Builds **Strike Pro OSS.app** from your installed *Alesis Strike Editor 1.1.6*, without touching the original. See below for what the build changes. |
| `tools/strike-probe.swift` | Replays the editor's two module-detection checks (MIDI port and USB drive) and explains any failure, including fix commands for a mis-mounted drive. |
| `tools/strike-backup.sh` | Hard-linked snapshots of the module's drive to `~/StrikeBackups` (keeps 10; unchanged files take no extra space). Refuses to snapshot a drive that is mid-write or suddenly shrank. |
| `tools/install-backup-agent.sh` | Runs the backup automatically whenever the module's drive mounts. |
| `tools/strike-check.py` | Read-only preflight for WAV samples: names truncated, non-PCM, odd-format or duplicate files and folders over the 255-sample limit before the editor rejects them. Optional `--fix` writes 16-bit/44.1 kHz copies. |
| `branding/` | The text, logo, icon and optional colour-theme steps used by `build.sh`. |
| `docs/detection.md` | How the editor finds the module, and the ways that can break. |

## What `build.sh` changes

- **UI text:**
  - product name and logos become Strike Pro OSS;
  - the original typos are fixed;
  - the five preset-load errors that shared one message now each get a distinct, accurate message;
  - "module not found" now says what to check;
  - *Factory Content Update* becomes **Restore Factory Content from .bin…**, with a warning that it erases content;
  - the dead online-guide link points here.
- **Cmd/Ctrl+S** is rebound to *Save As*. The stock shortcut points at a command the app never registers.
- **Retina rendering** is enabled (`NSHighResolutionCapable`), with the classic light appearance for system dialogs.
- **With `--install`:**
  - copies the app to `/Applications`;
  - migrates your `UserSettings.ini`;
  - disables App Nap so the module keep-alive isn't throttled.
- **Optional `--theme graphite`:** recolours the main UI accent and background. It's a starting point, since PNG skin art isn't recoloured.

The editor's executable is never modified. The bundle is re-signed ad hoc, and the script prints the arm64 CDHash.

## Quick start

```sh
git clone https://github.com/nstankov-bg/strike-pro-oss && cd strike-pro-oss
./build.sh --install                       # needs /Applications/Alesis Strike Editor.app (1.1.6)
swift tools/strike-probe.swift             # with the module connected and powered on
./tools/install-backup-agent.sh            # automatic backups on every mount
python3 -I tools/strike-check.py ~/Samples/MyKit
```

Requirements: macOS with the Xcode Command Line Tools (for `swift`), and Python 3.

### Macs running Santa in Lockdown

The rebuilt app is ad-hoc signed, so it needs an allow rule. `build.sh` prints one (`CDHASH` + `ALLOWLIST`). Every rebuild changes the hash. `build.sh` skips rebuilding when its inputs haven't changed. The tools in `tools/` run through `swift`, `python3` and `zsh`, so they need no extra rules.

## Troubleshooting

1. Run `swift tools/strike-probe.swift` with the module connected.
2. **MIDI port missing:** check Audio MIDI Setup for an "Alesis Strike" device, and try another cable or port (avoid unpowered hubs).
3. **Drive mount path mismatch:** follow the commands the probe prints. The probe never runs them itself.
4. Backups log to `~/Library/Logs/strike-backup.log`. If launchd runs fail, allow `/bin/zsh` access to removable volumes in System Settings › Privacy & Security.

## License

MIT for everything in this repository. See [LICENSE](LICENSE).
