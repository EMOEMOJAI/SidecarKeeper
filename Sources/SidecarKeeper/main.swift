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

let version = "1.3.1"
// The standard installer's LaunchAgent, then the labels `brew services` uses (new and old).
// SIDECARKEEPER_AGENT_LABELS overrides the list, for tests.
let agentLabels = ProcessInfo.processInfo.environment["SIDECARKEEPER_AGENT_LABELS"]?
    .split(separator: ",").map(String.init)
    ?? ["com.sidecarkeeper.agent", "sh.brew.sidecarkeeper", "homebrew.mxcl.sidecarkeeper"]

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
// Settings and the pause flag live here, not in the install directory, so they are the same
// for every install route and survive a reinstall.
let stateDirOverride = ProcessInfo.processInfo.environment["SIDECARKEEPER_STATE_DIR"]
let stateDir = stateDirOverride ?? home + "/Library/Application Support/SidecarKeeper"
let pauseFile = stateDir + "/paused"
let legacyPauseFile = home + "/.sidecarkeeper/paused" // where 1.2 and earlier kept it
let configFile = stateDir + "/config"
enum Pause {
    case off, indefinite, until(Date)
    var active: Bool { if case .off = self { return false }; return true }
}
func pauseState() -> Pause {
    let fm = FileManager.default
    if stateDirOverride == nil && fm.fileExists(atPath: legacyPauseFile) { return .indefinite }
    do {
        let text = try String(contentsOfFile: pauseFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty flags from older versions, or damaged flags, remain paused until explicitly resumed.
        guard let expiry = TimeInterval(text), expiry.isFinite, expiry > 0 else { return .indefinite }
        let date = Date(timeIntervalSince1970: expiry)
        return date > Date() ? .until(date) : .off
    } catch {
        let e = error as NSError
        return e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoSuchFileError ? .off : .indefinite
    }
}
func isPaused() -> Bool { pauseState().active }
let defaultLog = home + "/Library/Logs/sidecar-keeper.log"

struct WatcherStatus: Codable {
    var pid: Int32
    var processStart: String
    var updated: Date
    var freshUntil: Date
    var state: String
    var retryAt: Date?
    var lastReconnect: Date?
    var lastDevice: String?
    var logPath: String
}
let statusFile = stateDir + "/status.json"
func readStatus() -> WatcherStatus? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: statusFile)) else { return nil }
    return try? JSONDecoder().decode(WatcherStatus.self, from: data)
}
func processStart(_ pid: Int32) -> String {
    run("/bin/ps", ["-p", String(pid), "-o", "lstart="], timeout: 2)
}
func timestamp(_ date: Date) -> String {
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    return formatter.string(from: date)
}

func usage() -> String {
    """
    usage: sidecar-keeper [run] [options]   run the watcher (what the LaunchAgent does)
           sidecar-keeper pause [--for 1h]  pause indefinitely, or for a duration (s, m, h, d)
           sidecar-keeper resume            start reconnecting again
           sidecar-keeper status [--log PATH]
           sidecar-keeper config [--init]   show the settings file, or create a commented one
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

    The same options can be set in a settings file, one `name = value` per line, for example
    `device = My iPad` or `wired = true`. Flags given on the command line win over the file.
    File: ~/Library/Application Support/SidecarKeeper/config   (`sidecar-keeper config --init`)
    """
}

func die(_ msg: String) -> Never {
    FileHandle.standardError.write("\(msg)\n".data(using: .utf8)!); exit(2)
}

let configTemplate = """
    # SidecarKeeper settings. Remove the leading # to set a value, then restart the watcher:
    #   brew services restart sidecarkeeper
    #   launchctl kickstart -k gui/$(id -u)/com.sidecarkeeper.agent     (standard installer)
    # Command-line flags, such as the ones install.sh writes into its LaunchAgent, win over
    # this file. If this file has a mistake in it, the watcher says so in its log and stays
    # idle until it is fixed, rather than guess.

    # device = My iPad
    # wired = true
    # usb-match = iPad
    # interval = 15
    # settle = 8
    # timeout = 30

    """

