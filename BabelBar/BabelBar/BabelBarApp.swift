import SwiftUI

@main
struct BabelBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No standard window scene — the UI lives entirely in the status-bar popover.
        // Settings scene kept empty so the app runs as a pure menu-bar agent.
        Settings {
            EmptyView()
        }
    }
}
