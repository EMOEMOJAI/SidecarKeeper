// sidecar-keeper: keep Sidecar connected to an iPad, event-driven, without notification spam.
//
// A connect is attempted only when all of these hold:
//   - not paused by the user (`sidecar-keeper pause`)
//   - the built-in screens are awake (NSWorkspace screensDidSleep/Wake, didWake)
//   - the login session is unlocked (com.apple.screenIsLocked/Unlocked)
//   - the lid is open (ioreg AppleClamshellState; Sidecar cannot create a virtual
//     display with the lid closed, error -501)
//   - the device shows up in `SidecarLauncher devices`
//   - in --wired mode, an iPad is attached over USB (a wired connect without a cable fails)
// Every failed connect raises a macOS "Unable to connect" notification, so failures
// back off (30 s doubling to 5 min; straight to 5 min on VirtualDisplay errors).
import AppKit
import Foundation

let version = "1.1.0"
let agentLabel = "com.sidecarkeeper.agent"

// MARK: - Configuration

struct Config {
    var device: String?            // nil = first device reported by `devices`
    var launcher: String
    var logPath: String
    var interval: TimeInterval = 15
    var settle: TimeInterval = 8   // wait after wake/unlock before the first attempt
    var timeout: TimeInterval = 30 // kill a hung launcher call after this long
    var wired = false              // pass -wired to SidecarLauncher and require a USB cable
    var usbMatch = "iPad"          // substring of the USB product name that counts as "cabled"
}

let home = NSHomeDirectory()
let stateDir = ProcessInfo.processInfo.environment["SIDECARKEEPER_STATE_DIR"] ?? home + "/.sidecarkeeper"
let pauseFile = stateDir + "/paused"
let defaultLog = home + "/Library/Logs/sidecar-keeper.log"

func usage() -> String {
    """
    usage: sidecar-keeper [run] [options]   run the watcher (what the LaunchAgent does)
           sidecar-keeper pause             stop reconnecting (e.g. you disconnected on purpose)
           sidecar-keeper resume            start reconnecting again
           sidecar-keeper status [--log PATH]
           sidecar-keeper --version | --help

    options:
      --device NAME      iPad name as shown by `SidecarLauncher devices`. Case and
                         straight/curly apostrophes are ignored when matching.
                         Default: the first reachable device.
      --launcher PATH    Path to the SidecarLauncher binary.
                         Default: SidecarLauncher next to this executable, else ~/bin/SidecarLauncher.
      --log PATH         Log file. Default: ~/Library/Logs/sidecar-keeper.log
      --interval SECONDS Poll interval. Default: 15
      --settle SECONDS   Delay after wake/unlock before reconnecting. Default: 8
      --timeout SECONDS  Give up on a hung SidecarLauncher call. Default: 30
      --wired            Experimental. Connect over the USB cable only (SidecarLauncher -wired).
                         Idles while no iPad is attached over USB, and restarts the session
                         when the cable comes back, because a wired session never recovers
                         by itself.
      --usb-match TEXT   USB product name that means "the iPad is cabled". Default: iPad
    """
}

func die(_ msg: String) -> Never {
    FileHandle.standardError.write("\(msg)\n".data(using: .utf8)!); exit(2)
}

func parseOptions(_ argv: [String]) -> Config {
    let exeDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
    let sibling = URL(fileURLWithPath: exeDir).appendingPathComponent("SidecarLauncher").path
    var cfg = Config(
        device: nil,
        launcher: FileManager.default.isExecutableFile(atPath: sibling) ? sibling : home + "/bin/SidecarLauncher",
        logPath: defaultLog)

    var args = argv.makeIterator()
    func value(_ flag: String) -> String {
        guard let v = args.next() else { die("missing value for \(flag)\n\(usage())") }
        return v
    }
    func seconds(_ flag: String, min: TimeInterval) -> TimeInterval {
        guard let n = TimeInterval(value(flag)), n >= min else { die("\(flag) must be a number >= \(Int(min))") }
        return n
    }
    while let a = args.next() {
        switch a {
        case "--device":   cfg.device = value(a)
        case "--launcher": cfg.launcher = (value(a) as NSString).expandingTildeInPath
        case "--log":      cfg.logPath = (value(a) as NSString).expandingTildeInPath
        case "--interval": cfg.interval = seconds(a, min: 1)
        case "--settle":   cfg.settle = seconds(a, min: 0)
        case "--timeout":  cfg.timeout = seconds(a, min: 1)
        case "--wired":    cfg.wired = true
        case "--usb-match": cfg.usbMatch = value(a)
        case "-h", "--help": print(usage()); exit(0)
        case "--version":  print(version); exit(0)
        default: die("unknown argument: \(a)\n\(usage())")
        }
    }
    return cfg
}

// MARK: - Process helper

final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

