import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    struct CheckFeedback: Equatable {
        let message: String
        let tone: StatusTone
    }

    let settings: SettingsStore
    let notificationService: NotificationService
    let monitorService: MonitorService
    let launchAtLoginManager: LaunchAtLoginManager
    @Published var checkFeedback: CheckFeedback?

    private var cancellables: Set<AnyCancellable> = []
    private weak var settingsWindow: NSWindow?
    private var feedbackDismissTask: Task<Void, Never>?

    init() {
        let settings = SettingsStore()
        let notificationService = NotificationService()
        let launchAtLoginManager = LaunchAtLoginManager()
        let monitorService = MonitorService(
            settings: settings,
            ipLookupService: IPLookupService(),
            notificationService: notificationService
        )

        self.settings = settings
        self.notificationService = notificationService
        self.monitorService = monitorService
        self.launchAtLoginManager = launchAtLoginManager

        settings.$launchAtLogin
            .dropFirst()
            .sink { [weak launchAtLoginManager] enabled in
                launchAtLoginManager?.apply(enabled: enabled)
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            settings.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            notificationService.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            monitorService.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            launchAtLoginManager.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        Task {
            await notificationService.requestAuthorizationIfNeeded()
            monitorService.start()
        }
    }

    func openSettingsWindow(using openSettings: OpenSettingsAction) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
        Task { @MainActor [weak self] in
            self?.focusSettingsWindowIfNeeded(retriesRemaining: 6)
        }
    }

    func registerSettingsWindow(_ window: NSWindow?) {
        guard let window else { return }
        settingsWindow = window
        window.title = "设置"
    }

    func runManualCheck() async {
        let executedImmediately = await monitorService.checkNow()

        if executedImmediately {
            showCheckFeedback(
                message: monitorService.snapshot.status.manualCheckMessage,
                tone: monitorService.snapshot.status.tone
            )
        } else {
            showCheckFeedback(
                message: "当前正在检查，已加入下一次检查队列。",
                tone: .neutral
            )
        }
    }

    var menuBarTitle: String {
        monitorService.snapshot.status.menuBarTitle
    }

    var menuBarSymbol: String {
        monitorService.snapshot.status.symbolName
    }

    var notificationStatusDescription: String {
        switch notificationService.authorizationStatus {
        case .authorized:
            return "已允许"
        case .provisional:
            return "临时允许"
        case .denied:
            return "已拒绝"
        case .notDetermined:
            return "尚未请求"
        case .ephemeral:
            return "临时会话"
        @unknown default:
            return "未知"
        }
    }

    private func focusSettingsWindowIfNeeded(retriesRemaining: Int) {
        if let settingsWindow {
            settingsWindow.level = .normal
            settingsWindow.orderFrontRegardless()
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        guard retriesRemaining > 0 else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.focusSettingsWindowIfNeeded(retriesRemaining: retriesRemaining - 1)
        }
    }

    private func showCheckFeedback(message: String, tone: StatusTone) {
        feedbackDismissTask?.cancel()
        checkFeedback = CheckFeedback(message: message, tone: tone)
        feedbackDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.checkFeedback = nil
        }
    }
}
