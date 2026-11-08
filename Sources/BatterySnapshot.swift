import Foundation

enum PowerState: Equatable {
    case missing
    case onBattery
    case charging
    case charged
    case pluggedIn

    var title: String {
        switch self {
        case .missing: return tr("Нет батареи", "No battery")
        case .onBattery: return tr("От батареи", "On battery")
        case .charging: return tr("Заряжается", "Charging")
        case .charged: return tr("Заряжена", "Charged")
        case .pluggedIn: return tr("Зарядка приостановлена", "Charging paused")
        }
    }

    var timeCaption: String? {
        switch self {
        case .onBattery: return tr("Осталось", "Remaining")
        case .charging: return tr("До полной", "Until full")
        default: return nil
        }
    }
}

enum BatteryCondition: Equatable {
    case excellent
    case normal
    case fair
    case service
    case unknown

    var title: String {
        switch self {
        case .excellent: return tr("Отличное", "Excellent")
        case .normal: return tr("Нормальное", "Normal")
        case .fair: return tr("Пониженное", "Fair")
        case .service: return tr("Нужно обслуживание", "Service recommended")
        case .unknown: return tr("Неопределено", "Unknown")
        }
    }
}

struct BatterySnapshot: Equatable {
    var isPresent: Bool
    var percentage: Int
    var powerState: PowerState
    var lowPowerMode: Bool
    var minutesRemaining: Int?
    var cycleCount: Int?
    var healthPercent: Int?
    var condition: BatteryCondition
    var temperatureC: Double?
    var powerWatts: Double?
    var voltageVolts: Double?
    var amperageAmps: Double?
    var remainingMah: Int?
    var maximumMah: Int?
    var designMah: Int?
    var serialNumber: String?
    var deviceName: String?
    var adapterName: String?
    var adapterWatts: Int?

    var isCharging: Bool { powerState == .charging }
    var isChargePaused: Bool { powerState == .pluggedIn }

    static let empty = BatterySnapshot(
        isPresent: false,
        percentage: 0,
        powerState: .missing,
        lowPowerMode: false,
        minutesRemaining: nil,
        cycleCount: nil,
        healthPercent: nil,
        condition: .unknown,
        temperatureC: nil,
        powerWatts: nil,
        voltageVolts: nil,
        amperageAmps: nil,
        remainingMah: nil,
        maximumMah: nil,
        designMah: nil,
        serialNumber: nil,
        deviceName: nil,
        adapterName: nil,
        adapterWatts: nil
    )

    var summaryLine: String {
        let cycles = cycleCount.map(String.init) ?? "-"
        let health = healthPercent.map(String.init) ?? "-"
        let temp = temperatureC.map { String(format: "%.1f", $0) } ?? "-"
        let power = powerWatts.map { String(format: "%.2f", $0) } ?? "-"
        let remaining = remainingMah.map(String.init) ?? "-"
        let maximum = maximumMah.map(String.init) ?? "-"
        let design = designMah.map(String.init) ?? "-"
        return "percent=\(percentage) state=\(powerState) cycles=\(cycles) health=\(health) temp=\(temp) power=\(power) mah=\(remaining)/\(maximum)/\(design) present=\(isPresent)"
    }
}
