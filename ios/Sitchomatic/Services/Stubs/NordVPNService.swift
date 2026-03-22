import Foundation

@MainActor
final class NordVPNService {
    static let shared = NordVPNService()

    private let baseURL = "https://api.nordvpn.com/v1"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "NordVPN-iOS/6.0",
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
    }

    func fetchRecommendedServers(count: Int, accessKey: String) async throws -> [NordServer] {
        let limit = min(count * 3, 100)
        var components = URLComponents(string: "\(baseURL)/servers/recommendations")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "filters[servers_groups][identifier]", value: "legacy_standard"),
            URLQueryItem(name: "filters[servers_technologies][identifier]", value: "wireguard_udp")
        ]

        guard let url = components.url else {
            throw NordAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if !accessKey.isEmpty {
            let credentials = "token:\(accessKey)"
            if let credData = credentials.data(using: .utf8) {
                let base64 = credData.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NordAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw NordAPIError.unauthorized
        case 429:
            throw NordAPIError.rateLimited
        default:
            throw NordAPIError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let apiServers = try decoder.decode([NordAPIServerResponse].self, from: data)

        let servers = apiServers
            .compactMap { $0.toNordServer() }
            .sorted { $0.load < $1.load }
            .prefix(count)

        return Array(servers)
    }

    func fetchServerByHostname(_ hostname: String) async throws -> NordServer? {
        var components = URLComponents(string: "\(baseURL)/servers")!
        components.queryItems = [
            URLQueryItem(name: "filters[hostname]", value: hostname),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components.url else {
            throw NordAPIError.invalidURL
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NordAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let apiServers = try decoder.decode([NordAPIServerResponse].self, from: data)

        return apiServers.first?.toNordServer()
    }
}

nonisolated enum NordAPIError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(Int)
    case noServersFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid NordVPN API URL"
        case .invalidResponse:
            "Invalid response from NordVPN API"
        case .unauthorized:
            "Invalid Nord access key. Check your credentials."
        case .rateLimited:
            "NordVPN API rate limited. Wait a moment and retry."
        case .httpError(let code):
            "NordVPN API error (HTTP \(code))"
        case .noServersFound:
            "No suitable NordVPN servers found"
        case .decodingFailed(let detail):
            "Failed to decode NordVPN response: \(detail)"
        }
    }
}
