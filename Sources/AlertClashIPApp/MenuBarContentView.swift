import AppKit
import SwiftUI

private struct StatusDot: View {
    let tone: StatusTone

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
            }
    }

    private var color: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

struct CheckFeedbackBanner: View {
    let message: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .imageScale(.medium)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral:
            return .primary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            return Color.secondary.opacity(0.12)
        case .success:
            return Color.green.opacity(0.12)
        case .warning:
            return Color.orange.opacity(0.12)
        case .error:
            return Color.red.opacity(0.12)
        }
    }

    private var symbolName: String {
        switch tone {
        case .neutral:
            return "clock.badge.checkmark"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let checkFeedback = model.checkFeedback {
                CheckFeedbackBanner(message: checkFeedback.message, tone: checkFeedback.tone)
            }

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(statusTint.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: model.menuBarSymbol)
                        .imageScale(.large)
                        .foregroundStyle(statusTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        StatusDot(tone: model.monitorService.snapshot.status.tone)
                        Text(model.monitorService.snapshot.status.shortLabel)
                            .font(.headline)
                    }

                    Text(model.monitorService.snapshot.status.subheadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.monitorService.snapshot.status.detailLines, id: \.self) { line in
                    Text(line)
                }

                Divider()

                Text("目标 IP：\(model.settings.trimmedTargetIP.isEmpty ? "尚未设置" : model.settings.trimmedTargetIP)")
                Text("检查频率：每 \(model.settings.checkIntervalMinutes) 分钟一次")
                Text("重复提醒：异常持续时每 \(model.settings.escalationIntervalMinutes) 分钟提醒一次")
                Text("通知权限：\(model.notificationStatusDescription)")

                if let lastCheckedAt = model.monitorService.snapshot.lastCheckedAt {
                    Text("上次检查：\(Self.dateFormatter.string(from: lastCheckedAt))")
                }

                if model.monitorService.isChecking {
                    Text("正在执行检查，请稍候...")
                        .foregroundStyle(statusTint)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack {
                Button(model.monitorService.isChecking ? "检查排队中" : "立即检查") {
                    Task {
                        await model.runManualCheck()
                    }
                }

                Button("设置") {
                    model.openSettingsWindow(using: openSettings)
                }

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private var statusTint: Color {
        switch model.monitorService.snapshot.status.tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
