import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    enum Keys {
        static let targetIP = "settings.targetIP"
        static let checkIntervalMinutes = "settings.checkIntervalMinutes"
        static let escalationIntervalMinutes = "settings.escalationIntervalMinutes"
        static let launchAtLogin = "settings.launchAtLogin"
        static let monitorSnapshot = "runtime.monitorSnapshot"
    }

    @Published var targetIP: String {
        didSet { persist() }
    }

    @Published var checkIntervalMinutes: Int {
        didSet { persist() }
    }

    @Published var escalationIntervalMinutes: Int {
        didSet { persist() }
    }

    @Published var launchAtLogin: Bool {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.targetIP = defaults.string(forKey: Keys.targetIP) ?? ""

        let storedCheckInterval = defaults.object(forKey: Keys.checkIntervalMinutes) as? Int
        self.checkIntervalMinutes = max(1, storedCheckInterval ?? 5)

        let storedEscalation = defaults.object(forKey: Keys.escalationIntervalMinutes) as? Int
        self.escalationIntervalMinutes = max(1, storedEscalation ?? 30)

        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }

    var trimmedTargetIP: String {
        targetIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isTargetIPValid: Bool {
        IPValidation.isValidIPAddress(trimmedTargetIP)
    }

    func loadSnapshot() -> MonitorSnapshot {
        guard let data = defaults.data(forKey: Keys.monitorSnapshot) else {
            return .empty
        }

        do {
            return try JSONDecoder().decode(MonitorSnapshot.self, from: data)
        } catch {
            return .empty
        }
    }

    func save(snapshot: MonitorSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Keys.monitorSnapshot)
        }
    }

    private func persist() {
        defaults.set(trimmedTargetIP, forKey: Keys.targetIP)
        defaults.set(max(1, checkIntervalMinutes), forKey: Keys.checkIntervalMinutes)
        defaults.set(max(1, escalationIntervalMinutes), forKey: Keys.escalationIntervalMinutes)
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
    }
}
