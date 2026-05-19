import SwiftUI
import Foundation

// NSUserNotificationCenter: no permission required for non-sandboxed apps,
// shouldPresent ensures delivery even when app is in foreground.
class AppNotificationDelegate: NSObject, NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter,
                                shouldPresent notification: NSUserNotification) -> Bool { true }
}

@main
struct SushiSpeakApp: App {
    private let notifDelegate = AppNotificationDelegate()

    init() {
        NSUserNotificationCenter.default.delegate = notifDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
