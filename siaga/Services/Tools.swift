import FoundationModels

// Siaga's 4 custom tools. Same pattern as WorkspaceAssistant-Lite Tools.swift:
// name + description tell the model WHEN to call it,
// @Generable Arguments are the only fields the model may fill in,
// call(arguments:) is plain Swift that returns what really happened.
// No tool ever sends a message, makes a call, or touches the network.
// DraftEmergencyMessageTool and CreateHandoverTool only DRAFT. The user approves in the UI.
//
// iOS 27: the action profile (SiagaProfile.swift) used to add Apple's
// built-in system tools alongside these 4: SpotlightSearchTool() for local
// RAG, plus OCRTool() / BarcodeReaderTool() for reading a photo. All three
// are gone as of 21 Nov 2026: the OCR tools do not exist in this Xcode 27
// SDK ("Cannot find in scope"), and SpotlightSearchTool made every action
// request fail with "Resource (Local Model Asset) unavailable" — its asset
// is not on this device/simulator. They are NOT in this file because Apple
// provides them; the profile documents each removal.

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
    let description = "Drafts an SMS to the emergency contact with location, brief, severity and allergies. It only drafts — the user copies it or opens it in Messages; the app never sends anything itself."
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
