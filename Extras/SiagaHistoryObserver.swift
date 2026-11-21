// ⚠️ REMOVED FROM THE APP BUILD ON 21 Nov 2026 — DO NOT PUT BACK IN siaga/.
// Build error in Xcode 27 (09:00 WIB, 12 issues from this file alone):
//   "Class 'SiagaHistoryObserver' requires that 'ObservationTracking.Token'
//    conform to 'Copyable'"
//   "Key path cannot refer to noncopyable type 'ObservationTracking'"
// Cause: an @Observable class cannot store ObservationTracking.Token
// (noncopyable). @ObservationIgnored on the token was not verified, and
// guessing a second fix on hackathon morning is not worth the risk.
// This class was also unused — nothing in the app reads totalCount /
// criticalCount / latestTitle. HistoryView already shows history with
// a sectioned @Query, which works. Keep this file as a reference for
// after the hackathon; do not re-add it to the app target before it
// compiles cleanly in a scratch project.

import Foundation
import Observation
import SwiftData

// iOS 27 — ResultsObserver (WWDC26 session 274).
// @Query only works inside a SwiftUI view. The agent and the store live
// outside views, so they observe the incident history through ResultsObserver.
// Pattern follows the WWDC26 MapCameraController sample verbatim:
//   observer = try ResultsObserver<Trip, Never>(modelContext: modelContext)
//   token = withContinuousObservation(options: [.didSet]) { ... observer.results ... }
// Generic parameters are <Model, SectionName>; Never means "not sectioned".
// NOTE: Apple's published sample also appears as ModelResultsObserver in one
// snippet. Check the final SwiftData headers in Xcode 27 for the exact
// spelling; the init / .results / token shape above is the WWDC26 shape.
//
// What it is used for in Siaga (all on-device, all local):
// - totalCount / criticalCount shown in History, so the caregiver sees
//   at a glance whether this family has had critical incidents before.
// - latestTitle, so the action profile can say "this is the second fall
//   this month" without the model having to remember it.
// The observer does NOT sync anything anywhere. There is no server, no
// HistoryObserver sync job — Siaga has no backend to sync to.

@MainActor
@Observable
final class SiagaHistoryObserver {
    private let observer: ResultsObserver<IncidentHistory, Never>
    private var token: ObservationTracking.Token?

    private(set) var totalCount = 0
    private(set) var criticalCount = 0
    private(set) var latestTitle: String?

    init(modelContext: ModelContext) throws {
        observer = try ResultsObserver<IncidentHistory, Never>(modelContext: modelContext)
        recompute()
        token = withContinuousObservation(options: [.didSet]) { [weak self] _ in
            self?.recompute()
        }
    }

    private func recompute() {
        let items = observer.results
        totalCount = items.count
        criticalCount = items.filter { $0.severity == .critical }.count
        latestTitle = items.sorted { $0.createdAt > $1.createdAt }.first?.snapshot.title
    }
}
