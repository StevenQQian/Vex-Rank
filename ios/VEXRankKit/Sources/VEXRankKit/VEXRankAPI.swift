import Foundation

public enum VEXRankError: LocalizedError, Sendable {
    case unreachable
    case upstream(status: Int)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Could not reach the ranking service. Check your connection and try again."
        case .upstream(let status):
            return "The ranking service returned an error (\(status)). Please retry."
        case .decoding(let detail):
            return "The ranking service sent something unexpected. \(detail)"
        }
    }
}

/// Client for the VEXRank Worker.
///
/// Deliberately thin: the Worker owns the VCR maths. Reimplementing the rating
/// model here would give two sources of truth for the same number, and that has
/// already gone wrong once on the web, where the live route and the archive
/// scripts used different confidence floors and silently disagreed.
public actor VEXRankAPI {
    public static let defaultBaseURL = URL(string: "https://vexrank-api-test.vexrank-eason.workers.dev")!

    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(baseURL: URL = VEXRankAPI.defaultBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            // The service cold-starts; a request that waits beats one that fails.
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 90
            self.session = URLSession(configuration: configuration)
        }
    }

    public func rankings(season: Int? = nil) async throws -> RankingsResponse {
        var path = "/api/rankings?data=v49"
        if let season { path += "&season=\(season)" }
        return try await get(path)
    }

    public func events(season: Int = 204) async throws -> EventsResponse {
        try await get("/api/events?season=\(season)&classification=v49")
    }

    public func skills(season: Int = 204) async throws -> SkillsResponse {
        try await get("/api/skills?season=\(season)")
    }

    public func eventDetail(id: String) async throws -> EventDetailResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await get("/api/events/\(encoded)?results=v49")
    }

    public func teamProfile(number: String, season: Int? = nil) async throws -> TeamProfileResponse {
        let encoded = number.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? number
        var path = "/api/teams/\(encoded)?profile=v8"
        if let season { path += "&season=\(season)" }
        return try await get(path)
    }

    // MARK: - Transport

    /// Retries 5xx and transport failures with exponential backoff and jitter.
    /// The service returns intermittent 502s on cold start - measured on the web
    /// as 502, 200, 200, 200, 200 across five consecutive calls - so a single
    /// failure should not reach the user.
    private func get<T: Decodable>(_ path: String, attempts: Int = 3) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw VEXRankError.unreachable
        }

        var lastError: VEXRankError = .unreachable
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0

                if (200..<300).contains(status) {
                    do {
                        return try decoder.decode(T.self, from: data)
                    } catch {
                        // Decoding failures are deterministic: retrying cannot help.
                        throw VEXRankError.decoding(String(describing: error))
                    }
                }
                // 4xx will not fix itself either.
                guard status >= 500 else { throw VEXRankError.upstream(status: status) }
                lastError = .upstream(status: status)
            } catch let error as VEXRankError {
                throw error
            } catch {
                lastError = .unreachable
            }

            if attempt < attempts - 1 {
                let backoff = 0.25 * pow(2, Double(attempt)) + Double.random(in: 0...0.12)
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
        throw lastError
    }
}