/// Runs a command and returns its trimmed output. A call that outlives `timeout` is killed
/// so a hung SidecarLauncher can never wedge the watcher.
///
/// Output is collected with a readability handler, not a blocking read, so nothing is left
/// behind when the pipe never reaches EOF (a killed child whose own child still holds it).
func run(_ path: String, _ args: [String], timeout: TimeInterval = 30) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
    let reader = pipe.fileHandleForReading
    let exited = DispatchSemaphore(value: 0), eof = DispatchSemaphore(value: 0)
    let data = Box(Data()), lock = NSLock()
    p.terminationHandler = { _ in exited.signal() }
    reader.readabilityHandler = { h in
        let chunk = h.availableData
        if chunk.isEmpty { h.readabilityHandler = nil; eof.signal() }
        else { lock.lock(); data.value.append(chunk); lock.unlock() }
    }
    func finish() { reader.readabilityHandler = nil; try? reader.close() }

    do { try p.run() } catch { finish(); return "spawn error: \(error.localizedDescription)" }

    if exited.wait(timeout: .now() + timeout) == .timedOut {
        p.terminate()
        if exited.wait(timeout: .now() + 2) == .timedOut { kill(p.processIdentifier, SIGKILL) }
        finish()
        return "timeout after \(Int(timeout))s"
    }
    _ = eof.wait(timeout: .now() + 1) // the child has exited; give the last bytes a moment
    finish()
    lock.lock(); defer { lock.unlock() }
    return (String(data: data.value, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// True when a USB device whose product name contains `match` is attached. Takes ~3 ms.
/// SIDECARKEEPER_USB_PROBE replaces the ioreg call with another executable (used by the tests).
func usbAttached(_ match: String) -> Bool {
    let out: String
    if let probe = ProcessInfo.processInfo.environment["SIDECARKEEPER_USB_PROBE"] {
        out = run(probe, [], timeout: 10)
    } else {
        out = run("/usr/sbin/ioreg", ["-r", "-c", "IOUSBHostDevice", "-w0", "-d1"], timeout: 10)
    }
    return out.split(separator: "\n").contains {
        $0.contains("\"USB Product Name\"") && $0.range(of: match, options: .caseInsensitive) != nil
    }
}

// MARK: - Subcommands

var argv = Array(CommandLine.arguments.dropFirst())
let command = (argv.first.map { !$0.hasPrefix("-") } ?? false) ? argv.removeFirst() : "run"

switch command {
case "run": break
case "pause":
    try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
    guard FileManager.default.createFile(atPath: pauseFile, contents: nil) else { die("cannot write \(pauseFile)") }
    print("paused: SidecarKeeper will not reconnect until `sidecar-keeper resume`"); exit(0)
case "resume":
    try? FileManager.default.removeItem(atPath: pauseFile)
    print("resumed: reconnecting on the next tick"); exit(0)
case "status":
    let cfg = parseOptions(argv)
    let agent = run("/bin/launchctl", ["print", "gui/\(getuid())/\(agentLabel)"])
    let state = agent.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("state =") }
    print("agent:  \(state.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "state = ", with: "") } ?? "not loaded")")
    print("paused: \(FileManager.default.fileExists(atPath: pauseFile) ? "yes" : "no")")
    print("usb:    \(usbAttached(cfg.usbMatch) ? "\(cfg.usbMatch) attached by cable" : "no \(cfg.usbMatch) on USB") (only matters with --wired)")
    print("log:    \(cfg.logPath)")
    if let text = try? String(contentsOfFile: cfg.logPath, encoding: .utf8) {
        for line in text.split(separator: "\n").suffix(8) { print("  \(line)") }
    } else { print("  (no log yet)") }
    exit(0)
default:
    die("unknown command: \(command)\n\(usage())")
}

let cfg = parseOptions(argv)

// MARK: - State

var screensAwake = true
var unlocked = true
var lastLine = ""
var backoff: TimeInterval = 15
var nextAllowed = Date()
var cableWasAbsent = false // wired mode: the cable was seen unplugged since the last good connect
let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
let maxLogBytes = 1_000_000

// MARK: - Helpers

func log(_ s: String, always: Bool = false) {
    if !always && s == lastLine { return }
    lastLine = s
    let fm = FileManager.default
    if let size = (try? fm.attributesOfItem(atPath: cfg.logPath))?[.size] as? Int, size > maxLogBytes {
        try? fm.removeItem(atPath: cfg.logPath + ".1")
        try? fm.moveItem(atPath: cfg.logPath, toPath: cfg.logPath + ".1")
    }
    let line = "\(fmt.string(from: Date())) \(s)\n"
    if let h = FileHandle(forWritingAtPath: cfg.logPath) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { fm.createFile(atPath: cfg.logPath, contents: line.data(using: .utf8)) }
}

/// True only on laptops with the lid closed; desktops have no AppleClamshellState and report false.
func lidClosed() -> Bool {
    run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "4"], timeout: 10)
        .contains("\"AppleClamshellState\" = Yes")
}

