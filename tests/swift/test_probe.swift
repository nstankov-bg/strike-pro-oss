// Tests for tools/strike-probe.swift. Uses virtual CoreMIDI endpoints owned by this process,
// so no module needs to be connected.

var client = MIDIClientRef()
MIDIClientCreate("strike-probe-tests" as CFString, nil, nil, &client)

/// A virtual source carrying the given properties (nil leaves a property unset).
func virtualSource(name: String, manufacturer: String?, model: String?, offline: Int32?) -> MIDIEndpointRef {
    var ep = MIDIEndpointRef()
    MIDISourceCreate(client, name as CFString, &ep)
    if let manufacturer { MIDIObjectSetStringProperty(ep, kMIDIPropertyManufacturer, manufacturer as CFString) }
    if let model { MIDIObjectSetStringProperty(ep, kMIDIPropertyModel, model as CFString) }
    if let offline { MIDIObjectSetIntegerProperty(ep, kMIDIPropertyOffline, offline) }
    return ep
}

func test_str() {
    let ep = virtualSource(name: "Probe Str Test", manufacturer: "Alesis", model: nil, offline: nil)
    expect(str(ep, kMIDIPropertyName) == "Probe Str Test", "name")
    expect(str(ep, kMIDIPropertyManufacturer) == "Alesis", "manufacturer")
    expect(str(ep, kMIDIPropertyModel) == nil, "unset property is nil")
    MIDIEndpointDispose(ep)
}

func test_int() {
    let ep = virtualSource(name: "Probe Int Test", manufacturer: nil, model: nil, offline: 1)
    expect(int(ep, kMIDIPropertyOffline) == 1, "offline")
    expect(int(MIDIObjectRef(0), kMIDIPropertyOffline) == nil, "invalid object gives nil")
    MIDIEndpointDispose(ep)
}

func test_matchDecision() {
    expect(matchDecision(offline: 0, manufacturer: "ALESIS", model: "Alesis Strike", name: "alesis strike MIDI 1").0, "case-insensitive substring match")
    let cases: [(Int32?, String?, String?, String?, String)] = [
        (nil, "Alesis", "Alesis Strike", "Alesis Strike", "offline"),
        (1, "Alesis", "Alesis Strike", "Alesis Strike", "offline"),
        (0, "inMusic", "Alesis Strike", "Alesis Strike", "manufacturer"),
        (0, "Alesis", "Strike", "Alesis Strike", "model"),
        (0, "Alesis", "Alesis Strike", "Strike Port 1", "name"),
        (0, "Alesis", "Alesis Strike", nil, "name"),
    ]
    for (offline, mfr, model, name, reason) in cases {
        let (ok, desc) = matchDecision(offline: offline, manufacturer: mfr, model: model, name: name)
        expect(!ok && desc.contains("rejected: \(reason)"), "expected rejection for \(reason): \(desc)")
    }
}

func test_editorMatches() {
    let good = virtualSource(name: "Alesis Strike", manufacturer: "Alesis", model: "Alesis Strike", offline: 0)
    let bad = virtualSource(name: "Strike Port 1", manufacturer: "Alesis", model: "Alesis Strike", offline: 0)
    expect(editorMatches(good).0, "virtual Alesis Strike endpoint should match")
    expect(!editorMatches(bad).0, "renamed port should be rejected")
    MIDIEndpointDispose(good)
    MIDIEndpointDispose(bad)
}

func test_probeMIDI() {
    var lines: [String] = []
    let before = probeMIDI { lines.append($0) }
    expect(lines.first?.hasPrefix("== MIDI") == true, "header")
    expect(lines.last?.contains("result:") == true, "summary line")

    let src = virtualSource(name: "Alesis Strike", manufacturer: "Alesis", model: "Alesis Strike", offline: 0)
    var dst = MIDIEndpointRef()
    MIDIDestinationCreateWithBlock(client, "Alesis Strike" as CFString, &dst) { _, _ in }
    MIDIObjectSetStringProperty(dst, kMIDIPropertyManufacturer, "Alesis" as CFString)
    MIDIObjectSetStringProperty(dst, kMIDIPropertyModel, "Alesis Strike" as CFString)
    MIDIObjectSetIntegerProperty(dst, kMIDIPropertyOffline, 0)
    let after = probeMIDI { _ in }
    expect(after.source && after.destination, "virtual endpoints should be found (before: \(before))")
    MIDIEndpointDispose(src)
    MIDIEndpointDispose(dst)
}

