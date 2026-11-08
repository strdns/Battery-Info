import Foundation

func tr(_ russian: String, _ english: String) -> String {
    let language = ProcessInfo.processInfo.environment["BATTERY_INFO_LANG"]
        ?? Locale.preferredLanguages.first
        ?? "en"
    return language.hasPrefix("ru") ? russian : english
}

enum Format {
    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func decimal(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).grouping(.automatic))
    }

    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return tr("\(hours) ч \(mins) мин", "\(hours)h \(mins)m")
        }
        return tr("\(mins) мин", "\(mins) min")
    }

    static func clock(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func mah(_ value: Int) -> String {
        "\(integer(value)) \(tr("мА·ч", "mAh"))"
    }
}
