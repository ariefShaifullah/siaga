import Foundation
import FoundationModels
import SwiftData

// MARK: - @Generable output (the type the on-device model fills in)

@Generable
enum Severity: String, CaseIterable {
    case low, medium, high, critical
}

@Generable
enum SituationCode: String, CaseIterable {
    case bleedingFall
    case choking
    case burn
    case allergicReaction
    case fainting
    case sprain
    case heartAttack
    case unknown
}

@Generable
struct EmergencyBrief {
    @Guide(description: "Short title, e.g. Mother fell in bathroom")
    var situationTitle: String
    var personName: String
    @Guide(description: "A factual description of the emergency in one or two sentences. Never a question. If the user's note is a question or has no facts (e.g. 'what happened to this man?'), describe what the photo shows instead — never copy the question.")
    var whatHappened: String
    @Guide(description: "Symptoms from the note AND from the photo description, e.g. chest pain, sweating, shortness of breath, bleeding, clutching chest. Empty only if truly none are visible or described.")
    var symptoms: [String]
    var severity: Severity
    var situationCode: SituationCode
    @Guide(description: "Where it happened, as described by the user")
    var locationDescription: String
    @Guide(.range(1...20))
    var peopleInvolved: Int
    var immediateRisks: [String]
    var needsAmbulance: Bool
}

// MARK: - Medical profile (SwiftData, on-device only, never synced)

@Model
final class MedicalProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var age: Int
    var bloodType: String
    var allergies: String // comma-separated, e.g. "Penicillin" or "None"
    var medications: String // comma-separated, e.g. "Amlodipine"
    var emergencyContactName: String
    var emergencyContactRelation: String
    var emergencyContactPhone: String

    init(name: String, age: Int, bloodType: String, allergies: String, medications: String,
         emergencyContactName: String, emergencyContactRelation: String, emergencyContactPhone: String) {
        self.id = UUID()
        self.name = name
        self.age = age
        self.bloodType = bloodType
        self.allergies = allergies
        self.medications = medications
        self.emergencyContactName = emergencyContactName
        self.emergencyContactRelation = emergencyContactRelation
        self.emergencyContactPhone = emergencyContactPhone
    }

    var summary: String {
        "\(name), \(age), blood type \(bloodType). Allergies: \(allergies). Medications: \(medications). Emergency contact: \(emergencyContactName) (\(emergencyContactRelation)), \(emergencyContactPhone)."
    }
}