func test_mountAdvice() {
    expect(mountAdvice(volume: "STRIKE", mountPoint: "/Volumes/STRIKE", device: "/dev/disk4s1").isEmpty, "matching paths need no advice")
    expect(mountAdvice(volume: nil, mountPoint: "/Volumes/X", device: "/dev/disk4s1").isEmpty, "unknown volume name")
    expect(mountAdvice(volume: "STRIKE", mountPoint: nil, device: "/dev/disk4s1").isEmpty, "not mounted")
    let advice = mountAdvice(volume: "STRIKE", mountPoint: "/Volumes/STRIKE 1", device: "/dev/disk4s1").joined(separator: "\n")
    expect(advice.contains("WARNING"), "warning")
    expect(advice.contains("sudo rmdir \"/Volumes/STRIKE\""), "stale folder removal")
    expect(advice.contains("diskutil unmount /dev/disk4s1 && diskutil mount /dev/disk4s1"), "remount command")
    let collision = mountAdvice(volume: "NO NAME", mountPoint: "/Volumes/NO NAME 1", device: "/dev/disk5s1",
                                occupiedBy: "/dev/disk6s1").joined(separator: "\n")
    expect(collision.contains("different drive (/dev/disk6s1)"), "collision is reported as such")
    expect(collision.contains("diskutil rename /dev/disk5s1"), "suggests relabelling")
    expect(!collision.contains("rmdir"), "must not suggest removing a real mount point")
    let selfOccupied = mountAdvice(volume: "X", mountPoint: "/Volumes/X 1", device: "/dev/disk5s1", occupiedBy: "/dev/disk5s1")
    expect(selfOccupied.joined().contains("rmdir"), "same device falls back to the stale-folder advice")
}

func test_mountedDevice() {
    expect(mountedDevice(at: "/")?.hasPrefix("/dev/disk") == true, "root volume device: \(String(describing: mountedDevice(at: "/")))")
    expect(mountedDevice(at: "/usr") == nil, "/usr is not itself a mount point")
    expect(mountedDevice(at: "/definitely/not/here") == nil, "missing path")
}

func test_volumeInfo() {
    // Built through CF, like DADiskCopyDescription returns it.
    let d = NSMutableDictionary()
    d[kDADiskDescriptionVolumeNameKey as String] = "NO NAME"
    d[kDADiskDescriptionVolumePathKey as String] = URL(fileURLWithPath: "/Volumes/NO NAME", isDirectory: true)
    d[kDADiskDescriptionMediaWritableKey as String] = false
    let info = volumeInfo(d)
    expect(info.name == "NO NAME", "name \(String(describing: info.name))")
    expect(info.path == "/Volumes/NO NAME", "path \(String(describing: info.path))")
    expect(info.writable == false, "writable")
    let empty = volumeInfo(NSDictionary())
    expect(empty.name == nil && empty.path == nil && empty.writable == nil, "missing keys give nil")
}

func test_wholeDisks() {
    expect(wholeDisks(["disk6s1", "disk6", "disk5", "disk5", "disk10", "diskX"]) == ["disk10", "disk5", "disk6"], "\(wholeDisks(["disk6s1", "disk6", "disk5", "disk5", "disk10", "diskX"]))")
    expect(wholeDisks([]).isEmpty, "empty")
}

func test_bsdNames() {
    // The registry root's subtree contains this Mac's own disks.
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    let names = bsdNames(under: root)
    expect(names.contains { $0.hasPrefix("disk") }, "expected some disks under the registry root, got \(names.prefix(5))")
    expect(bsdNames(under: 0).isEmpty, "invalid entry gives no names")
}

func test_probeDrive() {
    var lines: [String] = []
    let found = probeDrive { lines.append($0) }
    expect(lines.first?.contains("== USB drive") == true, "header")
    let reportedMissing = lines.contains { $0.contains("no IORegistry service named") }
    expect(found != reportedMissing, "return value must agree with the report")
}

test("test_str", test_str)
test("test_int", test_int)
test("test_matchDecision", test_matchDecision)
test("test_editorMatches", test_editorMatches)
test("test_probeMIDI", test_probeMIDI)
test("test_mountAdvice", test_mountAdvice)
test("test_mountedDevice", test_mountedDevice)
test("test_volumeInfo", test_volumeInfo)
test("test_wholeDisks", test_wholeDisks)
test("test_bsdNames", test_bsdNames)
test("test_probeDrive", test_probeDrive)
finish()
