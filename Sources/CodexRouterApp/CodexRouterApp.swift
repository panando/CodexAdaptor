import AppKit
import SwiftUI

@main
struct CodexRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSLog("[DEBUG] CodexRouterApp init")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
