import SwiftUI
import UIKit

// Images WITHOUT leaving the emergency flow.
//
// The question behind this file: why open PhotosPicker at all in an
// emergency? Picking from the library leaves the note screen, needs photo
// permission, and on stage it eats demo time. There are two in-context
// alternatives, and Siaga now uses both:
//
// 1. BUNDLED SAMPLE IMAGES — UIImage(named:) directly, no picker, no
//    permission, no context switch. The two PNGs in SampleImages/ are
//    dragged into the Xcode project (target membership on) and called by
//    name here. They are deliberately TEXT cards, not fake injury photos:
//    a medication label ("Amlodipine 5 mg") and an allergy card
//    ("ALLERGY: PENICILLIN"). Neither card carries a patient name, blood
//    type or age — they are generic, usable for any family. The person
//    comes from the profile the user selected, never from the image.
//    the on-device model can actually read them as an attached image, so the demo proves the multimodal path
//    work, instead of pretending a stock photo is a real injury.
// 2. IN-APP CAMERA — CameraPicker below. UIImagePickerController with
//    sourceType .camera, presented as a sheet inside Siaga. The user
//    never leaves the app, never opens the Photos app. This is the real
//    emergency path: photograph the actual injury / bottle / card.
//
// SYSTEM IMAGES (SF Symbols) — the third option, and the honest limit:
// Image(systemName:) / UIImage(systemName:) is perfect for UI icons,
// and for a fallback when a bundled asset is missing (see load() below).
// It is NOT a substitute for a real photo: a "bandage" symbol carries no
// medical detail, and the model describing it can only say "a bandage
// icon". So system images are used for the button icons and as a
// never-crash fallback, never as the analysed image itself.

enum SamplePhoto: String, CaseIterable, Identifiable {
    case medication = "sample-medication"
    case allergyCard = "sample-allergy-card"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .medication: return "Medication label"
        case .allergyCard: return "Allergy card"
        }
    }

    var systemImage: String {
        switch self {
        case .medication: return "pills.fill"
        case .allergyCard: return "exclamationmark.triangle.fill"
        }
    }

    var note: String {
        // No fixed patient name. The person is resolved from the profile
        // the user selected on the note screen, not from the image.
        switch self {
        case .medication: return "My mother takes this medication. She fell in the bathroom, she is bleeding from her head, she is awake but dizzy."
        case .allergyCard: return "My mother fell in the bathroom, she is bleeding from her head, she is awake but dizzy. She has an allergy, see the card."
        }
    }

    /// Bundled asset first, system image only as a fallback so the flow
    /// never crashes if the PNGs were not added to the target.
    func load() -> UIImage? {
        if let bundled = UIImage(named: rawValue) { return bundled }
        return UIImage(systemName: systemImage)
    }
}

// MARK: - In-app camera (no Photos app, no library picker)

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
