import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore
    @State private var draftTargetIP: String
    @State private var saveMessage: String?

    init(model: AppModel) {
        self.model = model
        self._settings = ObservedObject(wrappedValue: model.settings)
        self._draftTargetIP = State(initialValue: model.settings.targetIP)
    }

    var body: some View {
        Form {
            if let checkFeedback = model.checkFeedback {
                CheckFeedbackBanner(message: checkFeedback.message, tone: checkFeedback.tone)
                    .listRowInsets(EdgeInsets())
            }

            Section("监控") {
                HStack(alignment: .center, spacing: 10) {
                    TextField("目标 IP", text: targetIPBinding)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            applyTargetIP()
                        }

                    Button("保存并应用") {
                        applyTargetIP()
                    }
                }

                if !trimmedDraftTargetIP.isEmpty && !IPValidation.isValidIPAddress(trimmedDraftTargetIP) {
                    Text("请输入合法的 IPv4 或 IPv6 地址，应用才能准确比对出口 IP。")
                        .foregroundStyle(.red)
                }

                Text("当前已保存：\(settings.trimmedTargetIP.isEmpty ? "尚未设置" : settings.trimmedTargetIP)")
                    .foregroundStyle(.secondary)

                if let saveMessage {
                    Text(saveMessage)
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $settings.checkIntervalMinutes, in: 1...120) {
                    Text("每 \(settings.checkIntervalMinutes) 分钟检查一次")
                }

                Stepper(value: $settings.escalationIntervalMinutes, in: 1...720) {
                    Text("异常持续时每 \(settings.escalationIntervalMinutes) 分钟重复提醒")
                }
            }

            Section("系统") {
                Toggle("登录时自动启动", isOn: $settings.launchAtLogin)
                Text("通知权限：\(model.notificationStatusDescription)")

                if let error = model.launchAtLoginManager.lastError {
                    Text("无法更新登录启动设置：\(error)")
                        .foregroundStyle(.red)
                }

                if model.notificationService.authorizationStatus == .denied {
                    Text("当前通知已被阻止。如果你希望及时收到提醒，请到系统设置中允许通知。")
                        .foregroundStyle(.red)
                }
            }

            Section("当前状态") {
                LabeledContent("状态", value: model.monitorService.snapshot.status.shortLabel)
                Text(model.monitorService.snapshot.status.subheadline)
                    .foregroundStyle(.secondary)

                if let lastCheckedAt = model.monitorService.snapshot.lastCheckedAt {
                    LabeledContent("上次检查", value: lastCheckedAt.formatted(date: .abbreviated, time: .standard))
                }

                if let lastNotificationAt = model.monitorService.snapshot.lastNotificationAt {
                    LabeledContent("上次提醒", value: lastNotificationAt.formatted(date: .abbreviated, time: .standard))
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
        .onAppear {
            draftTargetIP = settings.targetIP
        }
        .onChange(of: settings.targetIP) { _, newValue in
            if trimmedDraftTargetIP != newValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                draftTargetIP = newValue
            }
        }
        .background(
            WindowAccessor { window in
                model.registerSettingsWindow(window)
            }
        )
    }

    private var trimmedDraftTargetIP: String {
        draftTargetIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var targetIPBinding: Binding<String> {
        Binding(
            get: { draftTargetIP },
            set: { newValue in
                draftTargetIP = newValue
                saveMessage = nil
            }
        )
    }

    private func applyTargetIP() {
        settings.targetIP = trimmedDraftTargetIP
        draftTargetIP = settings.targetIP
        if trimmedDraftTargetIP.isEmpty {
            saveMessage = "目标 IP 已清空。"
        } else if settings.isTargetIPValid {
            saveMessage = "目标 IP 已保存并立即生效。"
            Task {
                await model.runManualCheck()
            }
        } else {
            saveMessage = "目标 IP 已保存，但格式无效，请检查后重新填写。"
        }
    }
}
