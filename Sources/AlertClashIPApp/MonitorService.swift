import Combine
import Foundation

@MainActor
final class MonitorService: ObservableObject {
    @Published private(set) var snapshot: MonitorSnapshot
    @Published private(set) var isChecking = false

    private let settings: SettingsStore
    private let ipLookupService: IPLookupService
    private let notificationService: NotificationService
    private var monitorTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingManualCheck = false

    init(
        settings: SettingsStore,
        ipLookupService: IPLookupService,
        notificationService: NotificationService
    ) {
        self.settings = settings
        self.ipLookupService = ipLookupService
        self.notificationService = notificationService
        self.snapshot = settings.loadSnapshot()

        settings.$checkIntervalMinutes
            .dropFirst()
            .sink { [weak self] _ in
                self?.restartMonitoring(immediateCheck: false)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(settings.$targetIP, settings.$escalationIntervalMinutes)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.restartMonitoring(immediateCheck: true)
            }
            .store(in: &cancellables)
    }

    deinit {
        monitorTask?.cancel()
    }

    func start() {
        restartMonitoring(immediateCheck: true)
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func checkNow() async -> Bool {
        if isChecking {
            pendingManualCheck = true
            return false
        }
        await performCheck()
        return true
    }

    private func restartMonitoring(immediateCheck: Bool) {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }

            if immediateCheck {
                await self.performCheck()
            }

            while !Task.isCancelled {
                let interval = UInt64(max(self.settings.checkIntervalMinutes, 1)) * 60 * 1_000_000_000
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                await self.performCheck()
            }
        }
    }

    private func performCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer {
            isChecking = false
            if pendingManualCheck {
                pendingManualCheck = false
                Task { @MainActor [weak self] in
                    await self?.performCheck()
                }
            }
        }

        let now = Date()
        let nextStatus: MonitorStatus

        let targetIP = settings.trimmedTargetIP
        guard !targetIP.isEmpty else {
            nextStatus = .ipLookupFailed(errorSummary: "请先在设置中填写目标 IP。")
            await applyTransition(nextStatus: nextStatus, now: now)
            return
        }

        guard settings.isTargetIPValid else {
            nextStatus = .ipLookupFailed(errorSummary: "当前配置的目标 IP 格式无效。")
            await applyTransition(nextStatus: nextStatus, now: now)
            return
        }

        do {
            let currentIP = try await ipLookupService.fetchCurrentIP()
            if currentIP == targetIP {
                nextStatus = .healthy(currentIP: currentIP)
            } else {
                nextStatus = .ipMismatch(currentIP: currentIP, expectedIP: targetIP)
            }
        } catch {
            let summary = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            nextStatus = .ipLookupFailed(errorSummary: summary)
        }

        await applyTransition(nextStatus: nextStatus, now: now)
    }

    private func applyTransition(nextStatus: MonitorStatus, now: Date) async {
        let transition = MonitorDecisionEngine.evaluate(
            previous: snapshot,
            nextStatus: nextStatus,
            now: now,
            escalationInterval: TimeInterval(max(settings.escalationIntervalMinutes, 1) * 60)
        )

        snapshot = transition.snapshot
        settings.save(snapshot: transition.snapshot)

        if let notificationKind = transition.notificationKind {
            await notificationService.send(kind: notificationKind, status: transition.snapshot.status)
        }
    }
}
