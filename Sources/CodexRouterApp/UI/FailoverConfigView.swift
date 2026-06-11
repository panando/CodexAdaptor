import SwiftUI
import CodexRouterCore
import CodexRouterDB

/// View for configuring failover queue.
public struct FailoverConfigView: View {
    @ObservedObject var appState: AppState

    @State private var autoFailoverEnabled = false
    @State private var failoverQueue: [Provider] = []
    @State private var availableProviders: [Provider] = []

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Failover Configuration")
                    .font(.headline)
            }
            .padding()

            Divider()

            // Settings
            Form {
                Section {
                    Toggle("Enable Auto Failover", isOn: $autoFailoverEnabled)
                        .onChange(of: autoFailoverEnabled) { _, newValue in
                            updateFailoverSetting(newValue)
                        }

                    Text("When enabled, requests will automatically be retried with the next provider in the queue if the current provider fails.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Failover Queue") {
                    if failoverQueue.isEmpty {
                        Text("No providers in failover queue")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(failoverQueue) { provider in
                            HStack {
                                Text("\(provider.name)")
                                    .font(.body)

                                Spacer()

                                Button(action: {
                                    removeFromQueue(provider)
                                }) {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onMove(perform: moveInQueue)
                    }
                }

                Section("Available Providers") {
                    if availableProviders.isEmpty {
                        Text("All providers are in the failover queue")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(availableProviders) { provider in
                            HStack {
                                Text(provider.name)
                                    .font(.body)

                                Spacer()

                                Button(action: {
                                    addToQueue(provider)
                                }) {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.green)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 500)
        .onAppear {
            loadData()
        }
    }

    private func loadData() {
        // Load failover setting
        let configDAO = ProxyConfigDAO(appState.database)
        if let config = try? configDAO.get() {
            autoFailoverEnabled = config.autoFailoverEnabled
        }

        // Load failover queue
        let failoverDAO = FailoverDAO(appState.database)
        failoverQueue = (try? failoverDAO.getQueue(appType: "codex")) ?? []

        // Calculate available providers
        let queueIds = Set(failoverQueue.map { $0.id })
        availableProviders = appState.providers.filter { !queueIds.contains($0.id) }
    }

    private func updateFailoverSetting(_ enabled: Bool) {
        let configDAO = ProxyConfigDAO(appState.database)
        try? configDAO.setAutoFailover(enabled: enabled)
    }

    private func addToQueue(_ provider: Provider) {
        let failoverDAO = FailoverDAO(appState.database)
        let priority = failoverQueue.count
        try? failoverDAO.addToQueue(providerId: provider.id, appType: "codex", priority: priority)
        loadData()
    }

    private func removeFromQueue(_ provider: Provider) {
        let failoverDAO = FailoverDAO(appState.database)
        try? failoverDAO.removeFromQueue(providerId: provider.id, appType: "codex")
        loadData()
    }

    private func moveInQueue(from source: IndexSet, to destination: Int) {
        var queue = failoverQueue
        queue.move(fromOffsets: source, toOffset: destination)

        let failoverDAO = FailoverDAO(appState.database)
        try? failoverDAO.reorderQueue(
            appType: "codex",
            providerIds: queue.map { $0.id }
        )
        loadData()
    }
}
