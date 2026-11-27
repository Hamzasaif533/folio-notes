import Foundation
import PencilKit
import SwiftUI

/// Keeps folders and notebooks on disk in Documents/Folio.
/// Each page's ink is stored in its own file (Folio's own ink format).
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var folders: [Folder] = []
    @Published private(set) var notebooks: [Notebook] = []

    let root: URL
    private var indexURL: URL { root.appendingPathComponent("library.json") }

    private struct Index: Codable {
        var folders: [Folder]
        var notebooks: [Notebook]
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Folio", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { return }
        folders = index.folders
        notebooks = index.notebooks
        purgeOldTrash()
    }

    private func persist() {
        let index = Index(folders: folders, notebooks: notebooks)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: Queries

    func notebooks(in folderId: UUID?, sort: SortOrder = .modified) -> [Notebook] {
        sorted(notebooks.filter { $0.folderId == folderId && !$0.isTrashed }, by: sort)
    }

    var activeNotebooks: [Notebook] { notebooks.filter { !$0.isTrashed } }
    var starredNotebooks: [Notebook] { activeNotebooks.filter { $0.isStarred } }
    var unfiledNotebooks: [Notebook] { activeNotebooks.filter { $0.folderId == nil } }
    var trashedNotebooks: [Notebook] { notebooks.filter { $0.isTrashed } }

    // MARK: Star & trash

    func setStarred(_ id: UUID, _ value: Bool) {
        guard let i = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[i].starred = value
        persist()
    }

    func moveToTrash(_ id: UUID) {
        guard let i = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[i].trashedAt = Date()
        persist()
    }

    func restore(_ id: UUID) {
        guard let i = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[i].trashedAt = nil
        if let f = notebooks[i].folderId, folder(f) == nil { notebooks[i].folderId = nil }
        persist()
    }

    func emptyTrash() {
        for nb in trashedNotebooks { removeNotebookFiles(nb.id) }
        notebooks.removeAll { $0.isTrashed }
        persist()
    }

    /// Notebooks stay in the trash for 30 days.
    private func purgeOldTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let old = notebooks.filter { ($0.trashedAt ?? .distantFuture) < cutoff }
        guard !old.isEmpty else { return }
        for nb in old { removeNotebookFiles(nb.id) }
        notebooks.removeAll { ($0.trashedAt ?? .distantFuture) < cutoff }
        persist()
    }

    func sorted(_ list: [Notebook], by sort: SortOrder) -> [Notebook] {
        switch sort {
        case .modified: return list.sorted { $0.modifiedAt > $1.modifiedAt }
        case .created: return list.sorted { $0.createdAt > $1.createdAt }
        case .title: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    func notebook(_ id: UUID) -> Notebook? { notebooks.first { $0.id == id } }
    func folder(_ id: UUID) -> Folder? { folders.first { $0.id == id } }

    // MARK: Folders

    @discardableResult
    func createFolder(name: String, colorIndex: Int, icon: String, parentId: UUID? = nil) -> Folder {
        var f = Folder(name: name.isEmpty ? "New Folder" : name, colorIndex: colorIndex, icon: icon)
        f.parentId = parentId.flatMap { folder($0) == nil ? nil : $0 }
        folders.append(f)
        persist()
        return f
    }

    func updateFolder(_ folder: Folder) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        var f = folder
        // A folder can't sit inside itself or one of its own subfolders.
        if let p = f.parentId, p == f.id || descendants(of: f.id).contains(p) { f.parentId = folders[i].parentId }
        folders[i] = f
        persist()
    }

    /// Folders directly inside `parent` (nil = top level).
    func subfolders(of parent: UUID?) -> [Folder] {
        folders.filter { $0.parentId == parent }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Every folder below this one, at any depth.
    func descendants(of id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var queue = [id]
        while let next = queue.popLast() {
            for f in folders where f.parentId == next && !result.contains(f.id) {
                result.insert(f.id)
                queue.append(f.id)
            }
        }
        return result
    }

    /// Folders in tree order with their depth, for the sidebar and pickers.
    func folderTree() -> [(folder: Folder, depth: Int)] {
        var out: [(folder: Folder, depth: Int)] = []
        func walk(_ parent: UUID?, _ depth: Int) {
            for f in subfolders(of: parent) {
                out.append((folder: f, depth: depth))
                if depth < 12 { walk(f.id, depth + 1) }
            }
        }
        walk(nil, 0)
        // Folders whose parent went missing still show up at the top level.
        let shown = Set(out.map { $0.folder.id })
        for f in folders where !shown.contains(f.id) { out.append((folder: f, depth: 0)) }
        return out
    }

    /// "University › Year 2 › Physics"
    func folderPath(_ id: UUID) -> String {
        var names: [String] = []
        var cur: UUID? = id
        var guardCount = 0
        while let c = cur, let f = folder(c), guardCount < 20 {
            names.insert(f.name, at: 0)
            cur = f.parentId
            guardCount += 1
        }
        return names.joined(separator: " › ")
    }

    func moveFolder(_ id: UUID, to parent: UUID?) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        if let p = parent, p == id || descendants(of: id).contains(p) { return }
        folders[i].parentId = parent
        persist()
    }

    /// Notebooks in this folder and all of its subfolders.
    func notebookCount(inTree id: UUID) -> Int {
        let ids = descendants(of: id).union([id])
        return activeNotebooks.filter { $0.folderId.map(ids.contains) ?? false }.count
    }

    func deleteFolder(_ id: UUID, deleteNotebooks: Bool) {
        let parent = folder(id)?.parentId
        let tree = descendants(of: id).union([id])
        for i in notebooks.indices {
            guard let f = notebooks[i].folderId, tree.contains(f) else { continue }
            if deleteNotebooks {
                notebooks[i].folderId = nil
                if notebooks[i].trashedAt == nil { notebooks[i].trashedAt = Date() }
            } else if f == id {
                notebooks[i].folderId = parent
            }
        }
        if deleteNotebooks {
            folders.removeAll { tree.contains($0.id) }
        } else {
            // Keep the subfolders: they move up one level.
            for i in folders.indices where folders[i].parentId == id { folders[i].parentId = parent }
            folders.removeAll { $0.id == id }
        }
        persist()
    }

    // MARK: Notebooks

    @discardableResult
    func createNotebook(title: String, folderId: UUID?, cover: CoverStyle,
                        template: PageTemplate, paper: PaperColor, kind: NotebookKind = .paged) -> Notebook {
        var nb = Notebook(title: title.isEmpty ? (kind == .canvas ? "Untitled Canvas" : "Untitled") : title,
                          folderId: folderId, cover: cover, template: template, paper: paper, pages: [UUID()])
        nb.kind = kind == .canvas ? .canvas : nil
        notebooks.append(nb)
        persist()
        return nb
    }

    func updateNotebook(_ nb: Notebook) {
        guard let i = notebooks.firstIndex(where: { $0.id == nb.id }) else { return }
        var copy = nb
        copy.modifiedAt = Date()
        notebooks[i] = copy
        persist()
    }

    func moveNotebook(_ id: UUID, to folderId: UUID?) {
        guard let i = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[i].folderId = folderId
        persist()
    }

    func touch(_ id: UUID) {
        guard let i = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks[i].modifiedAt = Date()
        persist()
    }

    func deleteNotebook(_ id: UUID) {
        removeNotebookFiles(id)
        notebooks.removeAll { $0.id == id }
        persist()
    }

    func duplicateNotebook(_ id: UUID) {
        guard let src = notebook(id) else { return }
        var copy = src
        copy.id = UUID()
        copy.title = src.title + " copy"
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        copy.pages = src.pages.map { _ in UUID() }
        var map: [UUID: UUID] = [:]
        for (old, new) in zip(src.pages, copy.pages) {
            map[old] = new
            copyPageFiles(from: src.id, page: old, to: copy.id, page: new)
        }
        copy.bookmarks = src.bookmarks?.compactMap { map[$0] }
        copy.outline = src.outline?.compactMap { e in map[e.pageId].map { OutlineEntry(pageId: $0, title: e.title) } }
        notebooks.append(copy)
        persist()
    }

    // MARK: Bookmarks & outline

    func toggleBookmark(notebookId: UUID, pageId: UUID) {
        guard let i = notebooks.firstIndex(where: { $0.id == notebookId }) else { return }
        var list = notebooks[i].bookmarks ?? []
        if let k = list.firstIndex(of: pageId) { list.remove(at: k) } else { list.append(pageId) }
        notebooks[i].bookmarks = list
        persist()
    }

    /// Adds, renames or (with nil) removes a page from the outline.
    func setOutline(notebookId: UUID, pageId: UUID, title: String?) {
        guard let i = notebooks.firstIndex(where: { $0.id == notebookId }) else { return }
        var list = notebooks[i].outline ?? []
        list.removeAll { $0.pageId == pageId }
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            list.append(OutlineEntry(pageId: pageId, title: title))
            let order = notebooks[i].pages
            list.sort { (order.firstIndex(of: $0.pageId) ?? 0) < (order.firstIndex(of: $1.pageId) ?? 0) }
        }
        notebooks[i].outline = list
        persist()
    }

    // MARK: Page objects & backgrounds

    private func elementsURL(_ nb: UUID, _ page: UUID) -> URL {
        notebookDir(nb).appendingPathComponent(page.uuidString + ".elements.json")
    }

    private func backgroundURL(_ nb: UUID, _ page: UUID) -> URL {
        notebookDir(nb).appendingPathComponent(page.uuidString + ".bg.jpg")
    }

    func loadElements(notebookId: UUID, pageId: UUID) -> [PageElement] {
        guard let data = try? Data(contentsOf: elementsURL(notebookId, pageId)),
              let list = try? JSONDecoder().decode([PageElement].self, from: data) else { return [] }
        return list
    }

    func saveElements(_ list: [PageElement], notebookId: UUID, pageId: UUID) {
        let url = elementsURL(notebookId, pageId)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if list.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadBackground(notebookId: UUID, pageId: UUID) -> UIImage? {
        UIImage(contentsOfFile: backgroundURL(notebookId, pageId).path)
    }

    func hasBackground(notebookId: UUID, pageId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: backgroundURL(notebookId, pageId).path)
    }

    func saveBackground(_ image: UIImage, notebookId: UUID, pageId: UUID) {
        let url = backgroundURL(notebookId, pageId)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? image.jpegData(compressionQuality: 0.86)?.write(to: url, options: .atomic)
    }

    /// Saves a photo placed on a page; returns the file name to keep in the element.
    func saveImageAsset(_ image: UIImage, notebookId: UUID) -> String? {
        let name = UUID().uuidString + ".jpg"
        let url = notebookDir(notebookId).appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let scaled = image.scaledDown(maxSide: 2200)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return name
    }

    func loadImageAsset(_ name: String, notebookId: UUID) -> UIImage? {
        UIImage(contentsOfFile: notebookDir(notebookId).appendingPathComponent(name).path)
    }

    private func copyPageFiles(from srcNb: UUID, page srcPage: UUID, to dstNb: UUID, page dstPage: UUID) {
        saveDrawing(loadDrawing(notebookId: srcNb, pageId: srcPage), notebookId: dstNb, pageId: dstPage)
        if let bg = loadBackground(notebookId: srcNb, pageId: srcPage) {
            saveBackground(bg, notebookId: dstNb, pageId: dstPage)
        }
        var elements = loadElements(notebookId: srcNb, pageId: srcPage)
        for i in elements.indices {
            elements[i].id = UUID()
            if let file = elements[i].imageFile, srcNb != dstNb,
               let img = loadImageAsset(file, notebookId: srcNb) {
                elements[i].imageFile = saveImageAsset(img, notebookId: dstNb)
            }
        }
        saveElements(elements, notebookId: dstNb, pageId: dstPage)
    }

    // MARK: Pages

    private func notebookDir(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func removeNotebookFiles(_ id: UUID) {
        try? FileManager.default.removeItem(at: notebookDir(id))
    }

    /// Folio's own ink file for a page.
    private func inkURL(_ notebookId: UUID, _ pageId: UUID) -> URL {
        notebookDir(notebookId).appendingPathComponent(pageId.uuidString + ".ink")
    }

    /// Where Folio 1.0–1.5 kept a page's ink (a PencilKit drawing).
    private func legacyDrawingURL(_ notebookId: UUID, _ pageId: UUID) -> URL {
        notebookDir(notebookId).appendingPathComponent(pageId.uuidString + ".drawing")
    }

    func loadDrawing(notebookId: UUID, pageId: UUID) -> InkDrawing {
        if let data = try? Data(contentsOf: inkURL(notebookId, pageId)), let d = InkDrawing(data: data) {
            return d
        }
        // A page written before Folio had its own pens: convert it (it is saved in the
        // new format the next time the page changes).
        if let data = try? Data(contentsOf: legacyDrawingURL(notebookId, pageId)),
           let old = try? PKDrawing(data: data) {
            return InkDrawing(pencilKit: old)
        }
        return InkDrawing()
    }

    func saveDrawing(_ drawing: InkDrawing, notebookId: UUID, pageId: UUID) {
        let url = inkURL(notebookId, pageId)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? drawing.dataRepresentation().write(to: url, options: .atomic)) != nil {
            try? fm.removeItem(at: legacyDrawingURL(notebookId, pageId))
        }
    }

    func insertPage(notebookId: UUID, at index: Int) -> UUID? {
        guard let i = notebooks.firstIndex(where: { $0.id == notebookId }) else { return nil }
        let pid = UUID()
        let at = max(0, min(index, notebooks[i].pages.count))
        notebooks[i].pages.insert(pid, at: at)
        notebooks[i].modifiedAt = Date()
        persist()
        return pid
    }

    func deletePage(notebookId: UUID, pageId: UUID) {
        guard let i = notebooks.firstIndex(where: { $0.id == notebookId }) else { return }
        notebooks[i].pages.removeAll { $0 == pageId }
        notebooks[i].bookmarks?.removeAll { $0 == pageId }
        notebooks[i].outline?.removeAll { $0.pageId == pageId }
        notebooks[i].modifiedAt = Date()
        let fm = FileManager.default
        try? fm.removeItem(at: inkURL(notebookId, pageId))
        try? fm.removeItem(at: legacyDrawingURL(notebookId, pageId))
        try? fm.removeItem(at: elementsURL(notebookId, pageId))
        try? fm.removeItem(at: backgroundURL(notebookId, pageId))
        persist()
    }

    /// Copies a page (ink, objects and background) and puts the copy right after it.
    func duplicatePage(notebookId: UUID, pageId: UUID) -> UUID? {
        guard let i = notebooks.firstIndex(where: { $0.id == notebookId }),
              let at = notebooks[i].pages.firstIndex(of: pageId) else { return nil }
        let new = UUID()
        copyPageFiles(from: notebookId, page: pageId, to: notebookId, page: new)
        notebooks[i].pages.insert(new, at: at + 1)
        if let e = notebooks[i].pageExtents?[pageId.uuidString] { notebooks[i].pageExtents?[new.uuidString] = e }
        notebooks[i].modifiedAt = Date()
        persist()
        return new
    }

    /// Adds space around pages. When space goes on the top or left, the ink and objects move
    /// with the original page so nothing shifts on the paper.
    func addSpace(notebookId: UUID, pageIds: [UUID], add: PageExtent) {
        guard let i = notebooks.firstIndex(where: { $0.id == notebookId }) else { return }
        var map = notebooks[i].pageExtents ?? [:]
        for pid in pageIds {
            map[pid.uuidString] = (map[pid.uuidString] ?? .zero) + add
            guard add.left != 0 || add.top != 0 else { continue }
            let t = CGAffineTransform(translationX: add.left, y: add.top)
            saveDrawing(loadDrawing(notebookId: notebookId, pageId: pid).transformed(using: t),
                        notebookId: notebookId, pageId: pid)
            var elements = loadElements(notebookId: notebookId, pageId: pid)
            for k in elements.indices {
                elements[k].x += add.left
                elements[k].y += add.top
            }
            saveElements(elements, notebookId: notebookId, pageId: pid)
        }
        notebooks[i].pageExtents = map
        notebooks[i].modifiedAt = Date()
        persist()
    }

    /// Pastes a copy of a page (from any notebook) into a notebook at `index`.
    func copyPage(from srcNb: UUID, pageId: UUID, into dstNb: UUID, at index: Int) -> UUID? {
        guard let i = notebooks.firstIndex(where: { $0.id == dstNb }) else { return nil }
        let new = UUID()
        copyPageFiles(from: srcNb, page: pageId, to: dstNb, page: new)
        notebooks[i].pages.insert(new, at: max(0, min(index, notebooks[i].pages.count)))
        if let e = notebook(srcNb)?.pageExtents?[pageId.uuidString] {
            var m = notebooks[i].pageExtents ?? [:]
            m[new.uuidString] = e
            notebooks[i].pageExtents = m
        }
        notebooks[i].modifiedAt = Date()
        persist()
        return new
    }

    func movePage(notebookId: UUID, from: Int, to: Int) {
        guard let i = notebooks.firstIndex(where: { $0.id == notebookId }) else { return }
        var pages = notebooks[i].pages
        guard pages.indices.contains(from) else { return }
        let p = pages.remove(at: from)
        pages.insert(p, at: max(0, min(to, pages.count)))
        notebooks[i].pages = pages
        persist()
    }

    /// Puts a notebook's pages in a new order (the same pages, rearranged).
    func setPageOrder(notebookId: UUID, pages: [UUID]) {
        guard let i = notebooks.firstIndex(where: { $0.id == notebookId }),
              pages.count == notebooks[i].pages.count, Set(pages) == Set(notebooks[i].pages) else { return }
        notebooks[i].pages = pages
        notebooks[i].modifiedAt = Date()
        persist()
    }
}
