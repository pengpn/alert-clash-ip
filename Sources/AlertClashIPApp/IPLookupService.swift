import Foundation

enum IPLookupError: LocalizedError, Equatable {
    case invalidResponse
    case invalidPayload
    case allProvidersFailed([String])

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "IP 服务返回了无效响应。"
        case .invalidPayload:
            return "IP 服务返回的内容不是合法的 IP 地址。"
        case .allProvidersFailed(let errors):
            return errors.joined(separator: " | ")
        }
    }
}

actor IPLookupService {
    private let session: URLSession
    private let providers: [URL]

    init(
        session: URLSession = .shared,
        providers: [URL] = [
            URL(string: "https://api.ipify.org")!,
            URL(string: "https://ifconfig.me/ip")!
        ]
    ) {
        self.session = session
        self.providers = providers
    }

    func fetchCurrentIP() async throws -> String {
        var failures: [String] = []

        for provider in providers {
            do {
                return try await fetchCurrentIP(from: provider)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failures.append("\(provider.host ?? provider.absoluteString): \(message)")
            }
        }

        throw IPLookupError.allProvidersFailed(failures)
    }

    private func fetchCurrentIP(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw IPLookupError.invalidResponse
        }

        guard let ipString = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              IPValidation.isValidIPAddress(ipString) else {
            throw IPLookupError.invalidPayload
        }

        return ipString
    }
}
