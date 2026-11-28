import Foundation

/// Files that come inside the app (the "BundledFiles" folder; empty in the normal build).
/// On first launch each one becomes a notebook, in folders matching the folders on disk.
/// PDFs are shown straight from the app, so they don't take up space twice.
/// Files already added are remembered, so a notebook you delete doesn't come back,
/// and a newer build with more files adds only the new ones.
@MainActor
enum BundledLibrary {
    private static let foldersKey = "folio.bundled.folders"   // relative folder path → folder id
    private static let filesKey = "folio.bundled.files"       // relative file paths already added
    private static var running = false

    static var root: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let dir = res.appendingPathComponent("BundledFiles", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Bundled files not added yet, sorted by path. Paths are relative to the app's resources.
    static func pendingFiles() -> [String] {
        guard let root, let res = Bundle.main.resourceURL else { return [] }
        let done = Set(UserDefaults.standard.stringArray(forKey: filesKey) ?? [])
        let base = res.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  ImportInbox.isSupported(url) else { continue }
            var rel = url.standardizedFileURL.path
            if rel.hasPrefix(base) { rel.removeFirst(base.count) }
            while rel.hasPrefix("/") { rel.removeFirst() }
            if !done.contains(rel) { out.append(rel) }
        }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Adds whatever hasn't been added yet. `progress` gets text like "course files (3 of 40)".
    static func importIfNeeded(store: LibraryStore, progress: (String?) -> Void) async {
        guard !running else { return }
        let files = pendingFiles()
        guard !files.isEmpty else { return }
        running = true
        defer { running = false; progress(nil) }

        let defaults = UserDefaults.standard
        var folderIds = (defaults.dictionary(forKey: foldersKey) as? [String: String]) ?? [:]
        var done = defaults.stringArray(forKey: filesKey) ?? []

        /// The library folder for a folder path like "BundledFiles/L5/MTCA5028/02 L1", made when missing.
        func folderId(for dirPath: String) -> UUID? {
            var parts = dirPath.split(separator: "/").map(String.init)
            if parts.first == "BundledFiles" { parts.removeFirst() }
            var parent: UUID?
            var path = ""
            for (depth, name) in parts.enumerated() {
                path += (path.isEmpty ? "" : "/") + name
                if let s = folderIds[path], let id = UUID(uuidString: s), store.folder(id) != nil {
                    parent = id
                    continue
                }
                let f = store.createFolder(name: name,
                                           colorIndex: depth == 0 ? 0 : (store.folders.count % Theme.folderColors.count),
                                           icon: depth == 0 ? "graduationcap.fill" : "folder.fill",
                                           parentId: parent)
                folderIds[path] = f.id.uuidString
                parent = f.id
            }
            return parent
        }

        for (k, rel) in files.enumerated() {
            progress("course files (\(k + 1) of \(files.count))")
            await Task.yield()
            let url = Bundle.main.resourceURL!.appendingPathComponent(rel)
            let title = url.deletingPathExtension().lastPathComponent
            let dir = (rel as NSString).deletingLastPathComponent
            let folder = folderId(for: dir)
            if FileImporter.isPDF(url) {
                _ = store.importBundledPDF(title: title, folderId: folder, relativePath: rel)
            } else {
                // Word and PowerPoint files are turned into pages once.
                let pages = await FileImporter.pages(from: url)
                _ = store.importNotebook(title: title, folderId: folder, pages: pages)
            }
            // Remembered even if it couldn't be read, so it isn't tried on every launch.
            done.append(rel)
            defaults.set(done, forKey: filesKey)
            defaults.set(folderIds, forKey: foldersKey)
        }
    }
}
