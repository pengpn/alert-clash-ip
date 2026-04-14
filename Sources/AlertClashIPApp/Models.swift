import Foundation
import Network

enum StatusTone {
    case neutral
    case success
    case warning
    case error
}

extension StatusTone {
    var color: String {
        switch self {
        case .neutral:
            return "secondary"
        case .success:
            return "green"
        case .warning:
            return "orange"
        case .error:
            return "red"
        }
    }
}

struct ClashGroupSelection: Equatable, Codable {
    let groupName: String
    let selectedProxy: String
}

enum ClashConnectionStatus: Equatable {
    case disabled
    case connected
    case unreachable(String)
}

struct ClashRuntimeState: Equatable {
    let connectionStatus: ClashConnectionStatus
    let selections: [ClashGroupSelection]

    static let disabled = ClashRuntimeState(connectionStatus: .disabled, selections: [])
    static func unreachable(_ reason: String) -> ClashRuntimeState {
        ClashRuntimeState(connectionStatus: .unreachable(reason), selections: [])
    }

    var primarySelection: ClashGroupSelection? {
        return selections.first
    }

    func selection(forGroupName groupName: String) -> ClashGroupSelection? {
        let trimmedGroupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGroupName.isEmpty else {
            return nil
        }

        if let exactMatch = selections.first(where: { $0.groupName == trimmedGroupName }) {
            return exactMatch
        }

        return selections.first {
            $0.groupName.compare(trimmedGroupName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    var primaryProxyName: String? {
        primarySelection?.selectedProxy
    }

    var summaryLine: String {
        switch connectionStatus {
        case .disabled:
            return "Clash API：未启用"
        case .connected:
            if let primarySelection {
                return "当前策略组：\(primarySelection.groupName) -> \(primarySelection.selectedProxy)"
            }
            return "Clash API：已连接"
        case .unreachable(let reason):
            return "Clash API：连接失败（\(reason)）"
        }
    }

    var detailLines: [String] {
        switch connectionStatus {
        case .disabled:
            return []
        case .connected:
            return selections
                .filter { $0 != primarySelection }
                .prefix(4)
                .map { "\($0.groupName) -> \($0.selectedProxy)" }
        case .unreachable(let reason):
            return ["Clash API 错误：\(reason)"]
        }
    }

    var signature: String {
        selections
            .map { "\($0.groupName)=\($0.selectedProxy)" }
            .joined(separator: "|")
    }
}

enum MonitorStatus: Equatable, Codable {
    case idle
    case healthy(currentIP: String)
    case ipMismatch(currentIP: String, expectedIP: String)
    case ipLookupFailed(errorSummary: String)

    enum CodingKeys: String, CodingKey {
        case kind
        case currentIP
        case expectedIP
        case errorSummary
    }

    enum Kind: String, Codable {
        case idle
        case healthy
        case ipMismatch
        case ipLookupFailed
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .idle:
            self = .idle
        case .healthy:
            self = .healthy(currentIP: try container.decode(String.self, forKey: .currentIP))
        case .ipMismatch:
            self = .ipMismatch(
                currentIP: try container.decode(String.self, forKey: .currentIP),
                expectedIP: try container.decode(String.self, forKey: .expectedIP)
            )
        case .ipLookupFailed:
            self = .ipLookupFailed(errorSummary: try container.decode(String.self, forKey: .errorSummary))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .healthy(let currentIP):
            try container.encode(Kind.healthy, forKey: .kind)
            try container.encode(currentIP, forKey: .currentIP)
        case .ipMismatch(let currentIP, let expectedIP):
            try container.encode(Kind.ipMismatch, forKey: .kind)
            try container.encode(currentIP, forKey: .currentIP)
            try container.encode(expectedIP, forKey: .expectedIP)
        case .ipLookupFailed(let errorSummary):
            try container.encode(Kind.ipLookupFailed, forKey: .kind)
            try container.encode(errorSummary, forKey: .errorSummary)
        }
    }

    var isAlerting: Bool {
        switch self {
        case .ipMismatch, .ipLookupFailed:
            return true
        case .idle, .healthy:
            return false
        }
    }

    var headline: String {
        switch self {
        case .idle:
            return "监控待启动"
        case .healthy:
            return "出口 IP 正常"
        case .ipMismatch:
            return "出口 IP 与目标不一致"
        case .ipLookupFailed:
            return "无法确认当前出口 IP"
        }
    }

    var subheadline: String {
        switch self {
        case .idle:
            return "请先设置目标 IP，应用才会开始定时检查。"
        case .healthy(let currentIP):
            return "当前出口 IP 为 \(currentIP)。"
        case .ipMismatch(let currentIP, let expectedIP):
            return "当前 IP \(currentIP) 与目标 IP \(expectedIP) 不一致。"
        case .ipLookupFailed(let errorSummary):
            return "最近一次查询失败：\(errorSummary)"
        }
    }

    var menuBarTitle: String {
        switch self {
        case .idle:
            return "待命"
        case .healthy(let currentIP):
            return currentIP
        case .ipMismatch:
            return "异常"
        case .ipLookupFailed:
            return "失败"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "circle.dashed"
        case .healthy:
            return "checkmark.circle.fill"
        case .ipMismatch:
            return "exclamationmark.triangle.fill"
        case .ipLookupFailed:
            return "wifi.exclamationmark"
        }
    }

    var tone: StatusTone {
        switch self {
        case .idle:
            return .neutral
        case .healthy:
            return .success
        case .ipMismatch:
            return .warning
        case .ipLookupFailed:
            return .error
        }
    }

    var shortLabel: String {
        switch self {
        case .idle:
            return "待命"
        case .healthy:
            return "正常"
        case .ipMismatch:
            return "IP 不匹配"
        case .ipLookupFailed:
            return "查询失败"
        }
    }

    var detailLines: [String] {
        switch self {
        case .idle:
            return ["等待第一次定时检查。"]
        case .healthy(let currentIP):
            return ["当前 IP：\(currentIP)", "目标 IP：与配置一致"]
        case .ipMismatch(let currentIP, let expectedIP):
            return ["当前 IP：\(currentIP)", "目标 IP：\(expectedIP)"]
        case .ipLookupFailed(let errorSummary):
            return ["原因：\(errorSummary)", "应用会在下一个检查周期自动重试。"]
        }
    }

    var manualCheckMessage: String {
        switch self {
        case .idle:
            return "检查未执行，请先设置目标 IP。"
        case .healthy(let currentIP):
            return "检查完成，当前出口 IP 为 \(currentIP)，与目标一致。"
        case .ipMismatch(let currentIP, let expectedIP):
            return "检查完成，当前 IP \(currentIP) 与目标 IP \(expectedIP) 不一致。"
        case .ipLookupFailed(let errorSummary):
            return "检查失败：\(errorSummary)"
        }
    }
}

struct MonitorSnapshot: Codable, Equatable {
    var status: MonitorStatus
    var lastCheckedAt: Date?
    var lastStatusChangeAt: Date?
    var lastNotificationAt: Date?
    var lastHealthyIP: String?

    static let empty = MonitorSnapshot(
        status: .idle,
        lastCheckedAt: nil,
        lastStatusChangeAt: nil,
        lastNotificationAt: nil,
        lastHealthyIP: nil
    )
}

enum NotificationKind: Equatable {
    case alertInitial
    case alertEscalated
    case recovered
}

struct MonitorTransition {
    let snapshot: MonitorSnapshot
    let notificationKind: NotificationKind?
}

enum IPValidation {
    static func isValidIPAddress(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return IPv4Address(candidate) != nil || IPv6Address(candidate) != nil
    }
}

enum MonitorDecisionEngine {
    static func evaluate(
        previous snapshot: MonitorSnapshot,
        nextStatus: MonitorStatus,
        now: Date,
        escalationInterval: TimeInterval
    ) -> MonitorTransition {
        let statusChanged = snapshot.status != nextStatus
        let lastStatusChangeAt = statusChanged ? now : snapshot.lastStatusChangeAt
        let lastHealthyIP: String?

        switch nextStatus {
        case .healthy(let currentIP):
            lastHealthyIP = currentIP
        default:
            lastHealthyIP = snapshot.lastHealthyIP
        }

        var notificationKind: NotificationKind?
        var lastNotificationAt = snapshot.lastNotificationAt

        switch (snapshot.status, nextStatus) {
        case (_, .healthy) where snapshot.status.isAlerting:
            notificationKind = .recovered
            lastNotificationAt = now
        case (_, let status) where status.isAlerting && snapshot.status != status:
            notificationKind = .alertInitial
            lastNotificationAt = now
        case (let oldStatus, let newStatus) where oldStatus == newStatus && newStatus.isAlerting:
            if let previousNotificationAt = snapshot.lastNotificationAt {
                if now.timeIntervalSince(previousNotificationAt) >= escalationInterval {
                    notificationKind = .alertEscalated
                    lastNotificationAt = now
                }
            } else {
                notificationKind = .alertInitial
                lastNotificationAt = now
            }
        default:
            break
        }

        return MonitorTransition(
            snapshot: MonitorSnapshot(
                status: nextStatus,
                lastCheckedAt: now,
                lastStatusChangeAt: lastStatusChangeAt,
                lastNotificationAt: lastNotificationAt,
                lastHealthyIP: lastHealthyIP
            ),
            notificationKind: notificationKind
        )
    }
}
