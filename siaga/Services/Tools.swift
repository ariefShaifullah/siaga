import FoundationModels

// Siaga's 4 custom tools. Same pattern as WorkspaceAssistant-Lite Tools.swift:
// name + description tell the model WHEN to call it,
// @Generable Arguments are the only fields the model may fill in,
// call(arguments:) is plain Swift that returns what really happened.
// No tool ever sends a message, makes a call, or touches the network.
// DraftEmergencyMessageTool and CreateHandoverTool only DRAFT. The user approves in the UI.
//
// iOS 27: the action profile (SiagaProfile.swift) adds Apple's built-in
// system tools alongside these 4: SpotlightSearchTool() only — OCRTool() / BarcodeReaderTool() were removed 21 Nov 2026, Xcode 27 does not have them in scope in this SDK.
// They are Vision-backed, on-device, and the model calls them on an
// attached photo — e.g. to read a medication bottle label or scan its
// barcode. They are NOT in this file because Apple provides them.

struct LookupFirstAidTool: Tool {
    let name = "lookupFirstAid"
    let description = "READ-ONLY. Returns the pre-approved first-aid steps for one situation code from the bundled offline guide. Never invents medical steps."
    let store: SiagaStore

    @Generable
    struct Arguments {
        var situationCode: SituationCode
    }

    func call(arguments: Arguments) async throws -> String {
        await store.lookupFirstAid(code: arguments.situationCode)
    }
}

struct LookupMedicalProfileTool: Tool {
    let name = "lookupMedicalProfile"
    let description = "READ-ONLY. Returns the stored on-device medical profile for the named person: blood type, allergies, medication, emergency contact. Nothing is fetched from the cloud."
    let store: SiagaStore

    @Generable
    struct Arguments {
        @Guide(description: "The person's name, exactly as in the brief")
        var personName: String
    }

    func call(arguments: Arguments) async throws -> String {
        await store.lookupProfile(name: arguments.personName)
    }
}

struct DraftEmergencyMessageTool: Tool {
    let name = "draftEmergencyMessage"
    let description = "NEEDS APPROVAL. Drafts an SMS to the emergency contact with location, brief, severity and allergies. It only drafts. Nothing is sent until the user taps Approve in the app."
    let store: SiagaStore

    @Generable
    struct Arguments {
        @Guide(description: "The emergency contact's name, exactly as in the profile")
        var recipientName: String
    }

    func call(arguments: Arguments) async throws -> String {
        await store.draftMessage(to: arguments.recipientName)
    }
}

struct CreateHandoverTool: Tool {
    let name = "createHandover"
    let description = "NEEDS APPROVAL. Creates a one-page handover summary for paramedics from the brief, profile and steps taken. The user reviews it before it is shown or shared."
    let store: SiagaStore

    @Generable
    struct Arguments {
        @Guide(description: "True to include the first-aid steps that were shown")
        var includeStepsTaken: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await store.createHandover(includeStepsTaken: arguments.includeStepsTaken)
    }
}
