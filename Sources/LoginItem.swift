import Foundation
import ServiceManagement

enum LoginItem {
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return error.localizedDescription
        }

        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return tr(
                "Разрешите запуск в Системных настройках → Основные → Объекты входа.",
                "Allow it in System Settings → General → Login Items."
            )
        case .notFound:
            return tr(
                "Система не видит приложение. Откройте его из папки «Программы».",
                "macOS can't find the app. Open it from the Applications folder."
            )
        default:
            return nil
        }
    }
}
