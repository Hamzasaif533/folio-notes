import Foundation
import PencilKit
import SwiftUI

/// Keeps folders and notebooks on disk in Documents/Folio.
/// Each page's ink is stored as its own PencilKit drawing file.
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
    }

    private func persist() {
        let index = Index(folders: folders, notebooks: notebooks)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: Queries

    func notebooks(in folderId: UUID?, sort: SortOrder = .modified) -> [Notebook] {
        sorted(notebooks.filter { $0.folderId == folderId }, by: sort)
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
    func createFolder(name: String, colorIndex: Int, icon: String) -> Folder {
        let f = Folder(name: name.isEmpty ? "New Folder" : name, colorIndex: colorIndex, icon: icon)
        folders.append(f)
        persist()
        return f
    }

    func updateFolder(_ folder: Folder) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[i] = folder
        persist()
    }

    func deleteFolder(_ id: UUID, deleteNotebooks: Bool) {
        if deleteNotebooks {
            for nb in notebooks where nb.folderId == id { removeNotebookFiles(nb.id) }
            notebooks.removeAll { $0.folderId == id }
        } else {
            for i in notebooks.indices where notebooks[i].folderId == id { notebooks[i].folderId = nil }
        }
        folders.removeAll { $0.id == id }
        persist()
    }

    // MARK: Notebooks

    @discardableResult
    func createNotebook(title: String, folderId: UUID?, cover: CoverStyle,
                        template: PageTemplate, paper: PaperColor) -> Notebook {
        let nb = Notebook(title: title.isEmpty ? "Untitled" : title, folderId: folderId,
                          cover: cover, template: template, paper: paper, pages: [UUID()])
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
        for (old, new) in zip(src.pages, copy.pages) {
            saveDrawing(loadDrawing(notebookId: src.id, pageId: old), notebookId: copy.id, pageId: new)
        }
        notebooks.append(copy)
        persist()
    }

    // MARK: Pages

    private func notebookDir(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func removeNotebookFiles(_ id: UUID) {
        try? FileManager.default.removeItem(at: notebookDir(id))
    }

    func pageURL(notebookId: UUID, pageId: UUID) -> URL {
        notebookDir(notebookId).appendingPathComponent(pageId.uuidString + ".drawing")
    }

    func loadDrawing(notebookId: UUID, pageId: UUID) -> PKDrawing {
        let url = pageURL(notebookId: notebookId, pageId: pageId)
        guard let data = try? Data(contentsOf: url),
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    func saveDrawing(_ drawing: PKDrawing, notebookId: UUID, pageId: UUID) {
        let url = pageURL(notebookId: notebookId, pageId: pageId)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? drawing.dataRepresentation().write(to: url, options: .atomic)
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
        notebooks[i].modifiedAt = Date()
        try? FileManager.default.removeItem(at: pageURL(notebookId: notebookId, pageId: pageId))
        persist()
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
}
