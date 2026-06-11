import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import NIOPosix

/// HTTP client for making requests to upstream API providers.
public final class HTTPClient: Sendable {
    private let eventLoopGroup: any EventLoopGroup
    private let configuration: HTTPClientConfiguration

    public init(configuration: HTTPClientConfiguration = .init()) {
        self.eventLoopGroup = MultiThreadedEventLoopGroup.singleton
        self.configuration = configuration
    }

    /// Send a request to an upstream provider.
    public func send(
        url: String,
        method: HTTPRequest.Method,
        headers: [String: String],
        body: Data?
    ) async throws -> (Data, HTTPResponse.Status) {
        guard let url = URL(string: url) else {
            throw HTTPClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            request.httpBody = body
        }

        request.timeoutInterval = configuration.timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        let status = HTTPResponse.Status(integerLiteral: httpResponse.statusCode)
        return (data, status)
    }

    /// Send a streaming request to an upstream provider.
    public func sendStreaming(
        url: String,
        method: HTTPRequest.Method,
        headers: [String: String],
        body: Data?,
        onEvent: @escaping @Sendable (Data) -> Void
    ) async throws -> HTTPResponse.Status {
        guard let url = URL(string: url) else {
            throw HTTPClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            request.httpBody = body
        }

        request.timeoutInterval = configuration.streamingTimeout

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        let status = HTTPResponse.Status(integerLiteral: httpResponse.statusCode)

        // Read streaming data
        for try await byte in asyncBytes {
            onEvent(Data([byte]))
        }

        return status
    }
}

/// HTTP client configuration.
public struct HTTPClientConfiguration: Sendable {
    public var timeout: TimeInterval
    public var streamingTimeout: TimeInterval
    public var streamingFirstByteTimeout: TimeInterval
    public var streamingIdleTimeout: TimeInterval
    public var maxRetries: Int

    public init(
        timeout: TimeInterval = 600,
        streamingTimeout: TimeInterval = 1200,
        streamingFirstByteTimeout: TimeInterval = 60,
        streamingIdleTimeout: TimeInterval = 120,
        maxRetries: Int = 3
    ) {
        self.timeout = timeout
        self.streamingTimeout = streamingTimeout
        self.streamingFirstByteTimeout = streamingFirstByteTimeout
        self.streamingIdleTimeout = streamingIdleTimeout
        self.maxRetries = maxRetries
    }
}

/// HTTP client errors.
public enum HTTPClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case timeout
    case connectionFailed(String)
    case streamingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .timeout:
            return "Request timed out"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .streamingError(let message):
            return "Streaming error: \(message)"
        }
    }
}
