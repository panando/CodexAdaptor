import SwiftUI

/// View for displaying application logs.
public struct LogViewerView: View {
    @State private var logEntries: [LogEntry] = []
    @State private var autoScroll = true
    @State private var filterText = ""

    private let logFilePath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex-router/logs/proxy.log"
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField("Filter logs...", text: $filterText)
                    .textFieldStyle(.roundedBorder)

                Toggle("Auto-scroll", isOn: $autoScroll)

                Button("Clear") {
                    logEntries.removeAll()
                }

                Button("Open File") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: logFilePath))
                }
            }
            .padding()

            Divider()

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: logEntries.count) { _, _ in
                    if autoScroll, let lastId = filteredEntries.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(textBackgroundColor))

            // Status bar
            HStack {
                Text("\(filteredEntries.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if FileManager.default.fileExists(atPath: logFilePath) {
                    Text(logFilePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
        }
        .frame(minWidth: 500, minHeight: 300)
        .onAppear {
            loadLogs()
        }
        .onReceive(timer) { _ in
            loadLogs()
        }
    }

    private var filteredEntries: [LogEntry] {
        if filterText.isEmpty {
            return logEntries
        }
        return logEntries.filter { $0.message.localizedCaseInsensitiveContains(filterText) }
    }

    private var textBackgroundColor: NSColor {
        NSColor.textBackgroundColor
    }

    private func loadLogs() {
        guard FileManager.default.fileExists(atPath: logFilePath) else {
            // If no log file, show sample entries
            if logEntries.isEmpty {
                logEntries = [
                    LogEntry(level: .info, message: "CodexRouter started"),
                    LogEntry(level: .info, message: "Server listening on port 15721"),
                    LogEntry(level: .info, message: "Ready to accept connections"),
                ]
            }
            return
        }

        guard let content = try? String(contentsOfFile: logFilePath, encoding: .utf8) else {
            return
        }

        let lines = content.components(separatedBy: .newlines)
        var entries: [LogEntry] = []

        for line in lines where !line.isEmpty {
            if let entry = parseLogLine(line) {
                entries.append(entry)
            }
        }

        // Keep last 1000 entries
        logEntries = Array(entries.suffix(1000))
    }

    private func parseLogLine(_ line: String) -> LogEntry? {
        // Parse format: "2024-01-01T12:00:00Z [LEVEL] [Category] message"
        let components = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard components.count >= 2 else { return nil }

        let timestamp = String(components[0])
        var level: DisplayLogLevel = .info
        var message = line

        if components.count >= 2 {
            let levelStr = String(components[1])
            if levelStr.contains("DEBUG") {
                level = .debug
            } else if levelStr.contains("INFO") {
                level = .info
            } else if levelStr.contains("WARN") {
                level = .warning
            } else if levelStr.contains("ERROR") {
                level = .error
            }
        }

        if components.count >= 4 {
            message = String(components[3])
        }

        return LogEntry(timestamp: timestamp, level: level, message: message)
    }
}

/// A single log entry.
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let level: DisplayLogLevel
    let message: String

    init(level: DisplayLogLevel, message: String) {
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.level = level
        self.message = message
    }

    init(timestamp: String, level: DisplayLogLevel, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

/// Row view for a log entry.
struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(entry.level.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(colorForLevel(entry.level))
                .frame(width: 50, alignment: .leading)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }

    private func colorForLevel(_ level: DisplayLogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

/// Log level for display.
enum DisplayLogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}
