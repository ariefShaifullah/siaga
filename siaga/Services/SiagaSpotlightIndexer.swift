import CoreSpotlight
import Foundation

// iOS 27 — Local RAG with Core Spotlight (WWDC26 session 246).
// App records become CSSearchableItems once, then SpotlightSearchTool lets
// the model search them locally — no server, no embedding store, no network.
// Architecture: FirstAidCase / IncidentHistory -> CSSearchableItem ->
// CSSearchableIndex -> SpotlightSearchTool -> LanguageModelSession.
//
// What is indexed (on-device only):
// - Every first-aid case (title + steps as contentDescription), so the model
//   can retrieve "what were the burn steps?" from the app's own guide
//   instead of recalling them.
// - Every saved incident (title + person + code), so the model can answer
//   "has Sari had a fall before?" from local history.
// Retrieved text is UNTRUSTED data. It must never override the safety
// instructions in SiagaSafetyInstructions, and it must never authorise
// a tool action by itself.

enum SiagaSpotlightIndexer {
    static func indexFirstAidCases(_ cases: [FirstAidCase]) {
        let items = cases.map { firstAid in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = "First aid: \(firstAid.title)"
            attributes.contentDescription = firstAid.steps.joined(separator: " ")
            return CSSearchableItem(
                uniqueIdentifier: "siaga-firstaid-\(firstAid.code)",
                domainIdentifier: "siaga.firstaid",
                attributeSet: attributes
            )
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    static func indexIncident(_ incident: IncidentHistory) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = incident.snapshot.title
        attributes.contentDescription = "\(incident.snapshot.personName), \(incident.snapshot.situationCode), severity \(incident.snapshot.severity)"
        let item = CSSearchableItem(
            uniqueIdentifier: "siaga-incident-\(incident.id.uuidString)",
            domainIdentifier: "siaga.incidents",
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }
}
