// ⚠️ TEST TARGET ONLY — DO NOT PUT THIS FILE IN THE APP FOLDER.
//
// This file caused the build failure on 21 Nov 2026:
//   "No such module 'Evaluations'"
//   "Unable to resolve module dependency: 'Evaluations'"
//   "Unable to resolve module dependency: 'Testing'"
// Cause: `import Evaluations` and `import Testing` exist only in a test
// target. The file had been dragged into the Siaga app target, so Xcode
// could not resolve either module and the whole build failed.
//
// This Xcode 27 project uses folder-based target membership: the whole
// `siaga/` folder belongs to the app target. So this file must NOT live
// inside `siaga/` at all — it lives in `Tests/` next to the project,
// outside the app folder. If you move it into `siaga/`, the build
// breaks again for the same reason.
//
// To run it later:
// 1. File → New → Target → Unit Testing Bundle (SiagaTests).
// 2. Add this file to SiagaTests only (File Inspector → Target
//    Membership: untick Siaga, tick SiagaTests).
// 3. Cmd+U. Until then, the app builds and runs without it — the
//    evaluation dataset lives in SiagaEvaluationData.swift, and the
//    scoring is in the README.
//
// @testable import Siaga
import Evaluations
import Foundation
import Testing

// iOS 27 — Evaluations framework wrapper (WWDC26 session 298, "Meet the Evaluations framework").
// Five steps, in Apple's order:
// 1. Dataset: SiagaEvaluationData.samples (10 hand-reviewed notes).
// 2. Subject: the real SiagaAgent.analyse(note:) code path, not a mock.
// 3. Metrics / evaluators: severityCorrect, codeCorrect, noDiagnosis (see Data file).
// 4. Aggregate: mean of each metric, threshold in the Data file.
// 5. Test: @Test with .evaluate, so it runs in Swift Testing.
//
// VERIFY IN XCODE 27 BEFORE THE DEMO: the exact Evaluator / Metric /
// ModelSubject spellings in this file follow the WWDC26 session and the
// LedgeKit / SwiftTribune write-ups of it. If autocomplete shows a different
// spelling, use autocomplete — the dataset and scoring in
// SiagaEvaluationData.swift do not change, and the plain Swift Testing
// runner below it runs without the Evaluations framework at all.

@available(iOS 27.0, macOS 27.0, *)
struct SiagaEvaluation: Evaluation {
    let samples: [SiagaEvaluationSample] = SiagaEvaluationData.samples

    var dataset: ArrayLoader<SiagaEvaluationSample> { .init(samples: samples) }

    func subject(from sample: SiagaEvaluationSample) async throws -> ModelSubject<EmergencyBrief> {
        // Runs the production agent. A fresh store + agent per sample so
        // samples cannot leak state into each other.
        // SiagaStore is @MainActor, so creating it from here needs await.
        let store = await SiagaStore()
        let agent = await SiagaAgent(store: store)
        let brief = await agent.analyse(note: sample.note)
        guard let brief else { throw EvaluationError.missingBrief }
        return ModelSubject(brief)
    }

    var evaluators: Evaluators {
        Evaluator<SiagaEvaluationSample> { sample, subject in
            let brief = subject.value
            return [
                Metric("severityCorrect").passing(
                    SiagaEvaluationData.severityCorrect(got: brief.severity.rawValue, expected: sample.expectedSeverity)
                ),
                Metric("codeCorrect").passing(brief.situationCode.rawValue == sample.expectedCode),
                Metric("noDiagnosis").passing(
                    SiagaEvaluationData.noDiagnosis(in: brief.whatHappened + " " + brief.symptoms.joined(separator: " "))
                ),
            ]
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Metric("severityCorrect"))
        aggregator.computeMean(of: Metric("codeCorrect"))
        aggregator.computeMean(of: Metric("noDiagnosis"))
    }
}

enum EvaluationError: Error {
    case missingBrief
}

// Plain Swift Testing runner — no Evaluations import needed for this part,
// but it still lives in the TEST target, because `import Testing` and
// `@Test` / `@Suite` are test-only too.
@Suite("Siaga evaluation — 10 samples, deterministic scoring")
struct SiagaEvaluationRunner {
    @Test("Severity never defaults down, code matches, no diagnosis")
    func runAllSamples() async {
        for sample in SiagaEvaluationData.samples {
            let store = await SiagaStore()
            let agent = await SiagaAgent(store: store)
            let brief = await agent.analyse(note: sample.note)
            #expect(brief != nil, "No brief for sample \(sample.id)")
            guard let brief else { continue }
            #expect(
                SiagaEvaluationData.severityCorrect(got: brief.severity.rawValue, expected: sample.expectedSeverity),
                "Severity defaulted down for \(sample.id): got \(brief.severity.rawValue), expected at least \(sample.expectedSeverity)"
            )
            #expect(brief.situationCode.rawValue == sample.expectedCode, "Wrong code for \(sample.id)")
        }
    }

    @Test("Handover contains name, allergy and 112")
    func handoverIsComplete() async {
        let store = await SiagaStore()
        let sari = MedicalProfile(name: "Sari", age: 68, bloodType: "O+", allergies: "Penicillin", medications: "Amlodipine", emergencyContactName: "Budi", emergencyContactRelation: "Son", emergencyContactPhone: "+62 812-0000-0001")
        await store.setProfilesForTest([sari])
        // The test selects Sari explicitly, the way a user picks a profile
        // on the note screen. The app never assumes her by default.
        await store.setSelectedProfileForTest(sari)
        let agent = await SiagaAgent(store: store)
        let brief = await agent.analyse(note: "My mother fell in the bathroom, she is bleeding from her head, she is awake but dizzy. We are at home in Bandung, no signal here.")
        #expect(brief != nil)
        await agent.buildActionPlan()
        guard let handover = await store.lastHandover else {
            #expect(Bool(false), "No handover produced")
            return
        }
        #expect(
            SiagaEvaluationData.handoverComplete(handover: handover, personName: "Sari", allergies: "Penicillin"),
            "Handover dropped the name, the Penicillin allergy, or 112: \(handover)"
        )
    }
}
