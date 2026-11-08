import SwiftUI

enum PanelMetrics {
    static let contentWidth: CGFloat = 368
    static let padding: CGFloat = 12
    static var popoverWidth: CGFloat { contentWidth + padding * 2 }
}

struct PanelRoot: View {
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject var preferences: Preferences
    @ObservedObject var copyFlag = CopyFlag()
    @ObservedObject var power: PowerModeController
    var resize: () -> Void

    var body: some View {
        Group {
            if preferences.showsSettings {
                SettingsView(preferences: preferences, monitor: monitor) {
                    preferences.showsSettings = false
                }
            } else {
                OverviewView(
                    snapshot: monitor.snapshot,
                    copyFlag: copyFlag,
                    power: power,
                    onTogglePower: { power.setEnabled($0, monitor: monitor) }
                ) {
                    preferences.showsSettings = true
                }
            }
        }
        .frame(width: PanelMetrics.contentWidth)
        .padding(PanelMetrics.padding)
        .onAppear(perform: resize)
        .onChange(of: preferences.showsSettings) { _, _ in resize() }
        .onChange(of: monitor.snapshot) { _, _ in resize() }
        .onChange(of: power.message) { _, _ in resize() }
        .onChange(of: power.pending) { _, _ in resize() }
    }
}

final class CopyFlag: ObservableObject {
    @Published var copied = false

    func flash() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.copied = false
        }
    }
}