/// The lock notifications only report changes, so read the current state once at startup.
func sessionLocked() -> Bool {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

/// "Joe's iPad" and "joe’s ipad" should match: iPadOS names use a curly apostrophe nobody types.
func normalized(_ name: String) -> String {
    name.lowercased().replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
}

enum Probe { case found(String), missing, launcherError(String) }

/// Asks the launcher which devices are reachable and picks the configured (or first) one.
func probeDevice() -> Probe {
    let out = run(cfg.launcher, ["devices"], timeout: cfg.timeout)
    if out.hasPrefix("spawn error") || out.hasPrefix("timeout") { return .launcherError(out) }
    let names = out.split(separator: "\n").map(String.init).filter { $0 != "No sidecar capable devices detected" }
    if let wanted = cfg.device {
        return names.first { normalized($0) == normalized(wanted) }.map(Probe.found) ?? .missing
    }
    return names.first.map(Probe.found) ?? .missing
}

// MARK: - Main loop

func tick() {
    // Sample the cable first, even while locked or paused, so an unplug is never missed.
    let cabled = !cfg.wired || usbAttached(cfg.usbMatch)
    if !cabled { cableWasAbsent = true }
    if FileManager.default.fileExists(atPath: pauseFile) { log("paused, idle"); return }
    guard screensAwake else { log("screen off, idle"); return }
    guard unlocked else { log("locked, idle"); return }
    if lidClosed() { log("lid closed, idle"); return }
    guard cabled else { log("wired mode: no \(cfg.usbMatch) on USB, idle"); return }
    guard Date() >= nextAllowed else { return }

    let device: String
    switch probeDevice() {
    case .found(let d): device = d
    case .missing: log("\(cfg.device ?? "device") not reachable, idle"); return
    case .launcherError(let e):
        // Back off here too: a launcher that hangs would otherwise block every single tick.
        backoff = min(max(backoff * 2, 30), 300); nextAllowed = Date().addingTimeInterval(backoff)
        log("cannot run launcher \(cfg.launcher): \(e)"); return
    }

    let connectArgs = ["connect", device] + (cfg.wired ? ["-wired"] : [])
    var out = run(cfg.launcher, connectArgs, timeout: cfg.timeout)
    if cfg.wired && cableWasAbsent && out.contains("AlreadyInUse") {
        // A wired session does not survive an unplug and does not recover on replug: macOS still
        // reports it as in use. Now that the cable is back, end it and start a fresh one.
        log("cable is back, restarting the wired session", always: true)
        _ = run(cfg.launcher, ["disconnect", device], timeout: cfg.timeout)
        out = run(cfg.launcher, connectArgs, timeout: cfg.timeout)
    }
    if out.split(separator: "\n").contains("connected") {
        log("reconnected \(device)\(cfg.wired ? " (wired)" : "")", always: true)
        backoff = 15; nextAllowed = Date(); cableWasAbsent = false
    } else if out.contains("AlreadyInUse") {
        log("ok"); backoff = 15; nextAllowed = Date(); cableWasAbsent = false
    } else {
        // -500/-501 = virtual display busy/failed: display state is in flux, wait longer.
        backoff = out.contains("VirtualDisplay") ? 300 : min(max(backoff * 2, 30), 300)
        nextAllowed = Date().addingTimeInterval(backoff)
        let hint = out.contains("WiFiNotEnabled") ? " [is the iPad unlocked?]" : ""
        log("fail: \(out)\(hint) (retry in \(Int(backoff))s)")
    }
}

func resume(_ why: String) {
    log(why, always: true); backoff = 15; nextAllowed = Date().addingTimeInterval(cfg.settle)
    DispatchQueue.main.asyncAfter(deadline: .now() + cfg.settle + 1) { tick() }
}

let ws = NSWorkspace.shared.notificationCenter
ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in screensAwake = false; log("screens slept", always: true) }
ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,  object: nil, queue: .main) { _ in screensAwake = true;  resume("screens woke") }
ws.addObserver(forName: NSWorkspace.didWakeNotification,         object: nil, queue: .main) { _ in screensAwake = true;  resume("system woke") }
let dnc = DistributedNotificationCenter.default()
dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),   object: nil, queue: .main) { _ in unlocked = false; log("session locked", always: true) }
dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in unlocked = true;  resume("session unlocked") }

unlocked = !sessionLocked()
log("watcher \(version) started (device: \(cfg.device ?? "auto"), \(cfg.wired ? "wired only, " : "")launcher: \(cfg.launcher))", always: true)
Timer.scheduledTimer(withTimeInterval: cfg.interval, repeats: true) { _ in tick() }
tick()
RunLoop.main.run()
