import SwiftUI
import UIKit

/// Селфи с отметки, открытое крупно.
struct ShiftPhoto: Identifiable {
    let url: URL
    let fio: String
    var id: String { url.absoluteString }
}

/// Просмотр снимка с площадки на весь экран.
struct ShiftPhotoView: View {
    let photo: ShiftPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Spacing.s) {
                Spacer()
                CachedAsyncImage(url: photo.url) { $0.resizable().scaledToFit() } placeholder: {
                    ProgressView().tint(.white)
                }
                Text(photo.fio).font(Typography.callout).foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
            .padding(Spacing.m)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.white.opacity(0.9))
                    .padding(Spacing.m)
            }
        }
    }
}

/// Камера для селфи при отметке смены.
///
/// Снимок обязателен: геопозицию в телефоне подменяют в два касания, а фото на
/// фоне смонтированной площадки — нет. Поэтому именно камера, а не выбор из
/// галереи: из галереи прислали бы прошлогодний кадр.
///
/// Открываем фронтальную камеру — «селфи с площадки»; переключиться на основную
/// человек может сам, сервер снимок не разглядывает.
struct CheckinCamera: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // На симуляторе камеры нет — там открывается галерея, иначе экран пустой.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        if picker.sourceType == .camera {
            picker.cameraDevice = UIImagePickerController.isCameraDeviceAvailable(.front) ? .front : .rear
        }
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CheckinCamera

        init(_ parent: CheckinCamera) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