/// Reads the settings file into the equivalent command-line flags. Every value is checked
/// here, so that a mistake is reported with its line number instead of ending the process:
/// a watcher that exits is restarted by launchd every few seconds.
func loadConfig() -> (args: [String], error: String?) {
    let text: String
    do { text = try String(contentsOfFile: configFile, encoding: .utf8) }
    catch {
        let e = error as NSError
        // Only an absent file means defaults; unreadable settings must never select another iPad.
        if e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoSuchFileError { return ([], nil) }
        return ([], "cannot read settings: \(error.localizedDescription)")
    }
    var args: [String] = []
    for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        guard let eq = line.firstIndex(of: "=") else { return ([], "line \(n + 1): expected name = value") }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
        var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q {
            value = String(value.dropFirst().dropLast())
        }
        if value.isEmpty { return ([], "line \(n + 1): \(key) has no value") }
        switch key {
        case "device", "launcher", "log", "usb-match":
            args += ["--" + key, value]
        case "interval", "settle", "timeout":
            let minimum: TimeInterval = key == "settle" ? 0 : 1
            guard let v = TimeInterval(value), v.isFinite, v >= minimum, v <= 86_400 else {
                return ([], "line \(n + 1): \(key) must be a number of seconds between \(Int(minimum)) and 86400")
            }
            args += ["--" + key, value]
        case "wired":
            switch value.lowercased() {
            case "true", "yes", "on", "1": args.append("--wired")
            case "false", "no", "off", "0": break
            default: return ([], "line \(n + 1): wired must be true or false")
            }
        default:
            return ([], "line \(n + 1): unknown setting \"\(key)\"")
        }
    }
    return (args, nil)
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
        guard let n = TimeInterval(value(flag)), n.isFinite, n >= min, n <= 86_400 else {
            die("\(flag) must be a number of seconds between \(Int(min)) and 86400")
        }
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
    var expiry: Date?
    if !argv.isEmpty {
        guard argv.count == 2, argv[0] == "--for", let unit = argv[1].last,
              let multiplier = ["s": 1.0, "m": 60.0, "h": 3600.0, "d": 86400.0][String(unit)],
              let value = Double(argv[1].dropLast()), value.isFinite,
              value * multiplier >= 1, value * multiplier <= 31_536_000 else {
            die("usage: sidecar-keeper pause [--for DURATION] (e.g. 30s, 15m, 1h, 1d; 1 second to 365 days)")
        }
        expiry = Date().addingTimeInterval(value * multiplier)
    }
    do {
        try FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        let text = expiry.map { String($0.timeIntervalSince1970) } ?? ""
        try text.write(toFile: pauseFile, atomically: true, encoding: .utf8)
        if stateDirOverride == nil && FileManager.default.fileExists(atPath: legacyPauseFile) {
            try FileManager.default.removeItem(atPath: legacyPauseFile)
        }
    } catch { die("cannot set pause: \(error.localizedDescription)") }
    if let expiry { print("paused until \(timestamp(expiry)); reconnecting on the next eligible check after expiry") }
    else { print("paused: SidecarKeeper will not reconnect until `sidecar-keeper resume`") }
    exit(0)
case "resume":
    guard argv.isEmpty else { die("usage: sidecar-keeper resume") }
    for path in [pauseFile] + (stateDirOverride == nil ? [legacyPauseFile] : []) {
        do { try FileManager.default.removeItem(atPath: path) }
        catch {
            let e = error as NSError
            if e.domain != NSCocoaErrorDomain || e.code != NSFileNoSuchFileError {
                die("cannot resume: \(error.localizedDescription)")
            }
        }
    }
    print("resumed: reconnecting on the next tick"); exit(0)
case "config":
    if argv == ["--init"] {
        if FileManager.default.fileExists(atPath: configFile) { die("\(configFile) already exists; edit it instead") }
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: configFile, contents: configTemplate.data(using: .utf8)) else {
            die("cannot write \(configFile)")
        }
        print("created \(configFile)\nEdit it, then restart the watcher for the change to apply.")
        exit(0)
    }
    if !argv.isEmpty { die("usage: sidecar-keeper config [--init]") }
    let loaded = loadConfig()
    print("file:   \(configFile)\(FileManager.default.fileExists(atPath: configFile) ? "" : "  (not created; `sidecar-keeper config --init`)")")
    if let e = loaded.error { print("error:  \(e)\n        the watcher stays idle until this is fixed"); exit(1) }
    print("file settings: \(loaded.args.isEmpty ? "defaults" : loaded.args.joined(separator: " "))")
    print("Command-line flags override these settings; restart the watcher after editing.")
    exit(0)
