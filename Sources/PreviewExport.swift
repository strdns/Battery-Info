import AppKit
import SwiftUI

@MainActor
enum PreviewExport {
    static func write() {
        let folder = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["BATTERY_INFO_PREVIEW_DIR"] ?? "/tmp/battery-ui",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let snapshot = BatteryReader.read()
        let preferences = Preferences()
        let monitor = BatteryMonitor()
        monitor.adopt(snapshot)

        render(appearance: .aqua, name: "panel-light", folder: folder) {
            OverviewView(snapshot: snapshot, copyFlag: CopyFlag(), power: PowerModeController(), onTogglePower: { _ in }) {}
        }
        render(appearance: .darkAqua, name: "panel-dark", folder: folder) {
            OverviewView(snapshot: snapshot, copyFlag: CopyFlag(), power: PowerModeController(), onTogglePower: { _ in }) {}
        }
        render(appearance: .aqua, name: "settings-light", folder: folder) {
            SettingsView(preferences: preferences, monitor: monitor) {}
        }
        render(appearance: .darkAqua, name: "menubar-sample", folder: folder) {
            menuBarSample(snapshot: snapshot)
        }
        var idle = snapshot
        idle.powerState = .onBattery
        render(appearance: .darkAqua, name: "menubar-idle", folder: folder) {
            menuBarSample(snapshot: idle)
        }
        var low = idle
        low.percentage = 15
        render(appearance: .darkAqua, name: "menubar-low", folder: folder) {
            menuBarSample(snapshot: low)
        }
        var saving = snapshot
        saving.lowPowerMode = true
        render(appearance: .darkAqua, name: "menubar-saving", folder: folder) {
            menuBarSample(snapshot: saving)
        }
        fputs("preview ok\n", stderr)
    }

    private static func render<V: View>(appearance: NSAppearance.Name, name: String, folder: URL, @ViewBuilder content: () -> V) {
        let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
        NSApp.appearance = NSAppearance(named: appearance)
        let view = content()
            .environment(\.colorScheme, scheme)
            .frame(width: PanelMetrics.contentWidth)
            .padding(PanelMetrics.padding)
            .background(scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: PanelMetrics.popoverWidth, height: 1600)
        renderer.isOpaque = true
        let url = folder.appendingPathComponent("\(name).png")
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            fputs("\(name) \(Int(image.size.width))x\(Int(image.size.height))\n", stderr)
        } else {
            fputs("\(name) failed\n", stderr)
        }
    }

    private static func menuBarSample(snapshot: BatterySnapshot) -> some View {
        let preferences = Preferences()
        return HStack(spacing: 6) {
            if let icon = MenuBarRenderer.icon(for: snapshot, preferences: preferences) {
                Image(nsImage: icon)
            }
            Text(AttributedString(MenuBarRenderer.title(for: snapshot, preferences: preferences)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }
}
