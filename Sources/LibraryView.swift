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
    @Namespace private var zoomNS

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(selection: $selection,
                        onNewFolder: { folderSheet = .create(parent: nil) },
                        onEditFolder: { folderSheet = .edit($0) },
                        onDeleteFolder: { deletingFolder = $0 },
                        onNewSubfolder: { folderSheet = .create(parent: $0) })
                .navigationSplitViewColumnWidth(min: 290, ideal: 320, max: 360)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            NavigationStack {
                NotesGridView(selection: $selection,
                              zoomNS: zoomNS,
                              onOpen: open,
                              onNewNotebook: { notebookSheet = .create(folderId: $0, kind: $1) },
                              onQuickNote: quickNote,
                              onNewFolder: { folderSheet = .create(parent: $0) },
                              onEditNotebook: { notebookSheet = .edit($0) },
                              onEditFolder: { folderSheet = .edit($0) },
                              onDeleteFolder: { deletingFolder = $0 })
            }
        }
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(item: $openNotebook) { nb in
            // No zoom transition here: on iPadOS 18+ it lets a pinch or swipe
            // close the notebook. Only the back arrow leaves the editor.
            EditorView(notebook: nb, onSwitch: { other in switchNotebook(to: other) })
                .id(nb.id)
                .environmentObject(store)
                .environmentObject(tools)
                .interactiveDismissDisabled(true)
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

    /// From the editor's "All Notes" panel: close this notebook and open another.
    private func switchNotebook(to nb: Notebook) {
        openNotebook = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { open(nb) }
    }

    /// Creates a notebook (or canvas) with default settings and opens it straight away.
    private func quickNote(_ kind: NotebookKind) {
        var folderId: UUID?
        if case .folder(let id) = selection { folderId = id }
        let nb = store.createNotebook(title: "", folderId: folderId,
                                      cover: CoverStyle(paletteIndex: Int.random(in: 0..<Theme.coverPalettes.count), pattern: .plain),
                                      template: kind == .canvas ? .dotted : .ruled, paper: .white, kind: kind)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { open(nb) }
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
        if DemoMode.openFolder, let uni = store.folders.first(where: { $0.name == "University" }) {
            selection = .folder(uni.id)
        }
        if DemoMode.openFirst, let first = store.activeNotebooks.first(where: { $0.title == DemoMode.firstTitle }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open(first) }
        }
        if DemoMode.openCanvas, let board = store.activeNotebooks.first(where: { $0.title == DemoMode.canvasTitle }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open(board) }
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
    var onNewSubfolder: (UUID) -> Void = { _ in }
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
                    Button { withAnimation(.snappy(duration: 0.28)) { selection = .folders } } label: {
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
                    ForEach(store.folderTree(), id: \.folder.id) { item in
                        folderRow(item.folder, depth: item.depth)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.folders.map(\.id))
        }
        .scrollIndicators(.hidden)
        .background(Theme.sidebarPanel.ignoresSafeArea())
    }

    private func tile(_ item: SidebarItem, title: String, icon: String, tint: Color, count: Int) -> some View {
        let selected = selection == item
        return Button { withAnimation(.snappy(duration: 0.28)) { selection = item } } label: {
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
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    private func folderRow(_ f: Folder, depth: Int) -> some View {
        let selected = selection == .folder(f.id)
        let color = Color(hex: Theme.folderColors[abs(f.colorIndex) % Theme.folderColors.count])
        return Button { withAnimation(.snappy(duration: 0.28)) { selection = .folder(f.id) } } label: {
            HStack(spacing: 12) {
                if depth > 0 {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, CGFloat(depth - 1) * 18)
                }
                Image(systemName: f.icon)
                    .font(.system(size: depth > 0 ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: depth > 0 ? 26 : 30, height: depth > 0 ? 26 : 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
                Text(f.name)
                    .font(.system(size: depth > 0 ? 16 : 17))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text("\(store.notebookCount(inTree: f.id))")
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
            FolderMenu(store: store, folder: f, onEdit: onEditFolder, onDelete: onDeleteFolder, onNewSubfolder: onNewSubfolder)
        }
    }
}

/// Folder context menu: edit, new subfolder, move into another folder, delete.
struct FolderMenu: View {
    let store: LibraryStore
    let folder: Folder
    let onEdit: (Folder) -> Void
    let onDelete: (Folder) -> Void
    let onNewSubfolder: (UUID) -> Void

    var body: some View {
        Button { onEdit(folder) } label: { Label("Edit Folder", systemImage: "pencil") }
        Button { onNewSubfolder(folder.id) } label: { Label("New Folder Inside", systemImage: "folder.badge.plus") }
        Menu {
            let blocked = store.descendants(of: folder.id).union([folder.id])
            Button("Top Level") { store.moveFolder(folder.id, to: nil) }
            ForEach(store.folderTree().filter { !blocked.contains($0.folder.id) }, id: \.folder.id) { item in
                Button(String(repeating: "   ", count: item.depth) + item.folder.name) {
                    store.moveFolder(folder.id, to: item.folder.id)
                }
            }
        } label: { Label("Move to…", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { onDelete(folder) } label: { Label("Delete Folder", systemImage: "trash") }
    }
}

// MARK: - Notes grid

struct NotesGridView: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selection: SidebarItem
    var zoomNS: Namespace.ID? = nil
    let onOpen: (Notebook) -> Void
    let onNewNotebook: (UUID?, NotebookKind) -> Void
    let onQuickNote: (NotebookKind) -> Void
    let onNewFolder: (UUID?) -> Void
    let onEditNotebook: (Notebook) -> Void
    let onEditFolder: (Folder) -> Void
    let onDeleteFolder: (Folder) -> Void

    @AppStorage("folio.sort") private var sortRaw: String = SortOrder.modified.rawValue
    @AppStorage("folio.largeTiles") private var largeTiles = false
    @State private var showNewMenu = false
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
                VStack(alignment: .leading, spacing: 4) {
                    if let id = currentFolderId {
                        breadcrumb(id)
                    }
                    Text(title)
                        .font(.system(size: 40, weight: .regular, design: .serif))
                        .lineLimit(1)
                }
                .padding(.top, 2)

                Group {
                    if selection == .folders && query.isEmpty {
                        foldersGrid(parent: nil)
                    } else if let id = currentFolderId {
                        let hasSubfolders = !store.subfolders(of: id).isEmpty
                        if query.isEmpty {
                            foldersGrid(parent: id, compact: true)
                        }
                        if items.isEmpty {
                            if !hasSubfolders || !query.isEmpty { emptyState }
                        } else {
                            notebookGrid
                        }
                    } else if items.isEmpty {
                        emptyState
                    } else {
                        notebookGrid
                    }
                }
                .id(selection)
                .transition(.opacity.combined(with: .offset(y: 10)))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: items.map(\.id))
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: largeTiles)
        }
        .background(Theme.libraryBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selection == .trash {
                    Button("Empty Trash", role: .destructive) { confirmEmptyTrash = true }
                        .disabled(store.trashedNotebooks.isEmpty)
                } else if selection == .folders {
                    ProminentButton(title: "New Folder", systemImage: "plus") { onNewFolder(nil) }
                } else {
                    ProminentButton(title: "New", systemImage: "plus") { showNewMenu = true }
                        .popover(isPresented: $showNewMenu, arrowEdge: .top) {
                            NewMenu(onNotebook: { pick { onNewNotebook(currentFolderId, .paged) } },
                                    onCanvas: { pick { onNewNotebook(currentFolderId, .canvas) } },
                                    onFolder: { pick { onNewFolder(currentFolderId) } },
                                    onQuickNote: { pick { onQuickNote(.paged) } },
                                    onQuickCanvas: { pick { onQuickNote(.canvas) } })
                        }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sortRaw) {
                        ForEach(SortOrder.allCases) { s in Text(s.title).tag(s.rawValue) }
                    }
                    Divider()
                    Picker("Size", selection: $largeTiles) {
                        Label("Large Notebooks", systemImage: "square.grid.2x2").tag(true)
                        Label("Small Notebooks", systemImage: "square.grid.3x3").tag(false)
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis")
                }
            }
        }
        .onAppear {
            if DemoMode.showNew {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showNewMenu = true }
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

    /// Closes the New menu first, then runs the action (so sheets don't clash with the popover).
    private func pick(_ action: @escaping () -> Void) {
        showNewMenu = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
    }

    private var notebookGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: largeTiles ? 210 : 158,
                                               maximum: largeTiles ? 260 : 196), spacing: 30)],
                  alignment: .leading, spacing: 36) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, nb in
                Button {
                    if !nb.isTrashed { onOpen(nb) }
                } label: {
                    NotebookTile(notebook: nb, zoomNS: zoomNS)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .contextMenu { menu(for: nb) }
                .staggeredAppear(i)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    /// "‹ Folders › University" above a folder's title; tap a crumb to go up.
    private func breadcrumb(_ id: UUID) -> some View {
        var chain: [Folder] = []
        var cur = store.folder(id)?.parentId
        while let c = cur, let f = store.folder(c), chain.count < 12 {
            chain.insert(f, at: 0)
            cur = f.parentId
        }
        return HStack(spacing: 6) {
            Button { withAnimation(.snappy(duration: 0.28)) { selection = .folders } } label: {
                Label("Folders", systemImage: "chevron.left").font(.subheadline.weight(.medium))
            }
            ForEach(chain) { f in
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                Button(f.name) { withAnimation(.snappy(duration: 0.28)) { selection = .folder(f.id) } }
                    .font(.subheadline.weight(.medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.action)
    }

    /// Folders at one level (top level, or the subfolders of a folder).
    private func foldersGrid(parent: UUID?, compact: Bool = false) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 180 : 200, maximum: compact ? 220 : 260), spacing: 28)],
                  alignment: .leading, spacing: 30) {
            ForEach(Array(store.subfolders(of: parent).enumerated()), id: \.element.id) { i, f in
                Button { withAnimation(.snappy(duration: 0.28)) { selection = .folder(f.id) } } label: {
                    FolderCard(folder: f, notebooks: store.notebooks(in: f.id),
                               subfolders: store.subfolders(of: f.id).count,
                               total: store.notebookCount(inTree: f.id))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .contextMenu {
                    FolderMenu(store: store, folder: f, onEdit: onEditFolder, onDelete: onDeleteFolder,
                               onNewSubfolder: { onNewFolder($0) })
                }
                .staggeredAppear(i)
            }
            Button { onNewFolder(parent) } label: {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus").font(.system(size: compact ? 28 : 34, weight: .light))
                    Text(parent == nil ? "New Folder" : "New Folder Here").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Theme.action)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 130 : 170)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.action.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
            .buttonStyle(PressableStyle(scale: 0.95))
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
                    onNewNotebook(currentFolderId, .paged)
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
                ForEach(store.folderTree(), id: \.folder.id) { item in
                    Button(String(repeating: "   ", count: item.depth) + item.folder.name) {
                        store.moveNotebook(nb.id, to: item.folder.id)
                    }
                }
            } label: { Label("Move to Folder", systemImage: "folder") }
            Button { store.duplicateNotebook(nb.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive) { store.moveToTrash(nb.id) } label: { Label("Move to Trash", systemImage: "trash") }
        }
    }
}

/// The "+ New" popover: big tiles for Notebook / Canvas / Folder, then quick actions.
struct NewMenu: View {
    let onNotebook: () -> Void
    let onCanvas: () -> Void
    let onFolder: () -> Void
    let onQuickNote: () -> Void
    let onQuickCanvas: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                tile("Notebook", "book.closed", onNotebook)
                tile("Canvas", "infinity", onCanvas)
                tile("Folder", "folder.badge.plus", onFolder)
            }
            VStack(spacing: 0) {
                row("Quick Note", "square.and.pencil", onQuickNote)
                Divider().padding(.leading, 52)
                row("Quick Canvas", "scribble.variable", onQuickCanvas)
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
        }
        .padding(14)
        .frame(width: 380)
        .presentationCompactAdaptation(.popover)
        .solidPopover()
    }

    private func tile(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Theme.action)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }

    private func row(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.action)
                    .frame(width: 24)
                Text(title).font(.system(size: 17))
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Filled cyan "+ New" button (tinted Liquid Glass on iPadOS 26).
struct ProminentButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
        }
        .tint(Theme.action)
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
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
