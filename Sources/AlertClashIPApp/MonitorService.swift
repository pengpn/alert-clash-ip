import Combine
import Foundation

@MainActor
final class MonitorService: ObservableObject {
    @Published private(set) var snapshot: MonitorSnapshot
    @Published private(set) var isChecking = false
    @Published private(set) var clashRuntimeState: ClashRuntimeState = .disabled
    @Published private(set) var isRefreshingClashState = false

    private let settings: SettingsStore
    private let ipLookupService: IPLookupService
    private let clashAPIService: ClashAPIService
    private let notificationService: NotificationService
    private var monitorTask: Task<Void, Never>?
    private var clashMonitorTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingManualCheck = false

    init(
        settings: SettingsStore,
        ipLookupService: IPLookupService,
        clashAPIService: ClashAPIService,
        notificationService: NotificationService
    ) {
        self.settings = settings
        self.ipLookupService = ipLookupService
        self.clashAPIService = clashAPIService
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

        Publishers.CombineLatest3(
            settings.$clashControllerURL,
            settings.$clashSecret,
            settings.$clashFastDetectionEnabled
        )
        .dropFirst()
        .sink { [weak self] _, _, _ in
            self?.restartClashMonitoring()
        }
        .store(in: &cancellables)
    }

    deinit {
        monitorTask?.cancel()
        clashMonitorTask?.cancel()
    }

    func start() {
        restartMonitoring(immediateCheck: true)
        restartClashMonitoring()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        clashMonitorTask?.cancel()
        clashMonitorTask = nil
    }

    func checkNow() async -> Bool {
        if isChecking {
            pendingManualCheck = true
            return false
        }
        await performCheck()
        return true
    }

    func refreshClashStateNow() async {
        guard settings.clashFastDetectionEnabled else {
            clashRuntimeState = .disabled
            return
        }

        let controllerURL = settings.trimmedClashControllerURL
        guard !controllerURL.isEmpty else {
            clashRuntimeState = .unreachable("未填写控制器地址")
            return
        }

        isRefreshingClashState = true
        defer { isRefreshingClashState = false }

        do {
            clashRuntimeState = try await clashAPIService.fetchRuntimeState(
                controllerURLString: controllerURL,
                secret: settings.trimmedClashSecret
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            clashRuntimeState = ClashRuntimeState(connectionStatus: .unreachable(message), selections: [])
        }
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

    private func restartClashMonitoring() {
        clashMonitorTask?.cancel()

        guard settings.clashFastDetectionEnabled else {
            clashRuntimeState = .disabled
            return
        }

        let controllerURL = settings.trimmedClashControllerURL
        guard !controllerURL.isEmpty else {
            clashRuntimeState = .unreachable("未填写控制器地址")
            return
        }

        clashMonitorTask = Task { [weak self] in
            guard let self else { return }

            var previousSignature = self.clashRuntimeState.signature

            while !Task.isCancelled {
                let nextState: ClashRuntimeState

                do {
                    nextState = try await self.clashAPIService.fetchRuntimeState(
                        controllerURLString: self.settings.trimmedClashControllerURL,
                        secret: self.settings.trimmedClashSecret
                    )
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    nextState = ClashRuntimeState(connectionStatus: .unreachable(message), selections: [])
                }

                let nextSignature = nextState.signature
                let shouldTriggerCheck =
                    !previousSignature.isEmpty &&
                    previousSignature != nextSignature &&
                    !nextSignature.isEmpty

                self.clashRuntimeState = nextState
                previousSignature = nextSignature

                if shouldTriggerCheck {
                    await self.performCheck()
                }

                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
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
