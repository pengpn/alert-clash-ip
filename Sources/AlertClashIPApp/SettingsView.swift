import SwiftUI

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore
    @State private var draftTargetIP: String
    @State private var draftClashControllerURL: String
    @State private var draftClashSecret: String
    @State private var draftClashMonitoredGroupName: String
    @State private var isClashSecretVisible = false
    @State private var saveMessage: String?

    init(model: AppModel) {
        self.model = model
        self._settings = ObservedObject(wrappedValue: model.settings)
        self._draftTargetIP = State(initialValue: model.settings.targetIP)
        self._draftClashControllerURL = State(initialValue: model.settings.clashControllerURL)
        self._draftClashSecret = State(initialValue: model.settings.clashSecret)
        self._draftClashMonitoredGroupName = State(initialValue: model.settings.clashMonitoredGroupName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let checkFeedback = model.checkFeedback {
                    CheckFeedbackBanner(message: checkFeedback.message, tone: checkFeedback.tone)
                }

                SettingsSectionCard(title: "监控") {
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

                SettingsSectionCard(title: "系统") {
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

                SettingsSectionCard(title: "Clash API") {
                Toggle("启用节点变化快速感知", isOn: $settings.clashFastDetectionEnabled)

                TextField("控制器地址", text: clashControllerBinding)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    if isClashSecretVisible {
                        TextField("Secret", text: clashSecretBinding)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Secret", text: clashSecretBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        isClashSecretVisible.toggle()
                    } label: {
                        Image(systemName: isClashSecretVisible ? "eye.slash" : "eye")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(isClashSecretVisible ? "隐藏 Secret" : "显示 Secret")
                }

                if availableClashGroupNames.isEmpty {
                    TextField("监控策略组名称", text: clashMonitoredGroupBinding)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("监控策略组", selection: clashMonitoredGroupBinding) {
                        ForEach(availableClashGroupNames, id: \.self) { groupName in
                            Text(groupName).tag(groupName)
                        }
                    }
                    .pickerStyle(.menu)

                    if allowsManualGroupEntry {
                        TextField("或手动填写策略组名称", text: clashMonitoredGroupBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Button("保存 Clash API 配置") {
                    applyClashConfiguration()
                }

                Button(model.monitorService.isRefreshingClashState ? "正在刷新策略组..." : "刷新策略组列表") {
                    Task {
                        await model.monitorService.refreshClashStateNow()
                    }
                }
                .disabled(model.monitorService.isRefreshingClashState)

                Text("当前控制器：\(settings.trimmedClashControllerURL.isEmpty ? "尚未设置" : settings.trimmedClashControllerURL)")
                    .foregroundStyle(.secondary)
                Text("当前监控策略组：\(settings.trimmedClashMonitoredGroupName.isEmpty ? "尚未设置" : settings.trimmedClashMonitoredGroupName)")
                    .foregroundStyle(.secondary)
                if !availableClashGroupNames.isEmpty {
                    Text("已从 Clash API 获取到 \(availableClashGroupNames.count) 个策略组，可直接下拉选择。")
                        .foregroundStyle(.secondary)
                    Text("当前可选：\(availableClashGroupNames.joined(separator: "、"))")
                        .foregroundStyle(.secondary)
                } else {
                    Text(emptyGroupHint)
                        .foregroundStyle(.secondary)
                }
                clashStatusSection
                }

                SettingsSectionCard(title: "当前状态") {
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
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 760)
        .onAppear {
            draftTargetIP = settings.targetIP
            draftClashControllerURL = settings.clashControllerURL
            draftClashSecret = settings.clashSecret
            draftClashMonitoredGroupName = settings.clashMonitoredGroupName
            Task {
                await model.monitorService.refreshClashStateNow()
            }
        }
        .onChange(of: settings.targetIP) { _, newValue in
            if trimmedDraftTargetIP != newValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                draftTargetIP = newValue
            }
        }
        .onChange(of: settings.clashControllerURL) { _, newValue in
            if trimmedDraftClashControllerURL != newValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                draftClashControllerURL = newValue
            }
        }
        .onChange(of: settings.clashSecret) { _, newValue in
            if draftClashSecret != newValue {
                draftClashSecret = newValue
            }
        }
        .onChange(of: settings.clashMonitoredGroupName) { _, newValue in
            if trimmedDraftClashMonitoredGroupName != newValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                draftClashMonitoredGroupName = newValue
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

    private var trimmedDraftClashControllerURL: String {
        draftClashControllerURL.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var trimmedDraftClashMonitoredGroupName: String {
        draftClashMonitoredGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var clashControllerBinding: Binding<String> {
        Binding(
            get: { draftClashControllerURL },
            set: { newValue in
                draftClashControllerURL = newValue
                saveMessage = nil
            }
        )
    }

    private var clashSecretBinding: Binding<String> {
        Binding(
            get: { draftClashSecret },
            set: { newValue in
                draftClashSecret = newValue
                saveMessage = nil
            }
        )
    }

    private var clashMonitoredGroupBinding: Binding<String> {
        Binding(
            get: { draftClashMonitoredGroupName },
            set: { newValue in
                draftClashMonitoredGroupName = newValue
                saveMessage = nil
            }
        )
    }

    private var availableClashGroupNames: [String] {
        let names = model.monitorService.clashRuntimeState.selections.map(\.groupName)
        var uniqueNames: [String] = []
        var seenNames = Set<String>()

        for name in names where seenNames.insert(name).inserted {
            uniqueNames.append(name)
        }

        let currentName = trimmedDraftClashMonitoredGroupName
        if !currentName.isEmpty && !seenNames.contains(currentName) {
            uniqueNames.append(currentName)
        }

        return uniqueNames
    }

    private var allowsManualGroupEntry: Bool {
        let currentName = trimmedDraftClashMonitoredGroupName
        return !currentName.isEmpty && !model.monitorService.clashRuntimeState.selections.contains {
            $0.groupName == currentName
        }
    }

    private var emptyGroupHint: String {
        switch model.monitorService.clashRuntimeState.connectionStatus {
        case .disabled:
            return "当前未启用 Clash API 快速感知，所以还没有可选策略组。"
        case .unreachable:
            return "暂时还没从 Clash API 拉到策略组列表。可以先检查控制器地址和 Secret，再点“刷新策略组列表”。"
        case .connected:
            return "Clash API 已连接，但当前返回里还没有可识别的策略组。可以点“刷新策略组列表”再试一次。"
        }
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

    private func applyClashConfiguration() {
        settings.clashControllerURL = trimmedDraftClashControllerURL
        settings.clashSecret = draftClashSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.clashMonitoredGroupName = trimmedDraftClashMonitoredGroupName
        draftClashControllerURL = settings.clashControllerURL
        draftClashSecret = settings.clashSecret
        draftClashMonitoredGroupName = settings.clashMonitoredGroupName
        saveMessage = "Clash API 和监控策略组配置已保存。"
    }

    private var clashStatusColor: Color {
        switch model.monitorService.clashRuntimeState.connectionStatus {
        case .disabled:
            return .secondary
        case .connected:
            return .green
        case .unreachable:
            return .red
        }
    }

    @ViewBuilder
    private var clashStatusSection: some View {
        let monitoredGroupName = settings.trimmedClashMonitoredGroupName
        let runtimeState = model.monitorService.clashRuntimeState

        switch runtimeState.connectionStatus {
        case .disabled:
            Text("Clash API：未启用")
                .foregroundStyle(clashStatusColor)
        case .unreachable(let reason):
            Text("Clash API：连接失败（\(reason)）")
                .foregroundStyle(clashStatusColor)
        case .connected:
            if let matchedSelection = runtimeState.selection(forGroupName: monitoredGroupName) {
                LabeledContent("监控策略组", value: matchedSelection.groupName)
                LabeledContent("当前节点", value: matchedSelection.selectedProxy)
            } else if monitoredGroupName.isEmpty {
                Text("请先填写要监控的策略组名称。")
                    .foregroundStyle(.secondary)
            } else {
                Text("未找到策略组“\(monitoredGroupName)”。请检查名称是否与 Clash 中完全一致。")
                    .foregroundStyle(.orange)
            }
        }
    }
}
