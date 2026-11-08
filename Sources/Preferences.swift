import Foundation
import Combine

enum TrayMetric: String, Codable, CaseIterable, Identifiable {
    case icon
    case percentage
    case time
    case cycles
    case health
    case temperature
    case power
    case condition
    case voltage
    case current

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: return tr("Иконка", "Icon")
        case .percentage: return tr("Процент заряда", "Charge")
        case .time: return tr("Оставшееся время", "Time remaining")
        case .cycles: return tr("Циклы", "Cycle count")
        case .health: return tr("Максимальная ёмкость", "Maximum capacity")
        case .temperature: return tr("Температура", "Temperature")
        case .power: return tr("Мощность", "Power")
        case .condition: return tr("Состояние", "Condition")
        case .voltage: return tr("Напряжение", "Voltage")
        case .current: return tr("Ток", "Current")
        }
    }

    var symbol: String {
        switch self {
        case .icon: return "battery.100percent"
        case .percentage: return "percent"
        case .time: return "clock"
        case .cycles: return "arrow.triangle.2.circlepath"
        case .health: return "heart"
        case .temperature: return "thermometer.medium"
        case .power: return "bolt"
        case .condition: return "checkmark.seal"
        case .voltage: return "wave.3.right"
        case .current: return "arrow.left.arrow.right"
        }
    }

    static let defaultOrder: [TrayMetric] = allCases
    static let defaultEnabled: [TrayMetric] = [.icon, .percentage]
}

final class Preferences: ObservableObject {
    @Published var order: [TrayMetric] {
        didSet { persist() }
    }
    @Published var enabled: [TrayMetric] {
        didSet { persist() }
    }
    @Published var launchAtLogin: Bool {
        didSet { persistLaunch() }
    }
    @Published var showsSettings = false
    @Published var loginMessage: String?

    var onChange: (() -> Void)?

    private let trayKey = "batteryInfo.tray"
    private let launchKey = "batteryInfo.launchAtLogin"
    private let seenKey = "batteryInfo.didLaunchOnce"
    private var applyingLaunch = false

    init() {
        let stored = UserDefaults.standard.data(forKey: trayKey)
            .flatMap { try? JSONDecoder().decode(StoredTray.self, from: $0) }
        let restoredOrder: [TrayMetric]
        var restoredEnabled: [TrayMetric]
        if let stored {
            restoredOrder = Preferences.merged(stored.order)
            restoredEnabled = stored.enabled.filter { TrayMetric(rawValue: $0.rawValue) != nil }
            if restoredEnabled.isEmpty { restoredEnabled = TrayMetric.defaultEnabled }
        } else {
            restoredOrder = TrayMetric.defaultOrder
            restoredEnabled = TrayMetric.defaultEnabled
        }
        order = restoredOrder
        enabled = restoredEnabled

        let firstLaunch = !UserDefaults.standard.bool(forKey: seenKey)
        if firstLaunch {
            UserDefaults.standard.set(true, forKey: seenKey)
            UserDefaults.standard.set(true, forKey: launchKey)
            launchAtLogin = true
        } else {
            launchAtLogin = UserDefaults.standard.bool(forKey: launchKey)
        }
    }

    func startLoginItem() {
        guard launchAtLogin else { return }
        loginMessage = LoginItem.setEnabled(true)
    }

    func isEnabled(_ metric: TrayMetric) -> Bool {
        enabled.contains(metric)
    }

    func setEnabled(_ metric: TrayMetric, _ isOn: Bool) {
        if isOn {
            guard !enabled.contains(metric) else { return }
            enabled.append(metric)
        } else {
            let remaining = enabled.filter { $0 != metric }
            guard !remaining.isEmpty else { return }
            enabled = remaining
        }
    }

    func canDisable(_ metric: TrayMetric) -> Bool {
        !isEnabled(metric) || enabled.count > 1
    }

    func move(_ metric: TrayMetric, by delta: Int) {
        guard let index = order.firstIndex(of: metric) else { return }
        let target = index + delta
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    func resetTray() {
        order = TrayMetric.defaultOrder
        enabled = TrayMetric.defaultEnabled
    }

    var shouldOpenPanelOnce: Bool {
        let key = "batteryInfo.didShowPanel"
        if UserDefaults.standard.bool(forKey: key) { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }

    private func persist() {
        let payload = StoredTray(order: order, enabled: enabled)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: trayKey)
        }
        onChange?()
    }

    private func persistLaunch() {
        UserDefaults.standard.set(launchAtLogin, forKey: launchKey)
        guard !applyingLaunch else { return }
        applyingLaunch = true
        loginMessage = LoginItem.setEnabled(launchAtLogin)
        applyingLaunch = false
        onChange?()
    }

    private static func merged(_ stored: [TrayMetric]) -> [TrayMetric] {
        var seen = Set<TrayMetric>()
        var result: [TrayMetric] = []
        for metric in stored where seen.insert(metric).inserted {
            result.append(metric)
        }
        for metric in TrayMetric.allCases where seen.insert(metric).inserted {
            result.append(metric)
        }
        return result
    }
}

private struct StoredTray: Codable {
    var order: [TrayMetric]
    var enabled: [TrayMetric]
}
