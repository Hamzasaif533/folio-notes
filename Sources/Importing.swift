import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Picking files

/// The iOS file picker, shown straight from UIKit. It hands back copies of the picked files
/// (no "security scoped" access needed), which is also what LiveContainer's file picker fix
/// expects. SwiftUI's file importer did nothing at all there.
final class DocumentPicker: NSObject, UIDocumentPickerDelegate {
    private static var current: DocumentPicker?
    private let onPick: ([URL]) -> Void

    private init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

    /// Returns false when there's nothing on screen to show the picker from.
    @discardableResult
    static func present(types: [UTType], multiple: Bool, onPick: @escaping ([URL]) -> Void) -> Bool {
        guard let top = UIApplication.topViewController() else { return false }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.shouldShowFileExtensions = true
        let d = DocumentPicker(onPick: onPick)
        current = d
        picker.delegate = d
        top.present(picker, animated: true)
        return true
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // Copy right away, while the picked files are certainly there.
        let local = urls.compactMap(ImportInbox.localCopy)
        let done = onPick
        Self.current = nil
        DispatchQueue.main.async { done(local) }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Self.current = nil
    }
}

extension UIApplication {
    /// The screen in front, to present from.
    static func topViewController() -> UIViewController? {
        let scenes = shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

// MARK: - Files arriving from outside

/// Files sent to Folio from other apps ("Open in Folio", the share sheet), files dropped in
/// Folio's "Import" folder in the Files app, and PDFs pasted from the clipboard.
/// Each becomes a new notebook.
final class ImportInbox: ObservableObject {
    static let shared = ImportInbox()
    @Published var pending: [URL] = []

    private static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    /// Put a PDF here with the Files app ("On My iPad › Folio › Import") and it's imported next time Folio opens.
    static var importFolder: URL {
        let d = documents.appendingPathComponent("Import", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func isSupported(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return FileImporter.types.contains { t.conforms(to: $0) }
    }

    /// A copy of the file in Folio's own temporary folder (so it stays readable).
    static func localCopy(_ url: URL) -> URL? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolioImport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = url.lastPathComponent.isEmpty ? "Imported.pdf" : url.lastPathComponent
        let dst = dir.appendingPathComponent(name)
        if (try? FileManager.default.copyItem(at: url, to: dst)) != nil { return dst }
        // Some providers only allow reading the data.
        var coordError: NSError?
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { u in
            if let data = try? Data(contentsOf: u), (try? data.write(to: dst)) != nil { copied = true }
        }
        return copied ? dst : nil
    }

    /// "Open in Folio" / share sheet.
    func receive(_ url: URL) {
        guard url.isFileURL else { return }
        if let copy = Self.localCopy(url) {
            pending.append(copy)
            // iOS leaves its own copy in Documents/Inbox; it's not needed any more.
            if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Files waiting in the Import folder (and anything iOS left in Inbox).
    func scan() {
        let fm = FileManager.default
        for dir in [Self.importFolder, Self.documents.appendingPathComponent("Inbox", isDirectory: true)] {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                          options: [.skipsHiddenFiles]) else { continue }
            for f in files where Self.isSupported(f) {
                if let copy = Self.localCopy(f) {
                    pending.append(copy)
                    try? fm.removeItem(at: f)
                }
            }
        }
    }

    /// PDFs (or pictures) copied with the share sheet's "Copy", or a file copied in the Files app.
    static func fromClipboard() -> [URL] {
        let pb = UIPasteboard.general
        var out: [URL] = []
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolioImport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, item) in pb.items.enumerated() {
            let n = pb.items.count > 1 ? " \(i + 1)" : ""
            if let fileURL = item.values.compactMap({ $0 as? URL }).first(where: { $0.isFileURL && isSupported($0) }),
               let copy = localCopy(fileURL) {
                out.append(copy)
                continue
            }
            if let entry = item.first(where: { UTType($0.key)?.conforms(to: .pdf) ?? false }) {
                let data = (entry.value as? Data) ?? (entry.value as? String).flatMap { $0.data(using: .utf8) }
                if let data, data.starts(with: Array("%PDF".utf8)) {
                    let dst = dir.appendingPathComponent("Pasted PDF\(n).pdf")
                    if (try? data.write(to: dst)) != nil { out.append(dst); continue }
                }
            }
            if let img = item.values.compactMap({ v -> UIImage? in
                if let i = v as? UIImage { return i }
                if let d = v as? Data { return UIImage(data: d) }
                return nil
            }).first, let png = img.pngData() {
                let dst = dir.appendingPathComponent("Pasted Picture\(n).png")
                if (try? png.write(to: dst)) != nil { out.append(dst) }
            }
        }
        return out
    }
}

// MARK: - Turning a file into a notebook

@MainActor
enum ImportRunner {
    /// A PDF, Word document, PowerPoint or picture as a new notebook. Nil when it can't be read.
    static func notebook(from url: URL, folderId: UUID?, store: LibraryStore) async -> Notebook? {
        let title = url.deletingPathExtension().lastPathComponent
        // A PDF is kept as the PDF itself: sharp at any zoom and small on disk.
        if FileImporter.isPDF(url),
           let nb = FileImporter.withAccess(to: url, { store.importPDFNotebook(title: title, folderId: folderId, url: url) }) {
            return nb
        }
        let images = await FileImporter.pages(from: url)
        return store.importNotebook(title: title, folderId: folderId, pages: images)
    }

    /// Imports several files one after another. `progress` gets each file's name as it starts.
    static func notebooks(from urls: [URL], folderId: UUID?, store: LibraryStore,
                          progress: (String) -> Void) async -> (made: [Notebook], failed: [String]) {
        var made: [Notebook] = [], failed: [String] = []
        for url in urls {
            progress(url.deletingPathExtension().lastPathComponent)
            await Task.yield()
            if let nb = await notebook(from: url, folderId: folderId, store: store) {
                made.append(nb)
            } else {
                failed.append(url.lastPathComponent)
            }
            // Our temporary copy isn't needed once it's in the library.
            if url.path.contains("/FolioImport/") { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        }
        return (made, failed)
    }
}

/// What happened after importing, for the alert.
struct ImportResult: Identifiable {
    let id = UUID()
    let made: [Notebook]
    let failed: [String]

    var title: String {
        if made.isEmpty { return "Couldn't Import" }
        return made.count == 1 ? "Imported “\(made[0].title)”" : "Imported \(made.count) Files"
    }

    var message: String {
        if failed.isEmpty { return made.count == 1 ? "It's a new notebook in your library." : "Each one is a new notebook." }
        return "These couldn't be read: " + failed.joined(separator: ", ")
    }
}
