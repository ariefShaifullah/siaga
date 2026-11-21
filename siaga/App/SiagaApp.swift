import SwiftUI
import SwiftData

@main
struct SiagaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [MedicalProfile.self, IncidentHistory.self])
    }
}
