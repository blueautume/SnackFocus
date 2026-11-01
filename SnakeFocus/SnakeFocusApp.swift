import SwiftUI

@main
struct SnakeFocusApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--lab-board-only") {
                LabReferenceView()
            } else {
                DesignLabView()
            }
            #else
            DesignLabView()
            #endif
        }
    }
}
