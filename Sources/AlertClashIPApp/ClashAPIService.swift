import Foundation

enum ClashAPIError: LocalizedError {
    case invalidControllerURL
    case invalidResponse
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidControllerURL:
            return "控制器地址无效"
        case .invalidResponse:
            return "Clash API 返回了无效响应"
        case .invalidPayload:
            return "Clash API 返回了无法识别的数据"
        }
    }
}

actor ClashAPIService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRuntimeState(controllerURLString: String, secret: String) async throws -> ClashRuntimeState {
        let baseURL = try normalizedBaseURL(from: controllerURLString)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)

        if let groupState = try await fetchGroupRuntimeState(baseURL: baseURL, secret: trimmedSecret) {
            return groupState
        }

        return try await fetchProxyRuntimeState(baseURL: baseURL, secret: trimmedSecret)
    }

    private func normalizedBaseURL(from controllerURLString: String) throws -> URL {
        guard var baseURL = URL(string: controllerURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ClashAPIError.invalidControllerURL
        }

        if baseURL.scheme == nil {
            guard let normalized = URL(string: "http://\(controllerURLString)") else {
                throw ClashAPIError.invalidControllerURL
            }
            baseURL = normalized
        }

        return baseURL
    }

    private func fetchGroupRuntimeState(baseURL: URL, secret: String) async throws -> ClashRuntimeState? {
        let groupURL = baseURL.appending(path: "group")
        var request = URLRequest(url: groupURL)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClashAPIError.invalidResponse
        }

        // Some Clash variants do not expose /group; treat 404 as a fallback signal.
        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClashAPIError.invalidResponse
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let selections = parseSelections(fromGroupPayload: jsonObject)
        guard !selections.isEmpty else {
            return nil
        }

        return ClashRuntimeState(connectionStatus: .connected, selections: selections)
    }

    private func fetchProxyRuntimeState(baseURL: URL, secret: String) async throws -> ClashRuntimeState {
        let proxiesURL = baseURL.appending(path: "proxies")
        var request = URLRequest(url: proxiesURL)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ClashAPIError.invalidResponse
        }

        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let proxies = object["proxies"] as? [String: Any]
        else {
            throw ClashAPIError.invalidPayload
        }

        let selections = proxies.compactMap { key, value -> ClashGroupSelection? in
            guard
                let proxy = value as? [String: Any],
                let selected = proxy["now"] as? String,
                let type = proxy["type"] as? String,
                isPolicyGroup(type: type),
                !selected.isEmpty
            else {
                return nil
            }
            return ClashGroupSelection(groupName: key, selectedProxy: selected)
        }
        .sorted { $0.groupName < $1.groupName }

        return ClashRuntimeState(connectionStatus: .connected, selections: selections)
    }

    private func parseSelections(fromGroupPayload jsonObject: Any) -> [ClashGroupSelection] {
        if let groups = jsonObject as? [[String: Any]] {
            return groups.compactMap(parseSelection(from:))
        }

        if let object = jsonObject as? [String: Any] {
            if let groups = object["groups"] as? [[String: Any]] {
                return groups.compactMap(parseSelection(from:))
            }

            if let groups = object["data"] as? [[String: Any]] {
                return groups.compactMap(parseSelection(from:))
            }
        }

        return []
    }

    private func parseSelection(from group: [String: Any]) -> ClashGroupSelection? {
        guard
            let name = group["name"] as? String,
            let now = (group["now"] as? String) ?? (group["current"] as? String),
            !name.isEmpty,
            !now.isEmpty
        else {
            return nil
        }

        return ClashGroupSelection(groupName: name, selectedProxy: now)
    }

    private func isPolicyGroup(type: String) -> Bool {
        switch type.lowercased() {
        case "selector", "urltest", "fallback", "loadbalance", "relay":
            return true
        default:
            return false
        }
    }
}
