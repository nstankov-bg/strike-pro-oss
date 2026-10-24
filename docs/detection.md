# How the editor finds the module

Observed behaviour of the Strike editor 1.1.6 (Apple Silicon build), from static analysis for interoperability. The editor finds the module in two independent ways. If either fails, part of the app stops working.

`tools/strike-probe.swift` replays both checks and prints which one fails and why.

## 1. MIDI (kit and parameter editing)

At startup, and when hardware changes, the editor scans every CoreMIDI destination (output) and source (input). An endpoint is accepted only if all of these hold:

| Property | Requirement (case-insensitive substring) |
|---|---|
| `kMIDIPropertyOffline` | readable and `0` |
| `kMIDIPropertyManufacturer` | contains `alesis` |
| `kMIDIPropertyModel` | contains `alesis strike` |
| `kMIDIPropertyName` | contains `alesis strike` |

It needs one matching destination and one matching source. While connected, the editor sends the module a periodic keep-alive message. If that stops, the editor shows "Device Disconnected".

## 2. USB drive (kits, instruments and samples)

1. Register for IOKit matching notifications on a service whose registry name is exactly `Alesis Strike`.
2. Under that service, search recursively for the `BSD Name` of the disk (for example `disk4`).
3. Assume the content lives on partition 1: `/dev/disk4s1`.
4. Ask DiskArbitration for that partition's volume name, then build the path `/Volumes/<volume name>`.
5. Confirm it against the mounted filesystems (`getfsstat`).

The module exposes **two** drives under that service, one whole disk each:

| Drive | Typical size | Access | Contents |
|---|---|---|---|
| internal (factory) | ~8 GB | read-only | `Kits/`, `Instruments/`, `Samples/`, `Loops/`, `Ext/` |
| user (SD card) | card size | writable | your kits, instruments and samples |

Both are formatted FAT32 and usually labelled `NO NAME`.

### Known ways this breaks

- **Label collision.** Both drives are labelled `NO NAME`, so macOS mounts one at `/Volumes/NO NAME` and the other at `/Volumes/NO NAME 1`. A path built from the label alone, `/Volumes/<volume name>`, then points at the wrong drive. The editor also records the real mount points from `getfsstat`, but which of the two paths its browsers use hasn't been confirmed. The probe flags the collision and suggests giving the card a unique label.

- **Suffixed mount point.** A stale `/Volumes/<name>` folder left by an unclean unplug makes macOS mount the drive at `/Volumes/<name> 1`. The editor still builds `/Volumes/<name>`, so the file browsers stay empty. The probe detects this and prints the fix.
- **Different partition layout.** If the content isn't on partition `s1`, the drive isn't found.
- **Registry name changes.** If a future macOS names the USB device differently, the matching notification never fires.

## Other observations

- The editor optionally `dlopen`s `DeviceControlClient.dylib` from the folder that contains the app bundle, and resolves `AADI_*` functions for remote-device control. If the file isn't there, it skips it without an error. The module works without it.
- The device-matching strings live in the executable, which this project never modifies. Rebranding touches only resources and `Info.plist`.
- Keyboard shortcuts come from `GHK.<command>` entries in `StringTables.xml`. The stock entry for plain *Save* names a command the app never registers, so `build.sh` rebinds the shortcut to *Save As*.
