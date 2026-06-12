import Foundation

/// In-memory ring buffer for log entries. Observable by LogViewerView.
public final class LogStore: ObservableObject, @unchecked Sendable {
    public static let shared = LogStore()

    @Published public private(set) var entries: [LogEntry] = []
    private let maxEntries = 2000
    private let lock = NSLock()

    private init() {}

    /// Thread-safe append from any context.
    public func append(level: DisplayLogLevel, message: String) {
        let entry = LogEntry(level: level, message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        lock.unlock()
    }

    /// Convenience: append info-level message.
    public func info(_ message: String) {
        append(level: .info, message: message)
    }

    /// Clear all entries.
    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
