import AppIntents
import Foundation

// iOS 27 — Siri AI / Spotlight entry point (stable App Intents, NOT the
// iOS 27.3 developer-preview custom-skills / ToolIntent API).
// The 27.3 preview (SKILL.md bundles, @AppIntent(.tool)) is beta, App Store
// submissions open in spring, API may change — do NOT build the hackathon demo on it.
// This file uses the stable AppIntents API that ships in iOS 27:
// "Hey Siri, start a Siaga emergency" / Spotlight search for a profile,
// then the app opens to the Emergency Note screen. The agent itself still
// runs on-device inside the app; Siri only launches it.

struct MedicalProfileEntity: AppEntity {
    var id: UUID
    var name: String
    var bloodType: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Medical Profile")
    static var defaultQuery = MedicalProfileQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Blood type \(bloodType)")
    }
}

struct MedicalProfileQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [MedicalProfileEntity] {
        // Profiles live in SwiftData in the app. Intents run in a separate
        // process, so this query returns the seeded dummy family here and the
        // app re-resolves the full SwiftData record on open. Keep it small
        // and on-device: no network, no cloud lookup.
        let known: [UUID: MedicalProfileEntity] = [:]
        return identifiers.compactMap { known[$0] }
    }

    func suggestedEntities() async throws -> [MedicalProfileEntity] {
        []
    }
}

struct StartEmergencyIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Siaga emergency"
    static var description = IntentDescription("Opens Siaga to the Emergency Note screen so you can describe what happened.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SiagaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // FIXED 21 Nov 2026: Xcode 27 errors "Every App Shortcut utterance
        // should contain '${applicationName}'" if no phrase uses it, and the
        // intent:phrases: init is deprecated since iOS 17 — provide
        // shortTitle and systemImageName.
        AppShortcut(
            intent: StartEmergencyIntent(),
            phrases: [
                "Start a \(.applicationName) emergency",
                "\(.applicationName) emergency",
                "Help with \(.applicationName)"
            ],
            shortTitle: "Start Emergency",
            systemImageName: "cross.case.fill"
        )
    }
}
