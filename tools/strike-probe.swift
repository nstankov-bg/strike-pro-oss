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

func str(_ obj: MIDIObjectRef, _ key: CFString) -> String? {
    var s: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(obj, key, &s) == noErr, let v = s?.takeRetainedValue() else { return nil }
    return v as String
}

func int(_ obj: MIDIObjectRef, _ key: CFString) -> Int32? {
    var v: Int32 = 0
    return MIDIObjectGetIntegerProperty(obj, key, &v) == noErr ? v : nil
}

func editorMatches(_ ep: MIDIEndpointRef) -> (Bool, String) {
    let offline = int(ep, kMIDIPropertyOffline)
    let mfr = str(ep, kMIDIPropertyManufacturer)
    let model = str(ep, kMIDIPropertyModel)
    let name = str(ep, kMIDIPropertyName)
    let desc = "manufacturer=\(mfr.map { "\"\($0)\"" } ?? "nil") model=\(model.map { "\"\($0)\"" } ?? "nil") name=\(name.map { "\"\($0)\"" } ?? "nil") offline=\(offline.map(String.init) ?? "nil")"
    guard offline == 0 else { return (false, desc + "  -> rejected: offline property not readable/zero") }
    guard let m = mfr, m.lowercased().contains("alesis") else { return (false, desc + "  -> rejected: manufacturer") }
    guard let md = model, md.lowercased().contains("alesis strike") else { return (false, desc + "  -> rejected: model") }
    guard let n = name, n.lowercased().contains("alesis strike") else { return (false, desc + "  -> rejected: name") }
    return (true, desc + "  -> MATCH")
}

print("== MIDI (editor needs one matching destination AND one matching source)")
var destOK = false, srcOK = false
for i in 0..<MIDIGetNumberOfDestinations() {
    let (ok, d) = editorMatches(MIDIGetDestination(i)); destOK = destOK || ok
    print("  dest[\(i)] \(d)")
}
for i in 0..<MIDIGetNumberOfSources() {
    let (ok, d) = editorMatches(MIDIGetSource(i)); srcOK = srcOK || ok
    print("  src[\(i)]  \(d)")
}
print("  result: destination \(destOK ? "FOUND" : "MISSING"), source \(srcOK ? "FOUND" : "MISSING")")

print("\n== USB drive (IORegistry service named exactly \"Alesis Strike\")")
var iter: io_iterator_t = 0
var found = false
if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching("Alesis Strike"), &iter) == KERN_SUCCESS {
    var svc = IOIteratorNext(iter)
    while svc != 0 {
        found = true
        var cls = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(svc, &cls)
        print("  service class=\(String(cString: cls))")
        if let bsd = IORegistryEntrySearchCFProperty(svc, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault,
                                                     IOOptionBits(kIORegistryIterateRecursively)) as? String {
            let dev = "/dev/\(bsd)s1"
            print("  BSD Name=\(bsd)  editor assumes partition \(dev)")
            if let session = DASessionCreate(kCFAllocatorDefault),
               let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, dev),
               let d = DADiskCopyDescription(disk) as? [CFString: Any] {
                let vol = d[kDADiskDescriptionVolumeNameKey] as? String
                let mnt = (d[kDADiskDescriptionVolumePathKey] as? URL)?.path
                print("  volume name=\(vol ?? "nil")  editor will use /Volumes/\(vol ?? "?")  actual mount=\(mnt ?? "not mounted")")
                if let vol, let mnt, mnt != "/Volumes/\(vol)" {
                    // Usually a leftover "/Volumes/<name>" from an unclean unplug pushes the real mount to "<name> 1".
                    print("  WARNING: actual mount path differs from what the editor builds")
                    print("  Suggested fix (review first; this probe never runs it):")
                    print("    1. quit the editor and eject nothing else that is writing to the module")
                    print("    2. ls -la \"/Volumes/\(vol)\"        # should be an empty, stale folder")
                    print("    3. sudo rmdir \"/Volumes/\(vol)\"    # only if step 2 showed it empty")
                    print("    4. diskutil unmount \(dev) && diskutil mount \(dev)")
                }
            } else {
                print("  WARNING: \(dev) not found — editor's partition-1 assumption fails")
            }
        } else {
            print("  WARNING: no BSD Name under this service (drive not exposed/mounted)")
        }
        IOObjectRelease(svc)
        svc = IOIteratorNext(iter)
    }
    IOObjectRelease(iter)
}
if !found { print("  no IORegistry service named \"Alesis Strike\" (kit not connected, or macOS names it differently)") }
