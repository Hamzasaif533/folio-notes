import SwiftUI
import UIKit
import VisionKit
import PDFKit
import UniformTypeIdentifiers
import WebKit

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
    static let wordTypes: [UTType] = ["org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc"]
        .compactMap { UTType($0) } + [.rtf]
    static let slideTypes: [UTType] = ["org.openxmlformats.presentationml.presentation", "com.microsoft.powerpoint.ppt"]
        .compactMap { UTType($0) }
    static let types: [UTType] = [.pdf, .image] + wordTypes + slideTypes

    static func isPDF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .pdf) ?? false
    }

    /// Runs `work` while the picked file can be read.
    static func withAccess<T>(to url: URL, _ work: () -> T) -> T {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return work()
    }

    /// Every page of a PDF, Word document or PowerPoint (or a single image), as page backgrounds.
    @MainActor
    static func pages(from url: URL) async -> [UIImage] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if let type, wordTypes.contains(where: { type.conforms(to: $0) }) {
            return await OfficeRenderer.pages(of: url, landscape: false)
        }
        if let type, slideTypes.contains(where: { type.conforms(to: $0) }) {
            return await OfficeRenderer.pages(of: url, landscape: true)
        }
        if let doc = PDFDocument(url: url) {
            var out: [UIImage] = []
            let target = CGSize(width: TemplateRenderer.pageSize.width * 2, height: TemplateRenderer.pageSize.height * 2)
            for i in 0..<min(doc.pageCount, 300) {
                guard let page = doc.page(at: i) else { continue }
                let box = page.bounds(for: .mediaBox)
                let s = min(target.width / max(box.width, 1), target.height / max(box.height, 1))
                let size = CGSize(width: box.width * s, height: box.height * s)
                out.append(page.thumbnail(of: size, for: .mediaBox))
                if i % 10 == 9 { await Task.yield() }
            }
            return out
        }
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            return [img]
        }
        return []
    }
}

/// Word and PowerPoint files: iOS's own document viewer (WebKit) lays them out, then they're
/// printed page by page into pictures. Folio only writes on top; the file itself isn't edited.
@MainActor
final class OfficeRenderer: NSObject, WKNavigationDelegate {
    private var done: CheckedContinuation<Bool, Never>?
    private static var active: Set<OfficeRenderer> = []

    static func pages(of url: URL, landscape: Bool) async -> [UIImage] {
        // A private copy, so the web view can read it after the picker's access ends.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent(url.lastPathComponent)
        defer { try? FileManager.default.removeItem(at: dir) }
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return [] }

        let r = OfficeRenderer()
        active.insert(r)
        defer { active.remove(r) }
        // A4 in points, turned sideways for slides.
        let paper = landscape ? CGSize(width: 842, height: 595) : CGSize(width: 595, height: 842)
        let web = WKWebView(frame: CGRect(origin: .zero, size: paper))
        web.navigationDelegate = r
        // Laid out behind the app's own views (some layouts only happen inside a window).
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        web.alpha = 0.01
        window?.insertSubview(web, at: 0)
        defer { web.removeFromSuperview() }
        let loaded = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            r.done = c
            web.loadFileURL(copy, allowingReadAccessTo: dir)
        }
        guard loaded else { return [] }
        // Give the viewer a moment to lay the document out.
        try? await Task.sleep(nanoseconds: 700_000_000)

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        let rect = CGRect(origin: .zero, size: paper)
        renderer.setValue(NSValue(cgRect: rect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: rect), forKey: "printableRect")
        let count = min(renderer.numberOfPages, 300)
        guard count > 0 else { return [] }
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: count))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.5
        format.opaque = true
        var out: [UIImage] = []
        for i in 0..<count {
            out.append(UIGraphicsImageRenderer(size: paper, format: format).image { ctx in
                UIColor.white.setFill()
                ctx.fill(rect)
                renderer.drawPage(at: i, in: rect)
            })
            if i % 5 == 4 { await Task.yield() }
        }
        return out
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    private func finish(_ ok: Bool) {
        done?.resume(returning: ok)
        done = nil
    }
}
