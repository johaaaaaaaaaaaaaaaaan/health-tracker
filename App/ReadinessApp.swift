import SwiftUI

@main
struct ReadinessApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HealthKitProbeView()
            }
        }
    }
}