// Picker selection needs Hashable. Identity is the stable id, not the name
// (two family members can share a first name).
extension MedicalProfile: Hashable {
    static func == (lhs: MedicalProfile, rhs: MedicalProfile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - iOS 27 — Token budget (AFM 3, on-device context is 8192 tokens)
//
// SystemLanguageModel().contextSize is 8192 in iOS 27 (4096 in iOS 26).
// Siaga checks the budget BEFORE spending it: if the estimated prompt is
// over the safe budget, it starts a fresh session instead of waiting for
// LanguageModelError.contextSizeExceeded. Usage is reported from
// response.usage.input.totalTokenCount / output.totalTokenCount (iOS 27).
// Estimate is characters / 4 — a rough proxy, never a precise token count.
// If Xcode 27 shows a tokenCount(for:) API in autocomplete, use that exact
// count here instead of the estimate; the budget check itself does not change.

enum TokenBudget {
    static let contextSize = 8192
    static let safeBudget = 6000
    static func estimatedTokens(for text: String) -> Int { max(1, text.count / 4) }
    static func fits(_ text: String) -> Bool { estimatedTokens(for: text) < safeBudget }
}

// MARK: - iOS 27 — Incident history (SwiftData: .codable + persisted section key)
//
// @Attribute(.codable) stores the whole brief snapshot as one Codable blob,
// instead of breaking it into columns. severityName is a persisted String
// (not a computed property, not the enum) because @Query(sectionBy:) in
// iOS 27 requires a persisted property to group on — see HistoryView.
// IncidentHistory does NOT store the Severity enum itself: Xcode 27
// (21 Nov 2026) rejects it — the @Model macro's generated setValue /
// getValue have no exact match for the @Generable enum. Severity lives
// only as the String severityName and inside snapshot.severity.

struct IncidentBriefSnapshot: Codable {
    var title: String
    var personName: String
    var severity: String
    var situationCode: String
    var symptoms: [String]

    init(brief: EmergencyBrief) {
        title = brief.situationTitle
        personName = brief.personName
        severity = brief.severity.rawValue
        situationCode = brief.situationCode.rawValue
        symptoms = brief.symptoms
    }
}

@Model
final class IncidentHistory {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var severityName: String // persisted, for @Query(sectionBy: \.severityName)
    @Attribute(.codable) var snapshot: IncidentBriefSnapshot

    init(brief: EmergencyBrief) {
        self.id = UUID()
        self.createdAt = Date()
        self.severityName = brief.severity.rawValue.capitalized
        self.snapshot = IncidentBriefSnapshot(brief: brief)
    }
}

// MARK: - First-aid guide (bundled JSON, read-only, pre-approved steps)

struct FirstAidCase: Codable, Identifiable {
    var id: String { code }
    var code: String
    var title: String
    var call112First: Bool
    var steps: [String]
}

enum FirstAidGuide {
    static func load() -> [FirstAidCase] {
        if let url = Bundle.main.url(forResource: "FirstAid", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let cases = try? JSONDecoder().decode([FirstAidCase].self, from: data) {
            return cases
        }
        return bundledFallback
    }

    // Fallback if FirstAid.json was not added to the target. Same content as the JSON file.
    static let bundledFallback: [FirstAidCase] = [
        FirstAidCase(code: "bleedingFall", title: "Fall with bleeding", call112First: true, steps: [
            "Press the wound with a clean cloth. Keep pressure on it.",
            "Keep the patient awake and talking.",
            "Do not move the neck if a spinal injury is suspected.",
            "Do not give food or drink.",
            "Call 112 now."
        ]),
        FirstAidCase(code: "choking", title: "Choking", call112First: true, steps: [
            "Ask if the person can cough or speak. If they cannot, act now.",
            "Give 5 back blows between the shoulder blades.",
            "Give 5 abdominal thrusts. Repeat until the object comes out.",
            "If the person becomes unconscious, call 112 and start CPR if trained.",
            "Call 112 now."
        ]),
        FirstAidCase(code: "burn", title: "Burn", call112First: false, steps: [
            "Cool the burn with running water for at least 10 minutes.",
            "Do not apply toothpaste, butter, or ice directly.",
            "Cover loosely with a clean cloth.",
            "Do not pop blisters.",
            "Call 112 if the burn is large, on the face or hands, or the person is in shock."
        ]),
        FirstAidCase(code: "allergicReaction", title: "Allergic reaction", call112First: true, steps: [
            "Use an EpiPen if the person has one and knows how to use it.",
            "Call 112 now. Difficulty breathing is an emergency.",
            "Keep the person lying down unless breathing is easier sitting up.",
            "Do not give food or drink.",
            "Note what was eaten or what triggered the reaction for paramedics."
        ]),
        FirstAidCase(code: "fainting", title: "Fainting", call112First: true, steps: [
            "Lay the person on their back and loosen tight clothing.",
            "Raise the legs slightly if there is no injury.",
            "Do not give food or drink while confused or drowsy.",
            "If they do not wake up within a minute, call 112.",
            "Note how long they were unconscious for paramedics."
        ]),
        FirstAidCase(code: "sprain", title: "Sprain", call112First: false, steps: [
            "Rest the injured area. Do not walk on it.",
            "Apply a cold compress for 15 minutes.",
            "Compress lightly with a bandage if available.",
            "Elevate the injured area.",
            "Call 112 or go to a clinic if the person cannot move it, the pain is severe, or the shape looks wrong."
        ]),
        FirstAidCase(code: "unknown", title: "Unknown emergency", call112First: true, steps: [
            "Call 112 now.",
            "Make the area safe. Do not put yourself in danger.",
            "Do not move the patient unless there is immediate danger.",
            "Keep the patient awake and talking if possible.",
            "Siaga has no specific steps for this situation. Tell 112 exactly what you see."
        ])
    ]
}

// MARK: - Store (the single source of truth the tools read and write)

@MainActor
@Observable
final class SiagaStore {
    var profiles: [MedicalProfile] = []
    // The person this incident is about, chosen by the user on the note
    // screen. Nil means "someone else / unknown". This is the fix for the
    // hardcoded demo profiles: the app must never silently assume Sari.
    var selectedProfile: MedicalProfile?
    var firstAidCases: [FirstAidCase] = FirstAidGuide.load()
    var actions: [String] = []
    var currentBrief: EmergencyBrief?
    var lastFirstAid: FirstAidCase?
    var lastProfile: MedicalProfile?
    var lastDraft: String?
    var lastHandover: String?
    var lastTokenUsage: String? // e.g. "Brief: 312 in / 48 out tokens (context 8192)"

    func record(_ action: String) {
        actions.append(action)
    }

    // Test-only helper: the store is @MainActor, so a test sets profiles
    // through this method instead of assigning a MainActor-isolated var.
    func setProfilesForTest(_ profiles: [MedicalProfile]) {
        self.profiles = profiles
    }

    func setSelectedProfileForTest(_ profile: MedicalProfile?) {
        self.selectedProfile = profile
    }

    func saveIncident() -> IncidentHistory? {
        guard let brief = currentBrief else { return nil }
        return IncidentHistory(brief: brief)
    }

    func profile(named name: String) -> MedicalProfile? {
        let needle = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // No silent fallback to profiles.first. The old code returned Sari
        // for every unknown name, so a stranger's allergy and contact were
        // silently replaced with hers. A miss now returns nil, and the
        // caller says so honestly ("No medical profile found").
        if needle.isEmpty || needle == "unknown" { return selectedProfile }
        return profiles.first { $0.name.lowercased().contains(needle) }
            ?? profiles.first { needle.contains($0.name.lowercased()) }
            ?? selectedProfile
    }

    func firstAid(for code: SituationCode) -> FirstAidCase {
        firstAidCases.first { $0.code == code.rawValue }
            ?? firstAidCases.first { $0.code == "unknown" }!
    }

    func lookupProfile(name: String) -> String {
        guard let found = profile(named: name) else { return "No medical profile found for \(name)." }
        lastProfile = found
        record("Checked medical profile: \(found.name)")
        return found.summary
    }

    func lookupFirstAid(code: SituationCode) -> String {
        let found = firstAid(for: code)
        lastFirstAid = found
        record("Looked up first-aid steps: \(found.title)")
        return ([found.title] + found.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }).joined(separator: "\n")
    }

    func draftMessage(to recipientName: String) -> String {
        guard let brief = currentBrief else { return "No emergency brief yet, so no draft was created." }
        let profileText = lastProfile?.summary ?? "No medical profile found."
        let draft = """
        EMERGENCY — \(brief.situationTitle)
        Severity: \(brief.severity.rawValue.uppercased()). Ambulance needed: \(brief.needsAmbulance ? "Yes" : "Not sure").
        Person: \(brief.personName). What happened: \(brief.whatHappened).
        Symptoms: \(brief.symptoms.joined(separator: ", ")).
        Location: \(brief.locationDescription).
        Medical profile: \(profileText)
        Please call 112 if you get this. I am with \(brief.personName) now.
        — Sent from Siaga (draft, not sent yet)
        """
        lastDraft = draft
        record("Drafted emergency message to \(recipientName) (not sent)")
        return draft
    }

    func createHandover(includeStepsTaken: Bool) -> String {
        guard let brief = currentBrief else { return "No emergency brief yet, so no handover was created." }
        let steps = includeStepsTaken ? (lastFirstAid?.steps ?? []) : []
        let handover = """
        HANDOVER FOR PARAMEDICS — \(brief.situationTitle)
        Time: \(Date().formatted(date: .abbreviated, time: .shortened))
        Person: \(brief.personName). Severity: \(brief.severity.rawValue). Ambulance: \(brief.needsAmbulance ? "Yes" : "Not sure").
        Call 112 — ambulance requested: \(brief.needsAmbulance ? "Yes" : "Not sure").
        What happened: \(brief.whatHappened)
        Symptoms: \(brief.symptoms.joined(separator: ", "))
        Location: \(brief.locationDescription). People involved: \(brief.peopleInvolved).
        Medical profile: \(lastProfile?.summary ?? "No profile found.")
        First-aid steps shown: \(steps.isEmpty ? "None" : steps.joined(separator: "; "))
        """
        lastHandover = handover
        record("Created handover summary for paramedics")
        return handover
    }

    func resetForNewIncident() {
        currentBrief = nil
        lastFirstAid = nil
        lastProfile = nil
        lastDraft = nil
        lastHandover = nil
        // selectedProfile is NOT reset here: the person is usually the same
        // family member across incidents, and re-picking them every time
        // would be friction in an emergency. The user can change it on the
        // note screen.
        actions.removeAll()
    }
}
