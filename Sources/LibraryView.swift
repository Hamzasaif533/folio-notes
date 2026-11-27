import SwiftUI

enum LibraryRoute: Hashable {
    case folder(UUID)
}

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var tools: ToolState
    @State private var path = NavigationPath()
    @State private var openNotebook: Notebook?

    var body: some View {
        NavigationStack(path: $path) {
            ShelfView(folderId: nil, onOpen: open)
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .folder(let id):
                        ShelfView(folderId: id, onOpen: open)
                    }
                }
        }
        .fullScreenCover(item: $openNotebook) { nb in
            EditorView(notebook: nb)
                .environmentObject(store)
                .environmentObject(tools)
        }
    }

    private func open(_ nb: Notebook) {
        openNotebook = store.notebook(nb.id) ?? nb
    }
}

/// The shelf: folders on top (library only), then notebook covers.
struct ShelfView: View {
    @EnvironmentObject var store: LibraryStore
    let folderId: UUID?
    let onOpen: (Notebook) -> Void

    @AppStorage("folio.sort") private var sortRaw: String = SortOrder.modified.rawValue
    @State private var query = ""
    @State private var notebookSheet: NotebookSheetMode?
    @State private var folderSheet: FolderSheetMode?
    @State private var renaming: Notebook?
    @State private var renameText = ""
    @State private var deletingNotebook: Notebook?
    @State private var deletingFolder: Folder?

    private var sort: SortOrder { SortOrder(rawValue: sortRaw) ?? .modified }
    private var folder: Folder? { folderId.flatMap { store.folder($0) } }

    private var visibleNotebooks: [Notebook] {
        if !query.isEmpty {
            let base = folderId == nil ? store.notebooks : store.notebooks.filter { $0.folderId == folderId }
            return store.sorted(base.filter { $0.title.localizedCaseInsensitiveContains(query) }, by: sort)
        }
        return store.notebooks(in: folderId, sort: sort)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if folderId == nil && query.isEmpty {
                    foldersSection
                }
                notebooksSection
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
        }
        .background(Theme.shelfBackground.ignoresSafeArea())
        .navigationTitle(folder?.name ?? "Library")
        .searchable(text: $query, prompt: "Search notebooks")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sortRaw) {
                        ForEach(SortOrder.allCases) { s in
                            Text(s.title).tag(s.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                Menu {
                    Button {
                        notebookSheet = .create(folderId: folderId)
                    } label: {
                        Label("New Notebook", systemImage: "book.closed")
                    }
                    if folderId == nil {
                        Button {
                            folderSheet = .create
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $notebookSheet) { mode in
            NotebookSheet(mode: mode) { nb in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onOpen(nb) }
            }
            .environmentObject(store)
        }
        .sheet(item: $folderSheet) { mode in
            FolderSheet(mode: mode)
                .environmentObject(store)
        }
        .alert("Rename Notebook", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if var nb = renaming {
                    nb.title = renameText.isEmpty ? "Untitled" : renameText
                    store.updateNotebook(nb)
                }
                renaming = nil
            }
        }
        .confirmationDialog("Delete this notebook?",
                            isPresented: Binding(get: { deletingNotebook != nil }, set: { if !$0 { deletingNotebook = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Notebook", role: .destructive) {
                if let nb = deletingNotebook { store.deleteNotebook(nb.id) }
                deletingNotebook = nil
            }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog("Delete folder?",
                            isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Folder, Keep Notebooks") {
                if let f = deletingFolder { store.deleteFolder(f.id, deleteNotebooks: false) }
                deletingFolder = nil
            }
            Button("Delete Folder and Its Notebooks", role: .destructive) {
                if let f = deletingFolder { store.deleteFolder(f.id, deleteNotebooks: true) }
                deletingFolder = nil
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var foldersSection: some View {
        if !store.folders.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(text: "Folders")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 26)], spacing: 26) {
                    ForEach(store.folders) { f in
                        NavigationLink(value: LibraryRoute.folder(f.id)) {
                            FolderCard(folder: f, notebooks: store.notebooks(in: f.id))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { folderSheet = .edit(f) } label: { Label("Edit Folder", systemImage: "pencil") }
                            Button(role: .destructive) { deletingFolder = f } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
    }

    private var notebooksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: query.isEmpty ? "Notebooks" : "Results")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 30)], spacing: 32) {
                if query.isEmpty {
                    Button { notebookSheet = .create(folderId: folderId) } label: { NewNotebookTile() }
                        .buttonStyle(.plain)
                }
                ForEach(visibleNotebooks) { nb in
                    Button { onOpen(nb) } label: { NotebookTile(notebook: nb) }
                        .buttonStyle(.plain)
                        .contextMenu { notebookMenu(nb) }
                }
            }
        }
    }

    @ViewBuilder
    private func notebookMenu(_ nb: Notebook) -> some View {
        Button {
            renameText = nb.title
            renaming = nb
        } label: { Label("Rename", systemImage: "pencil") }
        Button { notebookSheet = .edit(nb) } label: { Label("Cover & Paper", systemImage: "paintpalette") }
        Menu {
            Button("Library (no folder)") { store.moveNotebook(nb.id, to: nil) }
            ForEach(store.folders) { f in
                Button(f.name) { store.moveNotebook(nb.id, to: f.id) }
            }
        } label: { Label("Move to", systemImage: "folder") }
        Button { store.duplicateNotebook(nb.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Divider()
        Button(role: .destructive) { deletingNotebook = nb } label: { Label("Delete", systemImage: "trash") }
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.85))
    }
}
