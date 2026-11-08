import Foundation

/// Hides the system battery menu-bar icon while Battery Info is running and
/// puts our item in that same slot. The system icon comes back when we quit.
enum SystemBatteryMenu {
    private static let domain = "com.apple.controlcenter" as CFString
    private static let batteryKey = "Battery" as CFString
    private static let managingKey = "batteryInfo.managingSystemBattery"
    private static let previousKey = "batteryInfo.systemBatteryMenuValue"
    private static let absent = -1
    private static let hiddenValue = 24

    static let autosaveName = "BatteryInfoMenu"
    static let preferredPositionDefaultsKey = "NSStatusItem Preferred Position BatteryInfoMenu"

    /// Smaller values sit further right. 1 is the rightmost place macOS
    /// gives a menu-bar app, beside Control Center, where the battery icon is.
    static func preferredPosition() -> Double { 1 }

    static func hide() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: managingKey) {
            defaults.set(currentValue() ?? absent, forKey: previousKey)
            defaults.set(true, forKey: managingKey)
        }
        write(hiddenValue)
        reloadControlCenter()
    }

    static func restore() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: managingKey) else { return }
        let previous = defaults.object(forKey: previousKey)
        let previousNumber = previous as? Int ?? (previous as? NSNumber)?.intValue
        if previousNumber == nil || previousNumber == absent || (previous as? String) == "-1" {
            clear()
        } else if let previousNumber {
            write(previousNumber)
        }
        defaults.set(false, forKey: managingKey)
        reloadControlCenter()
    }

    private static func currentValue() -> Int? {
        let value = CFPreferencesCopyValue(
            batteryKey,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return (value as? NSNumber)?.intValue
    }

    private static func write(_ value: Int) {
        CFPreferencesSetValue(
            batteryKey,
            NSNumber(value: value),
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    private static func clear() {
        CFPreferencesSetValue(
            batteryKey,
            nil,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    private static func reloadControlCenter() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["ControlCenter"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
