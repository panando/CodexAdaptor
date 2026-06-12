import SwiftUI
import CodexRouterCore

/// View for configuring failover queue.
/// Note: Failover configuration is currently not supported with unified Codex config.
public struct FailoverConfigView: View {
    @ObservedObject var appState: AppState

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

            VStack(spacing: 16) {
                Image(systemName: "info.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("Failover is managed through ~/.codex/config.toml")
                    .font(.body)
                    .multilineTextAlignment(.center)

                Text("Configure multiple providers in your Codex config file to enable failover.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
        .frame(width: 450, height: 300)
    }
}
