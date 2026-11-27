import SwiftUI

enum SidebarItem: Hashable {
    case all, starred, unfiled, trash, folders
    case folder(UUID)
}

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var tools: ToolState
    @State private var selection: SidebarItem = .all
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var openNotebook: Notebook?
    @State private var notebookSheet: NotebookSheetMode?
    @State private var folderSheet: FolderSheetMode?
    @State private var deletingFolder: Folder?
    @State private var didRunDemo = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(selection: $selection,
                        onNewFolder: { folderSheet = .create },
                        onEditFolder: { folderSheet = .edit($0) },
                        onDeleteFolder: { deletingFolder = $0 })
                .navigationSplitViewColumnWidth(min: 290, ideal: 320, max: 360)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            NavigationStack {
                NotesGridView(selection: $selection,
                              onOpen: open,
                              onNewNotebook: { notebookSheet = .create(folderId: $0) },
                              onNewFolder: { folderSheet = .create },
                              onEditNotebook: { notebookSheet = .edit($0) },
                              onEditFolder: { folderSheet = .edit($0) },
                              onDeleteFolder: { deletingFolder = $0 })
            }
        }
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(item: $openNotebook) { nb in
            EditorView(notebook: nb)
                .environmentObject(store)
                .environmentObject(tools)
        }
        .sheet(item: $notebookSheet) { mode in
            NotebookSheet(mode: mode) { nb in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { open(nb) }
            }
            .environmentObject(store)
        }
        .sheet(item: $folderSheet) { mode in
            FolderSheet(mode: mode).environmentObject(store)
        }
        .confirmationDialog("Delete folder “\(deletingFolder?.name ?? "")”?",
                            isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Folder, Keep Notebooks") {
                if let f = deletingFolder { removeFolder(f, notebooks: false) }
            }
            Button("Delete Folder, Move Notebooks to Trash", role: .destructive) {
                if let f = deletingFolder { removeFolder(f, notebooks: true) }
            }
        }
        .onAppear(perform: runDemoIfNeeded)
    }

    private func open(_ nb: Notebook) {
        openNotebook = store.notebook(nb.id) ?? nb
    }

    private func removeFolder(_ f: Folder, notebooks: Bool) {
        if selection == .folder(f.id) { selection = .all }
        store.deleteFolder(f.id, deleteNotebooks: notebooks)
        deletingFolder = nil
    }

    private func runDemoIfNeeded() {
        guard !didRunDemo, DemoMode.enabled else { return }
        didRunDemo = true
        DemoMode.seedIfNeeded(store)
        if DemoMode.showFolders { selection = .folders }
        if DemoMode.openFirst, let first = store.activeNotebooks.first(where: { $0.title == DemoMode.firstTitle }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open(first) }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selection: SidebarItem
    let onNewFolder: () -> Void
    let onEditFolder: (Folder) -> Void
    let onDeleteFolder: (Folder) -> Void
    @State private var foldersExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Folio")
                    .font(.system(size: 38, weight: .regular, design: .serif))
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .padding(.leading, 4)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    tile(.all, title: "All Notes", icon: "house", tint: .primary, count: store.activeNotebooks.count)
                    tile(.starred, title: "Starred", icon: "star", tint: .yellow, count: store.starredNotebooks.count)
                    tile(.unfiled, title: "Unfiled", icon: "tray", tint: Theme.action, count: store.unfiledNotebooks.count)
                    tile(.trash, title: "Trash", icon: "trash", tint: .secondary, count: store.trashedNotebooks.count)
                }

                HStack(spacing: 14) {
                    Button { selection = .folders } label: {
                        Text("Folders")
                            .font(.system(size: 25, weight: .regular, design: .serif))
                            .foregroundStyle(selection == .folders ? Theme.accent : Color.primary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(action: onNewFolder) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Folder")
                    Button {
                        withAnimation(.snappy) { foldersExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .rotationEffect(.degrees(foldersExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 22)
                .padding(.horizontal, 4)

                if foldersExpanded {
                    if store.folders.isEmpty {
                        Button(action: onNewFolder) {
                            Label("Create a folder", systemImage: "plus")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(store.folders) { f in
                        folderRow(f)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Theme.sidebarPanel.ignoresSafeArea())
    }

    private func tile(_ item: SidebarItem, title: String, icon: String, tint: Color, count: Int) -> some View {
        let selected = selection == item
        return Button { selection = item } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(selected ? Color.white : tint)
                    Spacer()
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 16, weight: .medium).monospacedDigit())
                            .foregroundStyle(selected ? Color.white : Color.secondary)
                    }
                }
                Spacer(minLength: 16)
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? Theme.accent : Theme.tileFill))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func folderRow(_ f: Folder) -> some View {
        let selected = selection == .folder(f.id)
        let color = Color(hex: Theme.folderColors[abs(f.colorIndex) % Theme.folderColors.count])
        return Button { selection = .folder(f.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: f.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
                Text(f.name)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text("\(store.notebooks(in: f.id).count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.22) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onEditFolder(f) } label: { Label("Edit Folder", systemImage: "pencil") }
            Button(role: .destructive) { onDeleteFolder(f) } label: { Label("Delete Folder", systemImage: "trash") }
        }
    }
}

// MARK: - Notes grid

struct NotesGridView: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selection: SidebarItem
    let onOpen: (Notebook) -> Void
    let onNewNotebook: (UUID?) -> Void
    let onNewFolder: () -> Void
    let onEditNotebook: (Notebook) -> Void
    let onEditFolder: (Folder) -> Void
    let onDeleteFolder: (Folder) -> Void

    @AppStorage("folio.sort") private var sortRaw: String = SortOrder.modified.rawValue
    @State private var query = ""
    @State private var renaming: Notebook?
    @State private var renameText = ""
    @State private var deletingForever: Notebook?
    @State private var confirmEmptyTrash = false

    private var sort: SortOrder { SortOrder(rawValue: sortRaw) ?? .modified }

    private var title: String {
        switch selection {
        case .all: return "All Notes"
        case .starred: return "Starred"
        case .unfiled: return "Unfiled"
        case .trash: return "Trash"
        case .folders: return "Folders"
        case .folder(let id): return store.folder(id)?.name ?? "Folder"
        }
    }

    private var items: [Notebook] {
        let base: [Notebook]
        switch selection {
        case .all, .folders: base = store.activeNotebooks
        case .starred: base = store.starredNotebooks
        case .unfiled: base = store.unfiledNotebooks
        case .trash: base = store.trashedNotebooks
        case .folder(let id): base = store.notebooks(in: id)
        }
        let filtered = query.isEmpty ? base : base.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return store.sorted(filtered, by: sort)
    }

    private var currentFolderId: UUID? {
        if case .folder(let id) = selection { return id }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(title)
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .lineLimit(1)
                    .padding(.top, 2)

                if selection == .folders && query.isEmpty {
                    foldersGrid
                } else if items.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 196), spacing: 30)],
                              alignment: .leading, spacing: 36) {
                        ForEach(items) { nb in
                            Button {
                                if !nb.isTrashed { onOpen(nb) }
                            } label: {
                                NotebookTile(notebook: nb)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { menu(for: nb) }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.libraryBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search notes")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selection == .trash {
                    Button("Empty Trash", role: .destructive) { confirmEmptyTrash = true }
                        .disabled(store.trashedNotebooks.isEmpty)
                } else {
                    Menu {
                        Button { onNewNotebook(currentFolderId) } label: {
                            Label("New Notebook", systemImage: "book.closed")
                        }
                        Button(action: onNewFolder) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("New", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.action)
                }
                Menu {
                    Picker("Sort By", selection: $sortRaw) {
                        ForEach(SortOrder.allCases) { s in Text(s.title).tag(s.rawValue) }
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis")
                }
            }
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
        .confirmationDialog("Delete “\(deletingForever?.title ?? "")” forever?",
                            isPresented: Binding(get: { deletingForever != nil }, set: { if !$0 { deletingForever = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Forever", role: .destructive) {
                if let nb = deletingForever { store.deleteNotebook(nb.id) }
                deletingForever = nil
            }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog("Empty the trash?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
            Button("Delete \(store.trashedNotebooks.count) Notebooks Forever", role: .destructive) {
                store.emptyTrash()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var foldersGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 28)],
                  alignment: .leading, spacing: 30) {
            ForEach(store.folders) { f in
                Button { selection = .folder(f.id) } label: {
                    FolderCard(folder: f, notebooks: store.notebooks(in: f.id))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { onEditFolder(f) } label: { Label("Edit Folder", systemImage: "pencil") }
                    Button(role: .destructive) { onDeleteFolder(f) } label: { Label("Delete Folder", systemImage: "trash") }
                }
            }
            Button(action: onNewFolder) {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 34, weight: .light))
                    Text("New Folder").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Theme.action)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.action.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: selection == .trash ? "trash" : (selection == .starred ? "star" : "book.closed"))
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyText)
                .font(.headline)
                .foregroundStyle(.secondary)
            if selection != .trash && selection != .starred && query.isEmpty {
                Button {
                    onNewNotebook(currentFolderId)
                } label: {
                    Label("New Notebook", systemImage: "plus").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var emptyText: String {
        if !query.isEmpty { return "No notes match “\(query)”" }
        switch selection {
        case .trash: return "Trash is empty"
        case .starred: return "Star a notebook to see it here"
        default: return "No notebooks yet"
        }
    }

    @ViewBuilder
    private func menu(for nb: Notebook) -> some View {
        if nb.isTrashed {
            Button { store.restore(nb.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { deletingForever = nb } label: { Label("Delete Forever", systemImage: "trash") }
        } else {
            Button { store.setStarred(nb.id, !nb.isStarred) } label: {
                Label(nb.isStarred ? "Unstar" : "Star", systemImage: nb.isStarred ? "star.slash" : "star")
            }
            Button {
                renameText = nb.title
                renaming = nb
            } label: { Label("Rename", systemImage: "pencil") }
            Button { onEditNotebook(nb) } label: { Label("Cover & Paper", systemImage: "paintpalette") }
            Menu {
                Button("Unfiled") { store.moveNotebook(nb.id, to: nil) }
                ForEach(store.folders) { f in
                    Button(f.name) { store.moveNotebook(nb.id, to: f.id) }
                }
            } label: { Label("Move to Folder", systemImage: "folder") }
            Button { store.duplicateNotebook(nb.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive) { store.moveToTrash(nb.id) } label: { Label("Move to Trash", systemImage: "trash") }
        }
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