case "status":
    let loaded = loadConfig()
    var cfg = parseOptions((loaded.error == nil ? loaded.args : []) + argv)
    // Report every agent that is loaded: two at once means two watchers competing.
    var found: [String] = []
    for label in agentLabels {
        let out = run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"], timeout: 10)
        guard let line = out.split(separator: "\n").first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("state =")
        }) else { continue }
        let state = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "state = ", with: "")
        found.append("\(state) (\(label))")
    }
    print("agent:  \(found.isEmpty ? "not loaded" : found.joined(separator: ", "))")
    if found.count > 1 { print("        warning: more than one watcher is loaded; stop one of them") }
    switch pauseState() {
    case .off: print("paused: no")
    case .indefinite: print("paused: yes (until resumed)")
    case .until(let date): print("paused: yes (until \(timestamp(date)))")
    }
    if let status = readStatus() {
        // PID plus process start distinguishes a stopped watcher from a reused PID.
        let live = status.pid > 0 && Date() <= status.freshUntil && !status.processStart.isEmpty
            && kill(status.pid, 0) == 0 && processStart(status.pid) == status.processStart
        if live {
            var detail = status.state
            if let retry = status.retryAt {
                let seconds = max(0, ceil(retry.timeIntervalSinceNow))
                detail += seconds > 0 ? " (eligible in \(Int(seconds))s)" : " (eligible; awaiting next check)"
            }
            print("watcher: \(detail) (observed \(timestamp(status.updated)))")
            if !argv.contains("--log") { cfg.logPath = status.logPath }
        } else {
            print("watcher: stale; last observed \(status.state) at \(timestamp(status.updated))")
        }
        if let date = status.lastReconnect {
            print("last reconnect: \(timestamp(date))\(status.lastDevice.map { " (\($0))" } ?? "")")
        } else { print("last reconnect: none recorded") }
    } else { print("watcher: unavailable (no readable status yet)") }
    if let e = loaded.error { print("config: ERROR in \(configFile): \(e)") }
    else if !loaded.args.isEmpty { print("config: \(loaded.args.joined(separator: " "))") }
    print("usb:    \(usbAttached(cfg.usbMatch) ? "\(cfg.usbMatch) attached by cable" : "no \(cfg.usbMatch) on USB") (only matters with --wired)")
    print("log:    \(cfg.logPath)")
    if let text = try? String(contentsOfFile: cfg.logPath, encoding: .utf8) {
        for line in text.split(separator: "\n").suffix(8) { print("  \(line)") }
    } else { print("  (no log yet)") }
    exit(0)
default:
    die("unknown command: \(command)\n\(usage())")
}

// Settings file first, real flags after, so that a flag on the command line wins.
let loadedConfig = loadConfig()
let cfg = parseOptions((loadedConfig.error == nil ? loadedConfig.args : []) + argv)

// MARK: - State

var screensAwake = true
var unlocked = true
var lastLine = ""
var backoff: TimeInterval = 15
var nextAllowed = Date()
var cableWasAbsent = false // wired mode: the cable was seen unplugged since the last good connect
let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
let maxLogBytes = 1_000_000
let previousStatus = readStatus()
var watcherStatus = WatcherStatus(pid: getpid(), processStart: processStart(getpid()), updated: Date(),
    freshUntil: Date(), state: "starting", lastReconnect: previousStatus?.lastReconnect,
    lastDevice: previousStatus?.lastDevice, logPath: cfg.logPath)
var statusWriteFailed = false
var waitingReason = "waiting to retry"

