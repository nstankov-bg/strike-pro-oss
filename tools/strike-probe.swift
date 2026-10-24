// strike-probe.swift — replays the Strike editor's (1.1.6) device-detection checks and explains failures.
// Run (interpreted, no compiled binary needed): swift tools/strike-probe.swift
//
// Behaviour observed in the 1.1.6 editor (see docs/detection.md):
//   MIDI  — MA::LMidiComm::OpenMidiOutputPort / StartMidiInput: for every non-offline CoreMIDI
//           destination/source, lowercase substring match of
//           Manufacturer ⊇ "alesis", Model ⊇ "alesis strike", Name ⊇ "alesis strike"
//           (descriptor from LStrikeDevice::GetMidiOutputPortDescriptor).
//   Drive — registerForUSBNotifications: IOServiceNameMatching("Alesis Strike"), then
//           USBDeviceCallback requires IORegistryEntryGetName == "Alesis Strike";
//           GetMountPoint: recursive "BSD Name" under each logical unit, assumes "/dev/<bsd>s1",
//           volume name via DiskArbitration, path "/Volumes/<name>", confirmed via getfsstat.

import CoreMIDI
import DiskArbitration
import Foundation
import IOKit

typealias Output = (String) -> Void

func str(_ obj: MIDIObjectRef, _ key: CFString) -> String? {
    var s: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(obj, key, &s) == noErr, let v = s?.takeRetainedValue() else { return nil }
    return v as String
}

func int(_ obj: MIDIObjectRef, _ key: CFString) -> Int32? {
    var v: Int32 = 0
    return MIDIObjectGetIntegerProperty(obj, key, &v) == noErr ? v : nil
}

/// The editor's acceptance rule for one endpoint, given its properties.
func matchDecision(offline: Int32?, manufacturer: String?, model: String?, name: String?) -> (Bool, String) {
    func q(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "nil" }
    let desc = "manufacturer=\(q(manufacturer)) model=\(q(model)) name=\(q(name)) offline=\(offline.map(String.init) ?? "nil")"
    guard offline == 0 else { return (false, desc + "  -> rejected: offline property not readable/zero") }
    guard let m = manufacturer, m.lowercased().contains("alesis") else { return (false, desc + "  -> rejected: manufacturer") }
    guard let md = model, md.lowercased().contains("alesis strike") else { return (false, desc + "  -> rejected: model") }
    guard let n = name, n.lowercased().contains("alesis strike") else { return (false, desc + "  -> rejected: name") }
    return (true, desc + "  -> MATCH")
}

func editorMatches(_ ep: MIDIEndpointRef) -> (Bool, String) {
    matchDecision(offline: int(ep, kMIDIPropertyOffline), manufacturer: str(ep, kMIDIPropertyManufacturer),
                  model: str(ep, kMIDIPropertyModel), name: str(ep, kMIDIPropertyName))
}

/// Checks every CoreMIDI destination and source. Returns whether each direction has a match.
@discardableResult
func probeMIDI(_ out: Output = { print($0) }) -> (destination: Bool, source: Bool) {
    out("== MIDI (editor needs one matching destination AND one matching source)")
    var destOK = false, srcOK = false
    for i in 0..<MIDIGetNumberOfDestinations() {
        let (ok, d) = editorMatches(MIDIGetDestination(i)); destOK = destOK || ok
        out("  dest[\(i)] \(d)")
    }
    for i in 0..<MIDIGetNumberOfSources() {
        let (ok, d) = editorMatches(MIDIGetSource(i)); srcOK = srcOK || ok
        out("  src[\(i)]  \(d)")
    }
    out("  result: destination \(destOK ? "FOUND" : "MISSING"), source \(srcOK ? "FOUND" : "MISSING")")
    return (destOK, srcOK)
}

/// Lines to print when the drive is mounted somewhere other than the "/Volumes/<name>" the editor builds.
/// Empty when the paths agree. The probe prints these; it never runs them.
func mountAdvice(volume: String?, mountPoint: String?, device: String) -> [String] {
    guard let vol = volume, let mnt = mountPoint, mnt != "/Volumes/\(vol)" else { return [] }
    // Usually a leftover "/Volumes/<name>" from an unclean unplug pushes the real mount to "<name> 1".
    return [
        "  WARNING: actual mount path differs from what the editor builds",
        "  Suggested fix (review first; this probe never runs it):",
        "    1. quit the editor and wait for any transfers to the module to finish",
        "    2. ls -la \"/Volumes/\(vol)\"        # should be an empty, stale folder",
        "    3. sudo rmdir \"/Volumes/\(vol)\"    # only if step 2 showed it empty",
        "    4. diskutil unmount \(device) && diskutil mount \(device)",
    ]
}

/// Follows the editor's drive lookup. Returns whether an "Alesis Strike" registry service exists.
@discardableResult
func probeDrive(_ out: Output = { print($0) }) -> Bool {
    out("\n== USB drive (IORegistry service named exactly \"Alesis Strike\")")
    var iter: io_iterator_t = 0
    var found = false
    if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching("Alesis Strike"), &iter) == KERN_SUCCESS {
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            found = true
            var cls = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(svc, &cls)
            out("  service class=\(String(cString: cls))")
            if let bsd = IORegistryEntrySearchCFProperty(svc, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault,
                                                         IOOptionBits(kIORegistryIterateRecursively)) as? String {
                let dev = "/dev/\(bsd)s1"
                out("  BSD Name=\(bsd)  editor assumes partition \(dev)")
                if let session = DASessionCreate(kCFAllocatorDefault),
                   let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, dev),
                   let d = DADiskCopyDescription(disk) as? [CFString: Any] {
                    let vol = d[kDADiskDescriptionVolumeNameKey] as? String
                    let mnt = (d[kDADiskDescriptionVolumePathKey] as? URL)?.path
                    out("  volume name=\(vol ?? "nil")  editor will use /Volumes/\(vol ?? "?")  actual mount=\(mnt ?? "not mounted")")
                    mountAdvice(volume: vol, mountPoint: mnt, device: dev).forEach(out)
                } else {
                    out("  WARNING: \(dev) not found — editor's partition-1 assumption fails")
                }
            } else {
                out("  WARNING: no BSD Name under this service (drive not exposed/mounted)")
            }
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        IOObjectRelease(iter)
    }
    if !found { out("  no IORegistry service named \"Alesis Strike\" (kit not connected, or macOS names it differently)") }
    return found
}

// Tests load this file with STRIKE_TEST set and call the functions directly.
if ProcessInfo.processInfo.environment["STRIKE_TEST"] == nil {
    probeMIDI()
    probeDrive()
}
