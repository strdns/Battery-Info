import Foundation
import IOKit
import IOKit.ps

enum BatteryReader {
    private static let smc = SMCReader()

    static func read() -> BatterySnapshot {
        autoreleasepool {
            let registry = copyRegistry()
            let sources = copyPowerSources()
            return makeSnapshot(registry: registry, sources: sources)
        }
    }

    /// Cheap power-source check used to update the icon as soon as the adapter connects.
    static func powerHint() -> (percentage: Int, state: PowerState)? {
        autoreleasepool {
            let sources = copyPowerSources()
            let registry = copyRegistry()
            let source = sources.first { ($0["Type"] as? String) == "InternalBattery" } ?? sources.first
            guard source != nil || registry["ExternalConnected"] != nil || registry["IsCharging"] != nil else { return nil }
            let percentage = chargePercent(
                sourceCurrent: integer(source?["Current Capacity"]),
                sourceMax: integer(source?["Max Capacity"]),
                registryCurrent: integer(registry["CurrentCapacity"]),
                registryMax: integer(registry["MaxCapacity"])
            )
            return (percentage, powerState(source: source, registry: registry, percentage: percentage))
        }
    }

    private static func powerState(source: [String: Any]?, registry: [String: Any], percentage: Int) -> PowerState {
        let pluggedIn = isPluggedIn(source: source, registry: registry)
        let charging = bool(source?["Is Charging"]) || bool(registry["IsCharging"])
        let fullyCharged = bool(registry["FullyCharged"]) || bool(source?["Is Charged"]) || (pluggedIn && percentage >= 100 && !charging)
        let missing = source == nil && registry["BatteryInstalled"] == nil && registry["CurrentCapacity"] == nil
        return powerState(pluggedIn: pluggedIn, charging: charging, fullyCharged: fullyCharged, missing: missing)
    }

    private static func powerState(pluggedIn: Bool, charging: Bool, fullyCharged: Bool, missing: Bool) -> PowerState {
        if missing { return .missing }
        if charging { return .charging }
        if fullyCharged { return .charged }
        if pluggedIn { return .pluggedIn }
        return .onBattery
    }

    private static func isPluggedIn(source: [String: Any]?, registry: [String: Any]) -> Bool {
        if let state = source?["Power Source State"] as? String {
            return state == "AC Power" || bool(registry["ExternalConnected"])
        }
        return bool(registry["ExternalConnected"])
    }

