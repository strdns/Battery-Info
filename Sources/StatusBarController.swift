import AppKit
import SwiftUI

final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor = BatteryMonitor()
    private let preferences = Preferences()
    private let power = PowerModeController()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hosting: NSHostingController<PanelRoot>?
    private var closedAt: Date?
    private var signature = ""
    private let anchor = PopoverAnchor()
    private let appearanceProbe = AppearanceProbe()

    func start() {
        UserDefaults.standard.set(
            SystemBatteryMenu.preferredPosition(),
            forKey: SystemBatteryMenu.preferredPositionDefaultsKey
        )
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = SystemBatteryMenu.autosaveName
        item.isVisible = true
        statusItem = item
        SystemBatteryMenu.hide()

        let content = PanelRoot(monitor: monitor, preferences: preferences, power: power) { [weak self] in
            self?.scheduleResize()
        }
        let hosting = NSHostingController(rootView: content)
        self.hosting = hosting
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: PanelMetrics.popoverWidth, height: 640)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            appearanceProbe.onChange = { [weak self] in
                DispatchQueue.main.async { self?.render() }
            }
            button.addSubview(appearanceProbe)
        }

        monitor.onChange = { [weak self] in self?.render() }
        preferences.onChange = { [weak self] in self?.render() }
        monitor.start()
        preferences.startLoginItem()
        render()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(themeChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openFromLaunch),
            name: Notification.Name("com.strelnikov.batteryinfo.open"),
            object: nil
        )

        if preferences.shouldOpenPanelOnce {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.openPopover()
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        closedAt = Date()
        anchor.hide()
    }

    @objc private func themeChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.render()
        }
    }

    @objc private func openFromLaunch() {
        openPopover()
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        let isRight = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isRight {
            if popover.isShown { popover.performClose(nil) }
            showMenu()
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if let closedAt, Date().timeIntervalSince(closedAt) < 0.2 {
            return
        }
        openPopover()
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            anchor.place(at: rect)
            popover.show(relativeTo: anchor.view.bounds, of: anchor.view, preferredEdge: .minY)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        scheduleResize()
    }

    private func scheduleResize() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let hosting = self.hosting else { return }
            let width = PanelMetrics.popoverWidth
            let fitting = hosting.sizeThatFits(in: NSSize(width: width, height: 2400))
            guard fitting.height > 80 else { return }
            let next = NSSize(width: width, height: ceil(fitting.height))
            if abs(self.popover.contentSize.height - next.height) > 1 || abs(self.popover.contentSize.width - next.width) > 1 {
                self.popover.contentSize = next
            }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        var tint = NSColor.white
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            tint = NSColor.labelColor.usingColorSpace(.sRGB) ?? NSColor.white
        }
        let icon = MenuBarRenderer.icon(for: monitor.snapshot, preferences: preferences, tint: tint)
        let title = MenuBarRenderer.title(for: monitor.snapshot, preferences: preferences)
        let appearance = button.effectiveAppearance.name.rawValue
        let color = tint.usingColorSpace(.sRGB) ?? tint
        let channels = "\(Int((color.redComponent * 255).rounded())),\(Int((color.greenComponent * 255).rounded())),\(Int((color.blueComponent * 255).rounded()))"
        let nextSignature = "\(icon?.size.width ?? 0)|\(title.string)|\(monitor.snapshot.percentage)|\(monitor.snapshot.powerState)|\(monitor.snapshot.lowPowerMode)|\(appearance)|\(channels)"
        button.toolTip = MenuBarRenderer.tooltip(for: monitor.snapshot)
        button.setAccessibilityLabel("Battery Info")
        button.setAccessibilityValue(MenuBarRenderer.accessibilityValue(for: monitor.snapshot))
        guard nextSignature != signature else { return }
        signature = nextSignature
        button.image = icon
        button.imagePosition = .imageLeading
        button.attributedTitle = title
        button.contentTintColor = nil
    }

    private func showMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: tr("Открыть", "Open"), action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        let settings = NSMenuItem(title: tr("Настроить…", "Customize…"), action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settings.target = self
        let quit = NSMenuItem(title: tr("Выйти", "Quit Battery Info"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(open)
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        }
    }

    @objc private func openFromMenu() {
        preferences.showsSettings = false
        openPopover()
    }

    @objc private func openSettingsFromMenu() {
        preferences.showsSettings = true
        openPopover()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private final class PopoverAnchor {
    let window: NSWindow
    let view: NSView

    init() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 22))
        view.autoresizingMask = [.width, .height]
        window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    func place(at screenRect: NSRect) {
        guard screenRect.width > 1, screenRect.height > 1 else { return }
        window.setFrame(screenRect, display: true)
        view.frame = NSRect(origin: .zero, size: screenRect.size)
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }
}

private final class AppearanceProbe: NSView {
    var onChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onChange?()
    }
}

