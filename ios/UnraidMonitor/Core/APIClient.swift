import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case http(Int)
    case decoding(Error)
    case transport(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL."
        case .http(let code): return "HTTP \(code)"
        case .decoding(let err): return "Decoding error: \(err.localizedDescription)"
        case .transport(let err): return err.localizedDescription
        case .cancelled: return "Request cancelled."
        }
    }

    static func from(_ error: Error) -> APIError {
        if let api = error as? APIError { return api }
        if let url = error as? URLError, url.code == .cancelled { return .cancelled }
        if (error as NSError).code == NSURLErrorCancelled { return .cancelled }
        return .transport(error)
    }
}

final class APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: cfg)
        self.decoder = JSONDecoder()
    }

    @MainActor
    func snapshot() async throws -> AggregateSnapshot {
        try await request(path: "/api/snapshot")
    }

    @MainActor
    func ping() async throws -> Ping {
        try await request(path: "/api/ping")
    }

    @MainActor
    func dockerAction(containerId: String, action: String) async throws {
        let encoded = containerId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(.init(charactersIn: ":/"))) ?? containerId
        try await post(path: "/api/actions/docker/\(encoded)/\(action)", body: nil)
    }

    @MainActor
    func parityAction(action: String, correct: Bool? = nil) async throws {
        let body = correct.map { ["correct": $0] }
        try await post(path: "/api/actions/parity/\(action)", body: body)
    }

    @MainActor
    func pingWith(baseURL: String, headers: [String: String]) async throws -> Ping {
        guard let base = URL(string: baseURL), let url = URL(string: "/api/ping", relativeTo: base) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.from(error) }
        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        do { return try decoder.decode(Ping.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    @MainActor
    private func post(path: String, body: [String: Any]?) async throws {
        let settings = Settings.shared
        guard let base = URL(string: settings.baseURL), let url = URL(string: path, relativeTo: base) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in settings.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (_, response): (Data, URLResponse)
        do { (_, response) = try await session.data(for: req) }
        catch { throw APIError.from(error) }
        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
    }

    @MainActor
    private func request<T: Decodable>(path: String) async throws -> T {
        let settings = Settings.shared
        guard let base = URL(string: settings.baseURL), let url = URL(string: path, relativeTo: base) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in settings.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.from(error) }

        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }

        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}

struct Ping: Decodable {
    let pong: Bool
    let ts: String
}
