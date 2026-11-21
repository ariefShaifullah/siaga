import SwiftUI
import UIKit

// In-app camera — photograph the injury, bottle or card WITHOUT leaving
// the emergency flow.
//
// The question behind this file: why open PhotosPicker at all in an
// emergency? Picking from the library leaves the note screen, needs photo
// permission, and on stage it eats demo time. The in-app camera is the
// answer: UIImagePickerController with sourceType .camera, presented as
// a sheet inside Siaga. The user never leaves the app, never opens the
// Photos app. This is the real emergency path: photograph the actual
// injury / bottle / card.
//
// SYSTEM IMAGES (SF Symbols) — Image(systemName:) is perfect for UI
// icons, and for a fallback when a bundled asset is missing. It is NOT
// a substitute for a real photo: a "bandage" symbol carries no medical
// detail, and the model describing it can only say "a bandage icon". So
// system images are used for the button icons, never as the analysed
// image itself.

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
