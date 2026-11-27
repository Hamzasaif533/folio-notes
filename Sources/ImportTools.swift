import SwiftUI
import UIKit
import VisionKit
import PDFKit
import UniformTypeIdentifiers

/// Apple's document scanner: each scanned page comes back as an image.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onDone: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onDone: ([UIImage]) -> Void
        init(onDone: @escaping ([UIImage]) -> Void) { self.onDone = onDone }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onDone((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onDone([]) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onDone([]) }
    }
}

/// The camera, for "Page from Camera" and photos on the page.
struct CameraPicker: UIViewControllerRepresentable {
    let onDone: (UIImage?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = Self.isAvailable ? .camera : .photoLibrary
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void
        init(onDone: @escaping (UIImage?) -> Void) { self.onDone = onDone }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
    }
}

enum FileImporter {
    static let types: [UTType] = [.pdf, .image]

    /// PDF pages (or a single image) rendered as page backgrounds.
    static func pages(from url: URL) -> [UIImage] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let doc = PDFDocument(url: url) {
            var out: [UIImage] = []
            let target = CGSize(width: TemplateRenderer.pageSize.width * 2, height: TemplateRenderer.pageSize.height * 2)
            for i in 0..<min(doc.pageCount, 200) {
                guard let page = doc.page(at: i) else { continue }
                let box = page.bounds(for: .mediaBox)
                let s = min(target.width / max(box.width, 1), target.height / max(box.height, 1))
                let size = CGSize(width: box.width * s, height: box.height * s)
                out.append(page.thumbnail(of: size, for: .mediaBox))
            }
            return out
        }
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            return [img]
        }
        return []
    }
}
