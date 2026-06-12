import Foundation

/// Represents a proxy request to be forwarded to an upstream provider.
public struct ProxyRequest: Sendable {
    public var endpoint: ProxyEndpoint
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    public var isStreaming: Bool
    public var appType: String

    public init(
        endpoint: ProxyEndpoint,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data? = nil,
        isStreaming: Bool = false,
        appType: String = "codex"
    ) {
        self.endpoint = endpoint
        self.method = method
        self.headers = headers
        self.body = body
        self.isStreaming = isStreaming
        self.appType = appType
    }

    /// Create from raw request data.
    public static func from(
        path: String,
        method: String,
        headers: [String: String],
        body: Data?
    ) -> ProxyRequest? {
        let endpoint: ProxyEndpoint?

        switch path {
        case "/v1/chat/completions":
            endpoint = .chatCompletions
        case "/v1/responses":
            endpoint = .responses
        case "/v1/responses/compact":
            endpoint = .responsesCompact
        case "/v1/models":
            endpoint = .models
        case "/health":
            endpoint = .health
        default:
            endpoint = nil
        }

        guard let endpoint = endpoint else {
            return nil
        }

        // Detect streaming from body
        var isStreaming = false
        if let body = body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let stream = json["stream"] as? Bool {
            isStreaming = stream
        }

        return ProxyRequest(
            endpoint: endpoint,
            method: method,
            headers: headers,
            body: body,
            isStreaming: isStreaming
        )
    }
}

/// Supported proxy endpoints.
public enum ProxyEndpoint: String, Sendable {
    case chatCompletions = "/v1/chat/completions"
    case responses = "/v1/responses"
    case responsesCompact = "/v1/responses/compact"
    case models = "/v1/models"
    case health = "/health"

    /// Returns the upstream path for this endpoint.
    /// Uses simplified UpstreamProvider for configuration.
    public func upstreamPath(usesChatCompletions: Bool) -> String {
        switch self {
        case .chatCompletions:
            return "/v1/chat/completions"
        case .responses:
            // If provider uses Chat Completions API, forward to chat completions endpoint
            if usesChatCompletions {
                return "/v1/chat/completions"
            }
            return "/v1/responses"
        case .responsesCompact:
            return "/v1/responses/compact"
        case .models:
            return "/v1/models"
        case .health:
            return "/health"
        }
    }
}

/// Proxy response from upstream provider.
public struct ProxyResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data?
    public var isStreaming: Bool

    public init(status: Int, headers: [String: String] = [:], body: Data? = nil, isStreaming: Bool = false) {
        self.status = status
        self.headers = headers
        self.body = body
        self.isStreaming = isStreaming
    }
}