    private static func copyRegistry() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private static func copyPowerSources() -> [[String: Any]] {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return [] }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return list.compactMap { item in
            IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any]
        }
    }

    private static func makeSnapshot(registry: [String: Any], sources: [[String: Any]]) -> BatterySnapshot {
        let batteryData = registry["BatteryData"] as? [String: Any] ?? [:]
        let telemetry = registry["PowerTelemetryData"] as? [String: Any] ?? [:]
        let adapter = registry["AdapterDetails"] as? [String: Any] ?? [:]
        let source = sources.first { ($0["Type"] as? String) == "InternalBattery" } ?? sources.first

        let topCurrent = integer(registry["CurrentCapacity"])
        let topMax = integer(registry["MaxCapacity"])
        let sourceCurrent = integer(source?["Current Capacity"])
        let sourceMax = integer(source?["Max Capacity"])

        let percentage = chargePercent(
            sourceCurrent: sourceCurrent,
            sourceMax: sourceMax,
            registryCurrent: topCurrent,
            registryMax: topMax
        )

        let designMah = integer(batteryData["DesignCapacity"])
        let nominalMah = integer(batteryData["NominalChargeCapacity"])
        let fullChargeMah = integer(batteryData["FullChargeCapacity"])
        let remainingFromData = integer(batteryData["RemainingCapacity"])

        let legacyMah: Bool = {
            guard let topMax, topMax > 100 else { return false }
            return designMah == nil
        }()

        let remainingMah = remainingFromData ?? (legacyMah ? topCurrent : nil)
        let maximumMah = nominalMah ?? fullChargeMah ?? (legacyMah ? topMax : nil)
        let resolvedDesign = designMah ?? (legacyMah ? topMax : nil)

        let calculatedHealth: Int? = {
            guard let maximumMah, let resolvedDesign, resolvedDesign > 0 else { return nil }
            return min(100, Int((Double(maximumMah) / Double(resolvedDesign) * 100).rounded()))
        }()
        let healthPercent = reportedCapacityPercent() ?? calculatedHealth

        let pluggedIn = isPluggedIn(source: source, registry: registry)
        let charging = bool(source?["Is Charging"]) || bool(registry["IsCharging"])
        let fullyCharged = bool(registry["FullyCharged"]) || bool(source?["Is Charged"]) || (pluggedIn && percentage >= 100 && !charging)

        let state = powerState(pluggedIn: pluggedIn, charging: charging, fullyCharged: fullyCharged, missing: source == nil && registry["BatteryInstalled"] == nil && topCurrent == nil)

        let minutes = minutesRemaining(source: source, registry: registry, state: state)
        let amperageMilli = integer64(registry["InstantAmperage"]) ?? integer64(registry["Amperage"])
        let voltageMilli = integer(registry["Voltage"]) ?? integer(registry["AppleRawBatteryVoltage"])

        let powerWatts: Double? = {
            if let milliwatts = integer64(telemetry["BatteryPower"]) ?? integer64(batteryData["BatteryPower"]) {
                return (Double(milliwatts) / 1000).rounded(to: 2)
            }
            if let amperageMilli, let voltageMilli {
                return (Double(voltageMilli) * Double(amperageMilli) / 1_000_000).rounded(to: 2)
            }
            return nil
        }()

        let present = state != .missing && (bool(source?["Is Present"]) || bool(registry["BatteryInstalled"]) || percentage > 0 || registry["CycleCount"] != nil)

        let serial = (registry["Serial"] as? String) ?? (source?["Hardware Serial Number"] as? String)
        let adapterWatts = integer(adapter["Watts"]).flatMap { $0 > 0 ? $0 : nil }
        let adapterName = (adapter["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAdapter = (adapterName?.isEmpty == false) ? adapterName : nil

        return BatterySnapshot(
            isPresent: present,
            percentage: present ? percentage : 0,
            powerState: present ? state : .missing,
            lowPowerMode: bool(source?["LPM Active"]) || LowPowerMode.readEnabled(),
            minutesRemaining: minutes,
            cycleCount: integer(registry["CycleCount"]),
            healthPercent: healthPercent,
            condition: condition(source: source, health: healthPercent),
            temperatureC: temperature(registry: registry),
            powerWatts: powerWatts,
            voltageVolts: voltageMilli.map { (Double($0) / 1000).rounded(to: 2) },
            amperageAmps: amperageMilli.map { (Double($0) / 1000).rounded(to: 2) },
            remainingMah: remainingMah,
            maximumMah: maximumMah,
            designMah: resolvedDesign,
            serialNumber: serial?.isEmpty == false ? serial : nil,
            deviceName: (registry["DeviceName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            adapterName: cleanedAdapter,
            adapterWatts: adapterWatts
        )
    }

    /// Public power-source values are a percentage on current macOS (`Max Capacity` is 100).
    /// Older systems report milliamp-hours at the top level instead.
    private static func chargePercent(sourceCurrent: Int?, sourceMax: Int?, registryCurrent: Int?, registryMax: Int?) -> Int {
        if let sourceCurrent, let sourceMax, sourceMax > 0 {
            let percent = sourceMax <= 100 ? sourceCurrent : Int((Double(sourceCurrent) / Double(sourceMax) * 100).rounded())
            return min(100, max(0, percent))
        }
        if let registryCurrent, let registryMax, registryMax > 0 {
            let percent = registryMax <= 100 ? registryCurrent : Int((Double(registryCurrent) / Double(registryMax) * 100).rounded())
            return min(100, max(0, percent))
        }
        return 0
    }

    private static func minutesRemaining(source: [String: Any]?, registry: [String: Any], state: PowerState) -> Int? {
        let key = state == .charging ? "Time to Full Charge" : "Time to Empty"
        if let minutes = finiteMinutes(integer(source?[key])) {
            return minutes
        }
        if state == .onBattery, let minutes = finiteMinutes(integer(registry["TimeRemaining"])) {
            return minutes
        }
        if state == .charging, let minutes = finiteMinutes(integer(registry["AvgTimeToFull"])) {
            return minutes
        }
        return nil
    }

    private static func finiteMinutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 65535 else { return nil }
        return value
    }

    private static func condition(source: [String: Any]?, health: Int?) -> BatteryCondition {
        let failure = (source?["BatteryHealthCondition"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !failure.isEmpty {
            return .service
        }
        if let healthName = (source?["Battery Health"] as? String)?.lowercased() {
            switch healthName {
            case "poor": return .service
            case "fair": return .fair
            case "good":
                if let health, health >= 90 { return .excellent }
                return .normal
            default: break
            }
        }
        guard let health else { return .unknown }
        switch health {
        case 90...: return .excellent
        case 80..<90: return .normal
        case 60..<80: return .fair
        default: return .service
        }
    }

    private static func temperature(registry: [String: Any]) -> Double? {
        if let raw = (registry["Temperature"] as? NSNumber)?.doubleValue {
            let celsius: Double
            if raw > 2000 {
                celsius = raw / 10 - 273.15
            } else if raw > 150 {
                celsius = raw / 10
            } else {
                celsius = raw
            }
            if celsius > -10, celsius < 100 {
                return (celsius * 10).rounded() / 10
            }
        }
        return smc.batteryTemperature()
    }

    /// Same figure as System Information → Power → Maximum Capacity.
    private static var reportedCapacity: (percent: Int, fetched: Date)?

    private static func reportedCapacityPercent() -> Int? {
        if let reportedCapacity, Date().timeIntervalSince(reportedCapacity.fetched) < 60 {
            return reportedCapacity.percent
        }
        guard let percent = readReportedCapacity() else { return reportedCapacity?.percent }
        reportedCapacity = (percent, Date())
        return percent
    }

    private static func readReportedCapacity() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["SPPowerDataType"] as? [[String: Any]]
        else { return nil }
        for section in sections {
            guard let health = section["sppower_battery_health_info"] as? [String: Any] else { continue }
            if let percent = leadingPercent(health["sppower_battery_health_maximum_capacity"]) {
                return percent
            }
        }
        return nil
    }

    private static func leadingPercent(_ value: Any?) -> Int? {
        let text: String
        if let value = value as? String {
            text = value
        } else if let value = value as? NSNumber {
            text = value.stringValue
        } else {
            return nil
        }
        let digits = text.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
        guard let percent = Int(digits), (0...100).contains(percent) else { return nil }
        return percent
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func integer64(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        return (value as? NSNumber)?.boolValue ?? false
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
