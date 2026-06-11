import SwiftUI
import CodexRouterCore
import CodexRouterDB

/// View for managing provider list.
public struct ProviderListView: View {
    @ObservedObject var appState: AppState
    @State private var showingAddProvider = false
    @State private var providerToEdit: Provider?
    @State private var showingDeleteConfirm = false
    @State private var providerToDelete: Provider?

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Providers")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddProvider = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding()

            Divider()

            // Provider list
            if appState.providers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No providers configured")
                        .foregroundColor(.secondary)
                    Button("Add Provider") {
                        showingAddProvider = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.providers) { provider in
                        ProviderRow(
                            provider: provider,
                            isCurrent: appState.currentProvider == provider.name,
                            onSelect: {
                                setCurrentProvider(provider)
                            },
                            onEdit: {
                                providerToEdit = provider
                            },
                            onDelete: {
                                providerToDelete = provider
                                showingDeleteConfirm = true
                            }
                        )
                    }
                    .onMove(perform: moveProvider)
                }
            }
        }
        .sheet(isPresented: $showingAddProvider) {
            ProviderFormView(appState: appState, provider: nil)
        }
        .sheet(item: $providerToEdit) { provider in
            ProviderFormView(appState: appState, provider: provider)
        }
        .alert("Delete Provider?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let provider = providerToDelete {
                    deleteProvider(provider)
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(providerToDelete?.name ?? "")'?")
        }
    }

    private func setCurrentProvider(_ provider: Provider) {
        let dao = ProviderDAO(appState.database)
        try? dao.setCurrent(id: provider.id)
        appState.loadProviders()
    }

    private func moveProvider(from source: IndexSet, to destination: Int) {
        var providers = appState.providers
        providers.move(fromOffsets: source, toOffset: destination)

        // Update sort indices
        let dao = ProviderDAO(appState.database)
        for (index, provider) in providers.enumerated() {
            try? dao.setCurrent(id: provider.id)
        }
        appState.loadProviders()
    }

    private func deleteProvider(_ provider: Provider) {
        let dao = ProviderDAO(appState.database)
        try? dao.delete(id: provider.id)

        // Also remove from keychain
        try? KeychainService.shared.deleteKey(for: provider.id)

        appState.loadProviders()
    }
}

/// Row view for a single provider.
struct ProviderRow: View {
    let provider: Provider
    let isCurrent: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            Circle()
                .fill(isCurrent ? Color.green : Color.clear)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.body)

                if let baseURL = provider.baseURL {
                    Text(baseURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
