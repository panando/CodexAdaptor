import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Real-time log viewer backed by LogStore.
public struct LogViewerView: View {
    @ObservedObject private var logStore = LogStore.shared
    @ObservedObject private var loc = LocalizationService.shared
    @State private var autoScroll = true
    @State private var filterText = ""
    @State private var copyConfirmation = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(L10n.filter, text: $filterText)
                    .textFieldStyle(.roundedBorder)
                Toggle(L10n.autoScroll, isOn: $autoScroll)

                Button(L10n.copyAll) { copyAll() }

                Button(L10n.exportBtn) { exportLogs() }

                Button(L10n.clearBtn) { logStore.clear() }
            }
            .padding(8)

            Divider()

            ScrollViewReader { proxy in
                List(filteredEntries) { entry in
                    LogEntryRow(entry: entry)
                        .id(entry.id)
                }
                .onChange(of: logStore.entries.count) { _, _ in
                    if autoScroll, let last = filteredEntries.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            HStack {
                if copyConfirmation {
                    Text(L10n.copied)
                        .font(.caption).foregroundColor(.green)
                        .transition(.opacity)
                }
                Text("\(filteredEntries.count) \(L10n.entries)")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEntries: [LogEntry] {
        if filterText.isEmpty { return logStore.entries }
        return logStore.entries.filter { $0.message.localizedCaseInsensitiveContains(filterText) }
    }

    private func formatEntries(_ entries: [LogEntry]) -> String {
        entries.map { "[\($0.timestamp)] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
    }

    private func copyAll() {
        let text = formatEntries(filteredEntries)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyConfirmation = false }
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.title = L10n.exportLogs
        panel.nameFieldStringValue = "codexadaptor-logs-\(formattedDate()).txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let text = formatEntries(logStore.entries)
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func formattedDate() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df.string(from: Date())
    }
}

/// A single log entry.
public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: String
    public let level: DisplayLogLevel
    public let message: String

    public init(level: DisplayLogLevel, message: String) {
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.level = level
        self.message = message
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(entry.level.rawValue)
                .font(.system(.caption2, design: .monospaced)).fontWeight(.bold)
                .foregroundColor(entry.level.color)
                .frame(width: 45, alignment: .leading)
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }
}

public enum DisplayLogLevel: String, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"

    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        }
    }
}