func report(_ state: String, retryAt: Date? = nil) {
    watcherStatus.state = state; watcherStatus.retryAt = retryAt; watcherStatus.updated = Date()
    // Allow for the next poll and bounded USB/lid/launcher probes, including while asleep.
    watcherStatus.freshUntil = Date().addingTimeInterval(max(cfg.interval + 30, cfg.timeout + 10))
    do {
        try FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(watcherStatus).write(to: URL(fileURLWithPath: statusFile), options: .atomic)
        statusWriteFailed = false
    } catch {
        if !statusWriteFailed { log("cannot write live status: \(error.localizedDescription)", always: true) }
        statusWriteFailed = true
    }
}

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
    let names = out.split(separator: "\n").map(String.init).filter {
        $0 != "No sidecar capable devices detected" && !$0.hasPrefix("Error") && !$0.contains("Domain=")
    }
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
    // A broken settings file must never turn into a guess about which iPad to connect.
    if let e = loadedConfig.error { report("settings file error"); log("settings file error (\(e)), idle until fixed: \(configFile)"); return }
    if isPaused() { report("paused"); log("paused, idle"); return }
    guard screensAwake else { report("screen off"); log("screen off, idle"); return }
    // The lock notifications are best-effort and only report changes, so also ask the session.
    guard unlocked && !sessionLocked() else { report("locked"); log("locked, idle"); return }
    if lidClosed() { report("lid closed"); log("lid closed, idle"); return }
    guard cabled else { report("waiting for USB cable"); log("wired mode: no \(cfg.usbMatch) on USB, idle"); return }
    guard Date() >= nextAllowed else { report(waitingReason, retryAt: nextAllowed); return }

    report("checking device availability")
    let device: String
    switch probeDevice() {
    case .found(let d): device = d
    case .missing: report("\(cfg.device ?? "device") not reachable"); log("\(cfg.device ?? "device") not reachable, idle"); return
    case .launcherError(let e):
        // Back off here too: a launcher that hangs would otherwise block every single tick.
        backoff = min(max(backoff * 2, 30), 300); nextAllowed = Date().addingTimeInterval(backoff)
        waitingReason = "waiting to retry launcher"; report(waitingReason, retryAt: nextAllowed)
        log("cannot run launcher \(cfg.launcher): \(e)"); return
    }

    let connectArgs = ["connect", device] + (cfg.wired ? ["-wired"] : [])
    report("connecting \(device)")
    var out = run(cfg.launcher, connectArgs, timeout: cfg.timeout)
    if cfg.wired && cableWasAbsent && out.contains("AlreadyInUse") {
        // A wired session does not survive an unplug and does not recover on replug: macOS still
        // reports it as in use. Now that the cable is back, end it and start a fresh one.
        log("cable is back, restarting the wired session", always: true)
        report("disconnecting stale wired session")
        _ = run(cfg.launcher, ["disconnect", device], timeout: cfg.timeout)
        report("connecting \(device)")
        out = run(cfg.launcher, connectArgs, timeout: cfg.timeout)
    }
    if out.split(separator: "\n").contains("connected") {
        log("reconnected \(device)\(cfg.wired ? " (wired)" : "")", always: true)
        backoff = 15; nextAllowed = Date(); cableWasAbsent = false
        watcherStatus.lastReconnect = Date(); watcherStatus.lastDevice = device
        report("connected to \(device)")
    } else if out.contains("AlreadyInUse") {
        log("ok"); backoff = 15; nextAllowed = Date(); cableWasAbsent = false
        report("connected to \(device)")
    } else {
        // -500/-501 = virtual display busy/failed: display state is in flux, wait longer.
        backoff = out.contains("VirtualDisplay") ? 300 : min(max(backoff * 2, 30), 300)
        nextAllowed = Date().addingTimeInterval(backoff)
        waitingReason = "waiting to retry connection"; report(waitingReason, retryAt: nextAllowed)
        let hint = out.contains("WiFiNotEnabled") ? " [is the iPad unlocked?]" : ""
        log("fail: \(out)\(hint) (retry in \(Int(backoff))s)")
    }
}

func resume(_ why: String) {
    log(why, always: true); backoff = 15; nextAllowed = Date().addingTimeInterval(cfg.settle)
    waitingReason = "settling after wake/unlock"
    DispatchQueue.main.asyncAfter(deadline: .now() + cfg.settle + 1) { tick() }
}

let ws = NSWorkspace.shared.notificationCenter
ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in screensAwake = false; log("screens slept", always: true) }
ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,  object: nil, queue: .main) { _ in screensAwake = true;  resume("screens woke") }
ws.addObserver(forName: NSWorkspace.didWakeNotification,         object: nil, queue: .main) { _ in screensAwake = true;  resume("system woke") }
let dnc = DistributedNotificationCenter.default()
dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),   object: nil, queue: .main) { _ in unlocked = false; log("session locked", always: true) }
dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in unlocked = true;  resume("session unlocked") }

// A watcher that cannot log is undebuggable, so make sure the log is writable before starting.
try? FileManager.default.createDirectory(atPath: (cfg.logPath as NSString).deletingLastPathComponent,
                                         withIntermediateDirectories: true)
if !FileManager.default.isWritableFile(atPath: cfg.logPath),
   !FileManager.default.createFile(atPath: cfg.logPath, contents: nil) {
    FileHandle.standardError.write("cannot write log file \(cfg.logPath)\n".data(using: .utf8)!); exit(1)
}

unlocked = !sessionLocked()
log("watcher \(version) started (device: \(cfg.device ?? "auto"), \(cfg.wired ? "wired only, " : "")launcher: \(cfg.launcher))", always: true)
Timer.scheduledTimer(withTimeInterval: cfg.interval, repeats: true) { _ in tick() }
tick()
RunLoop.main.run()
