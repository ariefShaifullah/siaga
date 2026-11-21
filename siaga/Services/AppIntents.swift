import AppIntents
import Foundation

// iOS 27 — Siri AI / Spotlight entry point (stable App Intents, NOT the
// iOS 27.3 developer-preview custom-skills / ToolIntent API).
// The 27.3 preview (SKILL.md bundles, @AppIntent(.tool)) is beta, App Store
// submissions open in spring, API may change — do NOT build the hackathon demo on it.
// This file uses the stable AppIntents API that ships in iOS 27:
// "Hey Siri, start a Siaga emergency", then the app opens to the
// Emergency Note screen. The agent itself still runs on-device inside
// the app; Siri only launches it.

// No MedicalProfileEntity / EntityQuery here (removed 21 Nov 2026,
// audit): the query's lookup table was empty, so it could never resolve
// a profile, suggestedEntities() returned nothing, and no intent or
// shortcut ever used the entity. Siri only launches the app — the agent
// and the profiles live inside it.

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
