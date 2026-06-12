import Foundation
import OSLog

/// Log level for the logging service.
public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    var prefix: String {
        switch self {
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARN]"
        case .error: return "[ERROR]"
        }
    }
}

/// Log category for organizing log messages.
public enum LogCategory: String, Sendable {
    case proxy = "Proxy"
    case provider = "Provider"
    case database = "Database"
    case failover = "Failover"
    case circuitBreaker = "CircuitBreaker"
    case transformer = "Transformer"
    case config = "Config"
    case ui = "UI"
    case general = "General"
}

/// Structured logging service for CodexRouter.
public actor LoggingService {
    public static let shared = LoggingService()

    private let logger = Logger(subsystem: "com.codexrouter.app", category: "General")
    private var minimumLevel: LogLevel = .info
    private var logFileURL: URL?
    private var fileHandle: FileHandle?

    private init() {}

    // MARK: - Configuration

    /// Set the minimum log level.
    public func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
    }

    /// Enable file logging to a specific path.
    public func enableFileLogging(to path: String? = nil) throws {
        let logPath = path ?? Self.defaultLogPath()
        logFileURL = URL(fileURLWithPath: logPath)

        // Ensure directory exists
        let directory = logFileURL!.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        fileHandle = try FileHandle(forWritingTo: logFileURL!)
    }

    /// Disable file logging.
    public func disableFileLogging() {
        fileHandle?.closeFile()
        fileHandle = nil
        logFileURL = nil
    }

    /// Default log path: ~/.codex/logs/proxy.log
    public static func defaultLogPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex/logs/proxy.log"
    }

    // MARK: - Logging Methods

    /// Log a debug message.
    public func debug(
        _ message: String,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    /// Log an info message.
    public func info(
        _ message: String,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    /// Log a warning message.
    public func warning(
        _ message: String,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    /// Log an error message.
    public func error(
        _ message: String,
        category: LogCategory = .general,
        error: Error? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .error, category: category, file: file, function: function, line: line)
    }

    // MARK: - Private Methods

    private func log(
        _ message: String,
        level: LogLevel,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    ) {
        guard level >= minimumLevel else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(timestamp) \(level.prefix) [\(category.rawValue)] \(fileName):\(line) - \(message)"

        // Log to OSLog
        logger.log(level: level.osLogType, "\(logMessage)")

        // Log to file if enabled
        if let handle = fileHandle {
            let data = (logMessage + "\n").data(using: .utf8)!
            handle.write(data)
        }
    }
}

// MARK: - Convenience Functions

/// Global logging functions for easy access.
public func logDebug(
    _ message: String,
    category: LogCategory = .general,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task { await LoggingService.shared.debug(message, category: category, file: file, function: function, line: line) }
}

public func logInfo(
    _ message: String,
    category: LogCategory = .general,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task { await LoggingService.shared.info(message, category: category, file: file, function: function, line: line) }
}

public func logWarning(
    _ message: String,
    category: LogCategory = .general,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task { await LoggingService.shared.warning(message, category: category, file: file, function: function, line: line) }
}

public func logError(
    _ message: String,
    category: LogCategory = .general,
    error: Error? = nil,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task { await LoggingService.shared.error(message, category: category, error: error, file: file, function: function, line: line) }
}
