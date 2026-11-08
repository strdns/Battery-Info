import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var monitor: BatteryMonitor
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(tr("Назад", "Back"))
                Text(tr("Настройка", "Customize"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            preview

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Строка меню", "Menu bar"))
                    .font(.system(size: 13, weight: .semibold))
                Text(tr(
                    "Отмеченное видно всегда. Остальное открывается по клику на иконку.",
                    "Checked items stay in the menu bar. Everything else appears when you click the icon."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 2) {
                ForEach(Array(preferences.order.enumerated()), id: \.element.id) { index, metric in
                    metricRow(metric, index: index)
                }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )

            HStack {
                Text(tr("Хотя бы один пункт остаётся включённым.", "At least one item stays on."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(tr("Сбросить", "Reset")) {
                    preferences.resetTray()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $preferences.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Открывать при входе", "Open at login"))
                            .font(.system(size: 13, weight: .medium))
                        Text(tr(
                            "Battery Info появится в строке меню после включения Mac.",
                            "Battery Info appears in the menu bar after you sign in."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if let message = preferences.loginMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Battery Info \(appVersion)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Так выглядит строка меню", "Menu bar preview"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            MenuBarPreview(snapshot: monitor.snapshot, preferences: preferences)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

    private func metricRow(_ metric: TrayMetric, index: Int) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { preferences.isEnabled(metric) },
                set: { preferences.setEnabled(metric, $0) }
            )) {
                Label(metric.title, systemImage: metric.symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .labelStyle(.titleAndIcon)
            }
            .toggleStyle(.checkbox)
            .disabled(preferences.isEnabled(metric) && !preferences.canDisable(metric))

            Spacer(minLength: 4)

            Button {
                preferences.move(metric, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 16, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(index == 0)
            .opacity(index == 0 ? 0.25 : 0.8)

            Button {
                preferences.move(metric, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 16, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(index == preferences.order.count - 1)
            .opacity(index == preferences.order.count - 1 ? 0.25 : 0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

struct MenuBarPreview: View {
    var snapshot: BatterySnapshot
    @ObservedObject var preferences: Preferences

    var body: some View {
        HStack(spacing: 8) {
            if let icon = MenuBarRenderer.icon(for: snapshot, preferences: preferences) {
                Image(nsImage: icon)
            }
            ForEach(Array(MenuBarRenderer.previewTokens(for: snapshot, preferences: preferences).enumerated()), id: \.offset) { _, token in
                HStack(spacing: 3) {
                    if let symbol = token.symbol {
                        Image(systemName: symbol)
                    }
                    Text(token.text)
                        .monospacedDigit()
                }
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }
}