struct OverviewView: View {
    var snapshot: BatterySnapshot
    @ObservedObject var copyFlag: CopyFlag
    @ObservedObject var power: PowerModeController
    var onTogglePower: (Bool) -> Void
    var onCustomize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.isPresent {
                header
                chargeTrack
                lowPowerControl
                statGrid
                details
            } else {
                emptyState
            }
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BatteryGlyph(
                fraction: Double(snapshot.percentage) / 100,
                charging: snapshot.isCharging || snapshot.isChargePaused,
                animating: snapshot.isCharging,
                tint: chargeTint
            )
            .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(snapshot.percentage)%")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Text(snapshot.powerState.title)
                    if powerIsOn {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.44))
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                if let line = timeLine {
                    Text(line)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            healthMark
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var healthMark: some View {
        switch snapshot.condition {
        case .excellent:
            statusSymbol("heart.fill", Color(red: 0.20, green: 0.70, blue: 0.44), snapshot.condition.title)
        case .normal:
            statusSymbol("heart", Color(red: 0.20, green: 0.70, blue: 0.44), snapshot.condition.title)
        case .fair:
            statusSymbol("heart.fill", Color(red: 0.95, green: 0.60, blue: 0.16), snapshot.condition.title)
        case .service:
            statusSymbol("wrench.fill", undefinedRed, snapshot.condition.title)
        case .unknown:
            statusSymbol("circle.fill", undefinedRed, snapshot.condition.title)
        }
    }

    private func statusSymbol(_ name: String, _ color: Color, _ label: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var timeLine: String? {
        guard let caption = snapshot.powerState.timeCaption else { return nil }
        guard let minutes = snapshot.minutesRemaining else {
            return tr("Считаю время…", "Calculating time…")
        }
        return "\(caption) \(Format.duration(minutes: minutes))"
    }

    private var chargeTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(chargeTint)
                    .frame(width: max(8, geo.size.width * CGFloat(snapshot.percentage) / 100))
            }
        }
        .frame(height: 6)
        .animation(.easeInOut(duration: 0.45), value: snapshot.percentage)
        .accessibilityLabel(tr("Заряд", "Charge"))
        .accessibilityValue("\(snapshot.percentage)%")
    }

    private var lowPowerControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if powerIsOn {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.44))
                        .frame(width: 18)
                }
                Text(tr("Энергосбережение", "Low Power Mode"))
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 8)
                PowerSwitch(isOn: powerIsOn, action: onTogglePower)
                    .disabled(!snapshot.isPresent)
                    .opacity(snapshot.isPresent ? 1 : 0.4)
            }
            if let message = power.message {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var powerIsOn: Bool {
        power.pending ?? snapshot.lowPowerMode
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            StatCard(
                    symbol: snapshot.cycleCount == nil ? "circle.fill" : "arrow.triangle.2.circlepath",
                    value: snapshot.cycleCount.map { Format.integer($0) } ?? "—",
                    label: tr("Циклы", "Cycles"),
                    tint: snapshot.cycleCount == nil ? undefinedRed : .primary,
                    state: cycleState,
                    stateColor: cycleTint
                )
                StatCard(
                    symbol: snapshot.healthPercent == nil ? "circle.fill" : capacityGrade.symbol,
                    value: snapshot.healthPercent.map { "\($0)%" } ?? "—",
                    label: tr("Ёмкость", "Capacity"),
                    tint: snapshot.healthPercent == nil ? undefinedRed : capacityGrade.tint,
                    state: snapshot.healthPercent == nil ? undefinedTitle : capacityGrade.title,
                    stateColor: snapshot.healthPercent == nil ? undefinedRed : capacityGrade.tint
                )
                StatCard(
                    symbol: snapshot.temperatureC == nil ? "circle.fill" : "thermometer.medium",
                    value: snapshot.temperatureC.map { "\(Format.decimal($0, fractionDigits: 1))°" } ?? "—",
                    label: tr("Температура", "Temperature"),
                    tint: snapshot.temperatureC == nil ? undefinedRed : .primary,
                    state: temperatureState,
                    stateColor: temperatureTint
                )
                StatCard(
                    symbol: snapshot.powerWatts == nil ? "circle.fill" : ((snapshot.isCharging || snapshot.isChargePaused) ? "bolt.fill" : "bolt"),
                    value: snapshot.powerWatts.map { "\(Format.decimal(abs($0), fractionDigits: 1)) \(tr("Вт", "W"))" } ?? "—",
                    label: tr("Мощность", "Power"),
                    tint: snapshot.powerWatts == nil ? undefinedRed : .primary,
                    state: powerState,
                    stateColor: powerTint
                )
        }
    }

    private var undefinedTitle: String {
        tr("Неопределено", "Unknown")
    }

    private var undefinedRed: Color {
        Color(red: 0.91, green: 0.27, blue: 0.24)
    }

    private var capacityGrade: CapacityGrade {
        CapacityGrade(percent: snapshot.healthPercent)
    }

    private var powerState: String? {
        guard let watts = snapshot.powerWatts else { return undefinedTitle }
        if watts > 0.05 { return tr("заряд", "in") }
        if watts < -0.05 { return tr("разряд", "out") }
        return nil
    }

    private var powerTint: Color {
        guard let watts = snapshot.powerWatts else { return undefinedRed }
        if watts > 0.05 { return Color(red: 0.20, green: 0.70, blue: 0.44) }
        if watts < -0.05 { return Color(red: 0.95, green: 0.60, blue: 0.16) }
        return .primary
    }

    private var temperatureState: String {
        guard let temperature = snapshot.temperatureC else { return undefinedTitle }
        if temperature > 40 { return tr("высокая", "high") }
        return tr("нормальная", "normal")
    }

    private var temperatureTint: Color {
        guard let temperature = snapshot.temperatureC else { return undefinedRed }
        if temperature > 40 { return Color(red: 0.95, green: 0.45, blue: 0.15) }
        return Color(red: 0.20, green: 0.70, blue: 0.44)
    }

    private var details: some View {
        VStack(spacing: 0) {
            DetailRow(title: tr("Состояние", "Condition"), value: snapshot.condition.title, dot: healthTint)
                if let volts = snapshot.voltageVolts {
                    DetailRow(title: tr("Напряжение", "Voltage"), value: "\(Format.decimal(volts, fractionDigits: 2)) \(tr("В", "V"))")
                }
                if let amps = snapshot.amperageAmps {
                    DetailRow(title: tr("Ток", "Current"), value: "\(Format.decimal(amps, fractionDigits: 2)) \(tr("А", "A"))")
                }
                if let remaining = snapshot.remainingMah {
                    let maximum = snapshot.maximumMah.map { " / \(Format.integer($0))" } ?? ""
                    DetailRow(title: tr("Сейчас", "Now"), value: "\(Format.integer(remaining))\(maximum) \(tr("мА·ч", "mAh"))")
                }
                if let design = snapshot.designMah {
                    DetailRow(title: tr("Проектная", "Design"), value: Format.mah(design))
                }
                if let watts = snapshot.adapterWatts {
                    let name = snapshot.adapterName.map { "\($0) · " } ?? ""
                    DetailRow(title: tr("Адаптер", "Adapter"), value: "\(name)\(watts) \(tr("Вт", "W"))")
                }
                if let device = snapshot.deviceName {
                    DetailRow(title: tr("Контроллер", "Controller"), value: device)
                }
                if let serial = snapshot.serialNumber {
                    DetailRow(
                        title: tr("Серийный номер", "Serial number"),
                        value: serial,
                        trailingSymbol: copyFlag.copied ? "checkmark" : "doc.on.doc",
                    trailingAction: copySerial
                )
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "battery.slash")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text(tr("Батарея не найдена", "No battery found"))
                .font(.system(size: 15, weight: .semibold))
            Text(tr(
                "На этом Mac нет встроенного аккумулятора.",
                "This Mac doesn’t have an internal battery."
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack {
            QuietButton(title: tr("Настроить", "Customize"), symbol: "slider.horizontal.3") {
                onCustomize()
            }
            Spacer()
            QuietButton(title: tr("Выйти", "Quit"), symbol: "power") {
                NSApp.terminate(nil)
            }
        }
    }

    private var chargeTint: Color {
        if snapshot.percentage <= 20 {
            return Color(red: 0.91, green: 0.27, blue: 0.24)
        }
        return Color(red: 0.20, green: 0.70, blue: 0.44)
    }

    private var healthTint: Color {
        switch snapshot.condition {
        case .excellent, .normal: return Color(red: 0.20, green: 0.70, blue: 0.44)
        case .fair: return Color(red: 0.95, green: 0.60, blue: 0.16)
        case .service: return Color(red: 0.91, green: 0.27, blue: 0.24)
        case .unknown: return undefinedRed
        }
    }

    private var numberColor: Color {
        if snapshot.percentage <= 20 { return chargeTint }
        return .primary
    }

    private var cycleState: String {
        guard let cycles = snapshot.cycleCount else { return undefinedTitle }
        if cycles < 300 { return tr("мало", "low") }
        if cycles < 700 { return tr("среднее", "moderate") }
        return tr("много", "high")
    }

    private var cycleTint: Color {
        guard let cycles = snapshot.cycleCount else { return undefinedRed }
        if cycles < 300 { return Color(red: 0.20, green: 0.70, blue: 0.44) }
        if cycles < 700 { return Color(red: 0.95, green: 0.60, blue: 0.16) }
        return Color(red: 0.91, green: 0.27, blue: 0.24)
    }

    private func copySerial() {
        guard let serial = snapshot.serialNumber else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serial, forType: .string)
        copyFlag.flash()
    }
}

struct PowerSwitch: View {
    var isOn: Bool
    var action: (Bool) -> Void

    var body: some View {
        Button {
            action(!isOn)
        } label: {
            Capsule()
                .fill(isOn ? Color(red: 0.20, green: 0.70, blue: 0.44) : Color.primary.opacity(0.16))
                .frame(width: 50, height: 30)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 1.2, y: 0.5)
                        .padding(3)
                        .frame(width: 30, height: 30)
                }
                .animation(.easeInOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Энергосбережение", "Low Power Mode"))
        .accessibilityValue(isOn ? tr("включено", "on") : tr("выключено", "off"))
        .accessibilityAddTraits(.isToggle)
    }
}

struct BatteryGlyph: View {
    var fraction: Double
    var charging: Bool
    var animating: Bool
    var tint: Color

    var body: some View {
        Group {
            if animating {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    glyph(phase: phase(context.date))
                }
            } else {
                glyph(phase: nil)
            }
        }
        .accessibilityHidden(true)
    }

    private func phase(_ date: Date) -> CGFloat {
        let period: TimeInterval = 1.7
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return CGFloat(progress)
    }

    private func glyph(phase: CGFloat?) -> some View {
        HStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.72), lineWidth: 1.6)
                GeometryReader { geo in
                    let inset: CGFloat = 3
                    let innerWidth = geo.size.width - inset * 2
                    let innerHeight = geo.size.height - inset * 2
                    let clamped = min(1, max(0, fraction))
                    let width = max(6, innerWidth * CGFloat(clamped))
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(tint)
                        .frame(width: width, height: innerHeight)
                        .overlay {
                            if let phase {
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.55), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 18)
                                .offset(x: -24 + phase * (width + 36))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                        .animation(.easeInOut(duration: 0.55), value: fraction)
                        .position(x: inset + width / 2, y: geo.size.height / 2)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.primary)
                }
            }
            .frame(width: 52, height: 26)
            RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                .fill(Color.primary.opacity(0.72))
                .frame(width: 3, height: 9)
        }
    }
}

