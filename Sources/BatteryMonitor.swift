import Foundation
import IOKit.ps

final class BatteryMonitor: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot.empty

    var onChange: (() -> Void)?

    private let queue = DispatchQueue(label: "com.strelnikov.batteryinfo.refresh", qos: .utility)
    private let fastQueue = DispatchQueue(label: "com.strelnikov.batteryinfo.power", qos: .userInteractive)
    private var timer: Timer?
    private var fastTimer: Timer?
    private var loopSource: CFRunLoopSource?
    private var refreshToken = 0

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        fastTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.pollPower()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.pollPower()
            monitor.refresh()
        }, context)?.takeRetainedValue() else { return }
        loopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func adopt(_ snapshot: BatterySnapshot) {
        self.snapshot = snapshot
    }

    func apply(_ snapshot: BatterySnapshot) {
        guard snapshot != self.snapshot else { return }
        self.snapshot = snapshot
        onChange?()
    }

    func pollPower() {
        fastQueue.async { [weak self] in
            let hint = BatteryReader.powerHint()
            DispatchQueue.main.async {
                guard let self, let hint else { return }
                let stateChanged = hint.state != self.snapshot.powerState
                let percentChanged = hint.percentage != self.snapshot.percentage
                guard stateChanged || percentChanged else { return }
                var next = self.snapshot
                next.percentage = hint.percentage
                next.powerState = hint.state
                self.snapshot = next
                self.onChange?()
                if stateChanged {
                    self.refresh()
                }
            }
        }
    }

    func refresh() {
        refreshToken += 1
        let token = refreshToken
        queue.async { [weak self] in
            let snapshot = BatteryReader.read()
            DispatchQueue.main.async {
                guard let self, self.refreshToken == token else { return }
                guard snapshot != self.snapshot else { return }
                self.snapshot = snapshot
                self.onChange?()
            }
        }
    }
}
