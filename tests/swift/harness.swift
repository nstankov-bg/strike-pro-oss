// Minimal test harness for the interpreted Swift scripts. tests/test_swift.py concatenates
// <script under test> + this file + <test file> and runs the result with `swift -`
// (STRIKE_TEST set, so the script's entry point doesn't run). No compiled binaries are produced.

var failures = 0
var currentTest = ""
var tempDirs: [String] = []

func expect(_ condition: Bool, _ message: @autoclosure () -> String = "", line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL \(currentTest) (line \(line)): \(message())")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    let before = failures
    do { try body() } catch { failures += 1; print("FAIL \(name): threw \(error)") }
    if failures == before { print("PASS \(name)") }
}

func finish() -> Never {
    tempDirs.forEach { try? FileManager.default.removeItem(atPath: $0) }
    print(failures == 0 ? "OK" : "FAILED (\(failures))")
    exit(failures == 0 ? 0 : 1)
}

func tempDir() -> String {
    let dir = NSTemporaryDirectory() + "strike-swift-test-" + UUID().uuidString
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    tempDirs.append(dir)
    return dir
}
