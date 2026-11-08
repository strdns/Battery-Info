import AppKit
import Darwin
import Security

@_silgen_name("BIOpenPrivilegedShell")
private func BIOpenPrivilegedShell(
    _ authorization: AuthorizationRef,
    _ pipe: UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>
) -> Int32

enum LowPowerMode {
    private static var authorization: AuthorizationRef?
    private static var shell: UnsafeMutablePointer<FILE>?
    private static let toolPath = "/usr/bin/pmset"

    /// The saved setting (`pmset -g live`), which stays in sync when the Mac is on power.
    static func readEnabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["-g", "live"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "lowpowermode" {
                return parts[1] == "1"
            }
        }
        return false
    }

    static func runDirect(_ enabled: Bool) -> Bool {
        run(enabled)
    }

    static func close() {
        if let shell {
            fclose(shell)
        }
        shell = nil
    }

    /// Asks for an administrator password once, then reuses that privileged shell.
    static func authorize(_ enabled: Bool) -> String? {
        if shell != nil, runInShell(enabled) {
            return nil
        }
        close()
        switch openShell() {
        case .cancelled:
            return tr("Отменено", "Canceled")
        case .failed:
            return runWithAppleScript(enabled)
        case .success:
            if runInShell(enabled) { return nil }
            close()
            return runWithAppleScript(enabled)
        }
    }

    private static func run(_ enabled: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["-a", "lowpowermode", enabled ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private enum PrivilegedResult {
        case success
        case cancelled
        case failed
    }

    private static func openShell() -> PrivilegedResult {
        guard let auth = sharedAuthorization() else { return .failed }
        let path = "/bin/sh"
        let granted = kAuthorizationRightExecute.withCString { rightName in
            path.withCString { pathPointer -> OSStatus in
                var item = AuthorizationItem(
                    name: rightName,
                    valueLength: strlen(pathPointer),
                    value: UnsafeMutableRawPointer(mutating: pathPointer),
                    flags: 0
                )
                return withUnsafeMutablePointer(to: &item) { itemPointer in
                    var rights = AuthorizationRights(count: 1, items: itemPointer)
                    let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
                    return AuthorizationCopyRights(auth, &rights, nil, flags, nil)
                }
            }
        }
        if granted == errAuthorizationCanceled { return .cancelled }
        guard granted == errAuthorizationSuccess else { return .failed }

        var opened: UnsafeMutablePointer<FILE>?
        let status = withUnsafeMutablePointer(to: &opened) { BIOpenPrivilegedShell(auth, $0) }
        if status == Int32(errAuthorizationCanceled) { return .cancelled }
        guard status == 0, let opened else { return .failed }
        shell = opened
        return .success
    }

    private static func runInShell(_ enabled: Bool) -> Bool {
        guard let shell else { return false }
        let value = enabled ? "1" : "0"
        let command = "/usr/bin/pmset -a lowpowermode \(value) >/dev/null 2>&1\n"
        let fd = fileno(shell)
        let bytes = Array(command.utf8)
        let written = bytes.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return write(fd, base, raw.count)
        }
        guard written == bytes.count else { return false }
        for _ in 0..<10 {
            if readEnabled() == enabled { return true }
            usleep(150_000)
        }
        return false
    }

    private static func sharedAuthorization() -> AuthorizationRef? {
        if let authorization { return authorization }
        var created: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &created) == errAuthorizationSuccess else { return nil }
        authorization = created
        return created
    }

    private static func runWithAppleScript(_ enabled: Bool) -> String? {
        let value = enabled ? "1" : "0"
        let source = "do shell script \"/usr/bin/pmset -a lowpowermode \(value)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error == nil, readEnabled() == enabled {
            return nil
        }
        if let message = error?[NSAppleScript.errorMessage] as? String, !message.isEmpty {
            return message
        }
        return tr("Не удалось переключить энергосбережение", "Couldn't change Low Power Mode")
    }
}

final class PowerModeController: ObservableObject {
    @Published var pending: Bool?
    @Published var message: String?
    private var busy = false

    func setEnabled(_ enabled: Bool, monitor: BatteryMonitor) {
        guard !busy else { return }
        busy = true
        pending = enabled
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let direct = LowPowerMode.runDirect(enabled)
            DispatchQueue.main.async {
                if !direct {
                    NSApp.activate(ignoringOtherApps: true)
                }
                let failure = direct ? nil : LowPowerMode.authorize(enabled)
                var snapshot = BatteryReader.read()
                if failure == nil, snapshot.lowPowerMode != enabled {
                    usleep(400_000)
                    snapshot = BatteryReader.read()
                }
                monitor.apply(snapshot)
                let applied = snapshot.lowPowerMode == enabled
                self.pending = nil
                if let failure, !applied {
                    self.message = failure
                } else if !applied {
                    self.message = tr("Не удалось переключить энергосбережение", "Couldn't change Low Power Mode")
                } else {
                    self.message = nil
                }
                self.busy = false
            }
        }
    }
}
