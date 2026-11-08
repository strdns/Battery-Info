import AppKit

@main
enum BatteryInfoMain {
    static let delegate = AppDelegate()

    static func main() {
        if CommandLine.arguments.contains("--print") {
            fputs(BatteryReader.read().summaryLine + "\n", stdout)
            fflush(stdout)
            return
        }
        if CommandLine.arguments.contains("--preview") {
            MainActor.assumeIsolated {
                NSApplication.shared.setActivationPolicy(.prohibited)
                PreviewExport.write()
            }
            return
        }

        let identifier = Bundle.main.bundleIdentifier ?? "com.strelnikov.batteryinfo"
        let alreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if alreadyRunning {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.strelnikov.batteryinfo.open"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        LowPowerMode.close()
        SystemBatteryMenu.restore()
    }

    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Выйти из Battery Info", "Quit Battery Info"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }
}