struct CapacityGrade {
    var symbol: String
    var title: String
    var tint: Color

    init(percent: Int?) {
        let green = Color(red: 0.20, green: 0.70, blue: 0.44)
        let yellow = Color(red: 0.95, green: 0.60, blue: 0.16)
        let red = Color(red: 0.91, green: 0.27, blue: 0.24)
        guard let percent else {
            symbol = "heart"
            title = tr("Ёмкость", "Capacity")
            tint = .secondary
            return
        }
        switch percent {
        case 99...:
            symbol = "heart.fill"
            title = tr("новая", "new")
            tint = green
        case 95..<99:
            symbol = "heart"
            title = tr("отличная", "excellent")
            tint = green
        case 85..<95:
            symbol = "heart"
            title = tr("хорошая", "good")
            tint = green
        case 80..<85:
            symbol = "heart.fill"
            title = tr("средняя", "fair")
            tint = yellow
        case 70..<80:
            symbol = "heart.slash.fill"
            title = tr("плохая", "poor")
            tint = red
        default:
            symbol = "exclamationmark.triangle.fill"
            title = tr("критическая", "critical")
            tint = red
        }
    }
}

struct StatCard: View {
    var symbol: String
    var value: String
    var label: String
    var tint: Color
    var state: String? = nil
    var stateColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let state, let stateColor {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 7, height: 7)
                        Text(state)
                            .foregroundStyle(stateColor)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 14, alignment: .leading)
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

struct DetailRow: View {
    var title: String
    var value: String
    var dot: Color?
    var trailingSymbol: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 16.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                Text(value)
                    .font(.system(size: 16.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let trailingSymbol, let trailingAction {
                    Button(action: trailingAction) {
                        Image(systemName: trailingSymbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Скопировать", "Copy"))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct QuietButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}
