import AppKit

enum MenuBarRenderer {
    static func icon(for snapshot: BatterySnapshot, preferences: Preferences, tint: NSColor = .labelColor) -> NSImage? {
        guard preferences.isEnabled(.icon), snapshot.isPresent else { return nil }
        let showsBolt = snapshot.isCharging || snapshot.isChargePaused
        let showsPercent = preferences.isEnabled(.percentage) && !showsBolt
        return trayBattery(
            percent: snapshot.percentage,
            charging: showsBolt,
            showsPercent: showsPercent,
            lowPower: snapshot.lowPowerMode,
            tint: tint
        )
    }

    static func title(for snapshot: BatterySnapshot, preferences: Preferences) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let color = titleColor(for: snapshot)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        var parts: [NSAttributedString] = []

        for metric in preferences.order where preferences.isEnabled(metric) && metric != .icon {
            if metric == .percentage, percentDrawnInside(snapshot, preferences: preferences) { continue }
            guard let part = token(metric, snapshot: snapshot, preferences: preferences, attributes: attributes) else { continue }
            parts.append(part)
        }

        if parts.isEmpty && !preferences.isEnabled(.icon) {
            parts.append(NSAttributedString(string: "\(snapshot.percentage)%", attributes: attributes))
        }

        for (index, part) in parts.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  ", attributes: attributes))
            }
            result.append(part)
        }
        return result
    }

    static func previewTokens(for snapshot: BatterySnapshot, preferences: Preferences) -> [(symbol: String?, text: String)] {
        guard snapshot.isPresent else { return [] }
        var tokens: [(symbol: String?, text: String)] = []
        for metric in preferences.order where preferences.isEnabled(metric) && metric != .icon {
            switch metric {
            case .icon:
                break
            case .percentage:
                if percentDrawnInside(snapshot, preferences: preferences) { break }
                let bolt = (snapshot.isCharging || snapshot.isChargePaused) && !preferences.isEnabled(.icon) ? "bolt.fill" : nil
                tokens.append((bolt, "\(snapshot.percentage)%"))
            case .time:
                if let minutes = snapshot.minutesRemaining, snapshot.powerState.timeCaption != nil {
                    tokens.append(("clock", Format.clock(minutes: minutes)))
                }
            case .cycles:
                if let cycles = snapshot.cycleCount {
                    tokens.append(("arrow.triangle.2.circlepath", Format.integer(cycles)))
                }
            case .health:
                if let health = snapshot.healthPercent {
                    tokens.append(("heart", "\(health)%"))
                }
            case .temperature:
                if let temperature = snapshot.temperatureC {
                    tokens.append(("thermometer.medium", "\(Format.decimal(temperature, fractionDigits: 1))°"))
                }
            case .power:
                if let watts = snapshot.powerWatts {
                    tokens.append(("bolt", "\(Format.decimal(abs(watts), fractionDigits: 1))\(tr("Вт", "W"))"))
                }
            case .condition:
                tokens.append((nil, shortCondition(snapshot.condition)))
            case .voltage:
                if let volts = snapshot.voltageVolts {
                    tokens.append((nil, "\(Format.decimal(volts, fractionDigits: 1))\(tr("В", "V"))"))
                }
            case .current:
                if let amps = snapshot.amperageAmps {
                    tokens.append((nil, "\(Format.decimal(amps, fractionDigits: 1))\(tr("А", "A"))"))
                }
            }
        }
        if tokens.isEmpty, !preferences.isEnabled(.icon) {
            tokens.append((nil, "\(snapshot.percentage)%"))
        }
        return tokens
    }

    static func tooltip(for snapshot: BatterySnapshot) -> String {
        guard snapshot.isPresent else { return "Battery Info" }
        var pieces = ["Battery Info", "\(snapshot.percentage)%", snapshot.powerState.title]
        if let cycles = snapshot.cycleCount {
            pieces.append(tr("\(cycles) циклов", "\(cycles) cycles"))
        }
        if let health = snapshot.healthPercent {
            pieces.append(tr("ёмкость \(health)%", "\(health)% capacity"))
        }
        return pieces.joined(separator: " · ")
    }

    static func accessibilityValue(for snapshot: BatterySnapshot) -> String {
        guard snapshot.isPresent else { return tr("Батарея не найдена", "No battery") }
        return "\(snapshot.percentage)% \(snapshot.powerState.title)"
    }

    private static func percentDrawnInside(_ snapshot: BatterySnapshot, preferences: Preferences) -> Bool {
        preferences.isEnabled(.icon) && preferences.isEnabled(.percentage) && snapshot.isPresent && !snapshot.isCharging && !snapshot.isChargePaused
    }

    /// The battery keeps one size. Percent is drawn inside when idle; a blue bolt is drawn on top while charging.
    private static func trayBattery(percent: Int, charging: Bool, showsPercent: Bool, lowPower: Bool, tint: NSColor) -> NSImage {
        let height: CGFloat = 18
        let bodyWidth: CGFloat = 42
        let width = bodyWidth + 5 + (lowPower ? 15 : 0)
        let low = percent <= 20
        let charge = low
            ? NSColor(srgbRed: 0.91, green: 0.27, blue: 0.24, alpha: 1)
            : (tint.usingColorSpace(.sRGB) ?? NSColor.white)
        let onFill: NSColor = isLight(charge) ? .black : .white
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let body = NSRect(x: 0.8, y: 1.6, width: bodyWidth, height: height - 3.2)
            charge.setStroke()
            let stroke = NSBezierPath(roundedRect: body, xRadius: 3.2, yRadius: 3.2)
            stroke.lineWidth = 1.45
            stroke.stroke()

            let inner = body.insetBy(dx: 2.1, dy: 2.1)
            let fillWidth = inner.width * CGFloat(min(100, max(0, percent))) / 100
            if fillWidth > 0.4 {
                charge.setFill()
                let fill = NSRect(x: inner.minX, y: inner.minY, width: max(fillWidth, 1.5), height: inner.height)
                NSBezierPath(roundedRect: fill, xRadius: 1.4, yRadius: 1.4).fill()
            }

            charge.setFill()
            let nub = NSRect(x: body.maxX + 1.15, y: height / 2 - 2.7, width: 2.2, height: 5.4)
            NSBezierPath(roundedRect: nub, xRadius: 0.8, yRadius: 0.8).fill()

            if showsPercent {
                drawPercent(percent, body: body, inner: inner, fillWidth: fillWidth, onFill: onFill, onEmpty: charge)
            }
            if charging {
                drawBolt(in: body)
            }
            if lowPower {
                drawLeaf(in: NSRect(x: body.maxX + 5.4, y: 2, width: 12, height: height - 4))
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func isLight(_ color: NSColor) -> Bool {
        guard let color = color.usingColorSpace(.sRGB) else { return true }
        let brightness = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
        return brightness > 0.6
    }

    private static func drawPercent(_ percent: Int, body: NSRect, inner: NSRect, fillWidth: CGFloat, onFill: NSColor, onEmpty: NSColor) {
        let label = "\(percent)%" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: percent >= 100 ? 7.5 : 8.5, weight: .bold)
        let white: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: onFill]
        let colored: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: onEmpty]
        let size = label.size(withAttributes: white)
        let rect = NSRect(
            x: body.midX - size.width / 2,
            y: body.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let splitX = inner.minX + fillWidth
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: -4, width: max(0, splitX), height: body.height + 12)).addClip()
        label.draw(in: rect, withAttributes: white)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: splitX, y: -4, width: max(0, body.maxX + 8 - splitX), height: body.height + 12)).addClip()
        label.draw(in: rect, withAttributes: colored)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawBolt(in body: NSRect) {
        let blue = NSColor(srgbRed: 0.12, green: 0.46, blue: 0.98, alpha: 1)
        guard let symbol = tintedSymbol("bolt.fill", pointSize: 11, color: blue) else { return }
        symbol.draw(in: NSRect(x: body.midX - 5.5, y: body.midY - 6.5, width: 11, height: 13))
    }

    private static func drawLeaf(in rect: NSRect) {
        let green = NSColor(srgbRed: 0.16, green: 0.70, blue: 0.36, alpha: 1)
        guard let symbol = tintedSymbol("leaf.fill", pointSize: 11, color: green) else { return }
        symbol.draw(in: rect)
    }

    private static func tintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        symbol.isTemplate = true
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(rect: rect).fill()
            symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func titleColor(for snapshot: BatterySnapshot) -> NSColor {
        if snapshot.isPresent, snapshot.percentage <= 20 {
            return .systemRed
        }
        return .labelColor
    }

    private static func token(
        _ metric: TrayMetric,
        snapshot: BatterySnapshot,
        preferences: Preferences,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString? {
        guard snapshot.isPresent else { return nil }
        switch metric {
        case .icon:
            return nil
        case .percentage:
            let text = NSMutableAttributedString()
            if (snapshot.isCharging || snapshot.isChargePaused), !preferences.isEnabled(.icon), let bolt = symbolAttachment("bolt.fill") {
                text.append(NSAttributedString(attachment: bolt))
                text.append(NSAttributedString(string: "\u{2009}", attributes: attributes))
            }
            text.append(NSAttributedString(string: "\(snapshot.percentage)%", attributes: attributes))
            return text
        case .time:
            guard let minutes = snapshot.minutesRemaining, snapshot.powerState.timeCaption != nil else { return nil }
            return labeled("clock", Format.clock(minutes: minutes), attributes: attributes)
        case .cycles:
            guard let cycles = snapshot.cycleCount else { return nil }
            return labeled("arrow.triangle.2.circlepath", Format.integer(cycles), attributes: attributes)
        case .health:
            guard let health = snapshot.healthPercent else { return nil }
            return labeled("heart", "\(health)%", attributes: attributes)
        case .temperature:
            guard let temperature = snapshot.temperatureC else { return nil }
            return labeled("thermometer.medium", "\(Format.decimal(temperature, fractionDigits: 1))°", attributes: attributes)
        case .power:
            guard let watts = snapshot.powerWatts else { return nil }
            let value = Format.decimal(abs(watts), fractionDigits: 1)
            return labeled("bolt", "\(value)\(tr("Вт", "W"))", attributes: attributes)
        case .condition:
            return NSAttributedString(string: shortCondition(snapshot.condition), attributes: attributes)
        case .voltage:
            guard let volts = snapshot.voltageVolts else { return nil }
            return NSAttributedString(
                string: "\(Format.decimal(volts, fractionDigits: 1))\(tr("В", "V"))",
                attributes: attributes
            )
        case .current:
            guard let amps = snapshot.amperageAmps else { return nil }
            return NSAttributedString(
                string: "\(Format.decimal(amps, fractionDigits: 1))\(tr("А", "A"))",
                attributes: attributes
            )
        }
    }

    private static func shortCondition(_ condition: BatteryCondition) -> String {
        switch condition {
        case .excellent, .normal: return "OK"
        case .fair: return tr("Ср.", "Fair")
        case .service: return tr("Сервис", "Service")
        case .unknown: return tr("Неопределено", "Unknown")
        }
    }

    private static func labeled(_ symbol: String, _ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let attachment = symbolAttachment(symbol) {
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "\u{2009}", attributes: attributes))
        }
        result.append(NSAttributedString(string: text, attributes: attributes))
        return result
    }

    private static func symbolAttachment(_ name: String) -> NSTextAttachment? {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        image.isTemplate = true
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -1.5, width: image.size.width, height: image.size.height)
        return attachment
    }
}
