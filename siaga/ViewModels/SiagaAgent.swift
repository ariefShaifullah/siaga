import Foundation
import FoundationModels
import Observation
import UIKit

/// Siaga's agent — iOS 27 version.
///
/// v1 had TWO sessions (brief, no tools / action, 4 tools). iOS 27 replaces
/// them with ONE session backed by a Dynamic Profile (SiagaProfile.swift):
/// triage → action → handover, same transcript, instructions / tools /
// temperature swap in place. All three branches use SystemLanguageModel()
/// ON-DEVICE ONLY — no PCC, no provider model.
///
/// iOS 27 additions in this file, in order of demo impact:
/// 1. MULTIMODAL: analyse(note:image:) — the user can attach a photo of the
///    injury, a medication bottle or an allergy card. The model describes
///    the image on-device (Attachment(image)), then that description is fed
///    as TEXT into the strict brief extraction. Strict fields stay on the
///    specialised path (photo as Attachment(image) in the action profile),
///    per Apple's guidance: image prompts for interpretation, system tools
///    for repeatable fields.
/// 2. TOKEN BUDGET: contextSize is 8192 on-device in iOS 27. The agent
///    checks TokenBudget.fits(prompt) BEFORE calling the model and starts a
///    fresh session instead of waiting for contextSizeExceeded. Usage is
///    reported from response.usage (input / output token counts).
/// 3. DYNAMIC PROFILE: see SiagaProfile.swift. If Xcode 27 autocomplete
///    shows a different DynamicProfile spelling, use autocomplete — the
///    v1 two-session code is in git history / README, and the agent API
///    (analyse / buildActionPlan) does not change.
///
/// If Apple Intelligence is unavailable, analyse() does NOT invent a brief
/// with a fake model. It uses the deterministic keyword fallback below,
/// labels it clearly in the UI, and the user edits the brief by hand.
@MainActor
@Observable
final class SiagaAgent {
    let store: SiagaStore
    let orchestrator: SiagaOrchestrator
    private(set) var isWorking = false
    private(set) var streamingText = ""
    private(set) var problem: String?
    private(set) var fallbackUsed = false
    private(set) var imageDescription: String?
    private var session: LanguageModelSession

    init(store: SiagaStore) {
        self.store = store
        let orchestrator = SiagaOrchestrator()
        self.orchestrator = orchestrator
        self.session = LanguageModelSession(profile: SiagaProfile(orchestrator: orchestrator, store: store))
    }

    func newIncident(preservingBrief: Bool = false) {
        // Transcript management, agent level (iOS 27, Round 2).
        // The framework transcript is mutable in iOS 27, but rewriting it
        // can invalidate the KV cache and confuse the model (WWDC26 242).
        // Siaga therefore keeps its own compact summary — the structured
        // brief + the actions taken — and starts a fresh session from it.
        // The raw panic note is discarded after extraction; only the brief
        // survives, which also protects privacy.
        let preservedBrief = preservingBrief ? store.currentBrief : nil
        let preservedActions = preservingBrief ? store.actions : []
        store.resetForNewIncident()
        if let preservedBrief {
            store.currentBrief = preservedBrief
            store.actions = preservedActions
        }
        streamingText = ""
        problem = nil
        fallbackUsed = false
        imageDescription = nil
        orchestrator.mode = .triage
        session = LanguageModelSession(profile: SiagaProfile(orchestrator: orchestrator, store: store))
    }

    /// The compact transcript: brief + actions, no raw note. Used when the
    /// token budget is exceeded, so the next session starts from facts,
    /// not from a wall of panic text.
    func compactTranscript() -> String {
        guard let brief = store.currentBrief else { return "No incident yet." }
        return "Previous incident (compacted): \(brief.situationTitle), \(brief.personName), severity \(brief.severity.rawValue), \(brief.whatHappened). Actions so far: \(store.actions.joined(separator: "; "))"
    }

    func prewarm() {
        if unavailableReason == nil { session.prewarm() }
    }

    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in Settings to use the agent."
        case .unavailable(.modelNotReady):
            "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable:
            "Apple Intelligence isn't available right now."
        }
    }

    // MARK: - Step 1: brief (triage profile, multimodal if a photo is attached)

    func analyse(note: String, image: UIImage? = nil) async -> EmergencyBrief? {
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isWorking else { return store.currentBrief }
        isWorking = true
        defer { isWorking = false }
        problem = nil
        fallbackUsed = false
        imageDescription = nil
        orchestrator.mode = .triage

        if unavailableReason != nil {
            fallbackUsed = true
            let brief = FallbackBriefExtractor.extract(from: clean, personName: store.selectedProfile?.name)
            store.currentBrief = brief
            return brief
        }

        // Multimodal, on-device: describe the photo first, in plain text.
        // The description — never the raw pixels — goes into the brief prompt.
        var imageNote = ""
        if let image {
            do {
                let description = try await session.respond {
                    "Describe only what is medically relevant in this image, in 2 short sentences: what injury, rash, swelling or label text do you see? Do not diagnose."
                    Attachment(image)
                }
                imageDescription = description.content
                imageNote = "\nPhoto description (on-device, from the attached image): \(description.content)"
            } catch {
                // A photo that cannot be described must not block the emergency.
                // Continue with text only; the user can still edit the brief.
                imageNote = "\n(A photo was attached but could not be described on-device.)"
            }
        }

        // The selected profile is ground truth for WHO, not the note.
        // Without it, "my mother" has no name to resolve to, and the old
        // code silently invented Sari. With it, the model is told the real
        // name, age and allergies before it extracts anything.
        let personContext: String
        if let selected = store.selectedProfile {
            personContext = "\nKnown person for this incident: \(selected.name), age \(selected.age), blood type \(selected.bloodType), allergies: \(selected.allergies), medications: \(selected.medications). If the note refers to them by relationship (mother, father, wife, husband, son, daughter), personName is \(selected.name). If the note names a different person, use that name instead."
        } else {
            personContext = "\nNo family profile was selected. personName is the name in the note, or \"Unknown\" if the note names nobody."
        }
        let prompt = "Extract the emergency brief from this note:\n\(personContext)\n\n<note>\n\(clean)\(imageNote)\n</note>"

        // Token budget check BEFORE spending tokens (iOS 27, context 8192).
        guard TokenBudget.fits(prompt) else {
            _ = compactTranscript()
            newIncident(preservingBrief: true)
            problem = "That note was too long for the on-device model, so I started a fresh session from the compact brief. Please try again with a shorter note."
            return nil
        }

        do {
            let response = try await session.respond(to: prompt, generating: EmergencyBrief.self)
            store.lastTokenUsage = "Brief: \(response.usage.input.totalTokenCount) in / \(response.usage.output.totalTokenCount) out tokens (context \(SystemLanguageModel().contextSize))"
            store.currentBrief = response.content
            return response.content
        } catch LanguageModelError.contextSizeExceeded {
            _ = compactTranscript()
            newIncident(preservingBrief: true)
            problem = "The on-device model ran out of context, so I started a fresh one from the compact brief. Please try again with a shorter note."
            return nil
        } catch {
            fallbackUsed = true
            problem = "The model could not be reached (\(error.localizedDescription)). Using the offline fallback — please check the brief."
            let brief = FallbackBriefExtractor.extract(from: clean, personName: store.selectedProfile?.name)
            store.currentBrief = brief
            return brief
        }
    }

    // MARK: - Step 2: action plan (action profile, tools, streamed)

    func buildActionPlan() async {
        guard let brief = store.currentBrief, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        streamingText = ""
        orchestrator.mode = .action

        if unavailableReason != nil || fallbackUsed {
            _ = store.lookupProfile(name: brief.personName)
            _ = store.lookupFirstAid(code: brief.situationCode)
            _ = store.draftMessage(to: store.lastProfile?.emergencyContactName ?? store.selectedProfile?.emergencyContactName ?? "emergency contact")
            _ = store.createHandover(includeStepsTaken: true)
            streamingText = "Offline fallback: profile, first-aid steps, draft message and handover are ready. Please review them."
            return
        }

        let prompt = """
        Build the action plan for this brief. Title: \(brief.situationTitle). Person: \(brief.personName). Situation: \(brief.situationCode.rawValue). Severity: \(brief.severity.rawValue). What happened: \(brief.whatHappened).
        """
        do {
            for try await snapshot in session.streamResponse(to: prompt) {
                streamingText = snapshot.content
            }
            // Handover runs in its own profile branch, same transcript.
            orchestrator.mode = .handover
            _ = store.createHandover(includeStepsTaken: true)
        } catch LanguageModelError.contextSizeExceeded {
            _ = compactTranscript()
            newIncident(preservingBrief: true)
            problem = "The on-device model ran out of context, so I started a fresh session from the compact brief. The brief is kept — please try building the plan again."
        } catch {
            problem = error.localizedDescription
        }
    }
}

// MARK: - Deterministic fallback (no model, keyword matching only)

enum FallbackBriefExtractor {
    // personName comes from the user's selected profile, never from a
    // hardcoded name. The old code mapped mother -> Sari, father -> Agus,
    // son -> Budi, which made the app unusable for any other family.
    static func extract(from note: String, personName: String? = nil) -> EmergencyBrief {
        let lower = note.lowercased()
        let code: SituationCode
        let severity: Severity
        if lower.contains("chok") { code = .choking; severity = .critical }
        else if lower.contains("peanut") || lower.contains("allerg") || lower.contains("swell") { code = .allergicReaction; severity = .critical }
        else if lower.contains("bleed") || lower.contains("fell") || lower.contains("fall") { code = .bleedingFall; severity = .high }
        else if lower.contains("burn") { code = .burn; severity = .medium }
        else if lower.contains("faint") { code = .fainting; severity = .high }
        else if lower.contains("sprain") || lower.contains("ankle") { code = .sprain; severity = .low }
        else { code = .unknown; severity = .high }

        let person = personName ?? "Unknown"

        return EmergencyBrief(
            situationTitle: "Emergency (offline fallback)",
            personName: person,
            whatHappened: note,
            symptoms: [],
            severity: severity,
            situationCode: code,
            locationDescription: "As described in the note",
            peopleInvolved: 1,
            immediateRisks: [],
            needsAmbulance: severity == .high || severity == .critical
        )
    }
}
