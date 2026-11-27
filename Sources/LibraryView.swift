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
            EditorRoot(start: nb, onSwitch: { other in switchNotebook(to: other) })
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
        for (on, title) in [(DemoMode.penTest, DemoMode.penTestTitle), (DemoMode.pdfTest, DemoMode.pdfTestTitle)] where on {
            if let nb = store.activeNotebooks.first(where: { $0.title == title }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open(nb) }
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var themes: ThemeCenter
    @Binding var selection: SidebarItem
    let onNewFolder: () -> Void
    let onEditFolder: (Folder) -> Void
    let onDeleteFolder: (Folder) -> Void
    var onNewSubfolder: (UUID) -> Void = { _ in }
    @State private var foldersExpanded = true
    @AppStorage("folio.openFolders") private var openFoldersRaw = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Folio")
                        .font(.system(size: 38, weight: .regular, design: .serif))
                    Spacer()
                    Button { themes.showPicker = true } label: {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.tileFill))
                            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Themes")
                }
                .padding(.top, 14)
                .padding(.bottom, 8)
                .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    tile(.all, title: "All Notes", icon: "house", tint: .primary, count: store.activeNotebooks.count)
                    tile(.starred, title: "Starred", icon: "star", tint: .yellow, count: store.starredNotebooks.count)
                    tile(.unfiled, title: "Unfiled", icon: "tray", tint: Theme.action, count: store.unfiledNotebooks.count)
                        .libraryDropTarget(.folder(nil), store: store, cornerRadius: 18)
                    tile(.trash, title: "Trash", icon: "trash", tint: .secondary, count: store.trashedNotebooks.count)
                        .libraryDropTarget(.trash, store: store, cornerRadius: 18)
                }

                HStack(spacing: 14) {
                    Button { withAnimation(.snappy(duration: 0.28)) { selection = .folders } } label: {
                        Text("Folders")
                            .font(.system(size: 25, weight: .regular, design: .serif))
                            .foregroundStyle(selection == .folders ? Theme.accent : Color.primary)
                    }
                    .buttonStyle(.plain)
                    // Drop a folder here to take it out to the top level.
                    .libraryDropTarget(.folder(nil), store: store, cornerRadius: 10)
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
                    ForEach(visibleTree, id: \.folder.id) { item in
                        folderRow(item.folder, depth: item.depth)
                            .transition(.move(edge: .top).combined(with: .opacity))
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
            .background {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                if selected {
                    shape.fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.78)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 4)
                } else {
                    shape.fill(Theme.tileFill)
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    /// Folders whose parents are all open in the sidebar.
    private var visibleTree: [(folder: Folder, depth: Int)] {
        let open = openFolders
        return store.folderTree().filter { item in
            var p = item.folder.parentId
            var guardCount = 0
            while let id = p, guardCount < 32 {
                if !open.contains(id) { return false }
                p = store.folder(id)?.parentId
                guardCount += 1
            }
            return true
        }
    }

    private var openFolders: Set<UUID> {
        Set(openFoldersRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private func toggleOpen(_ id: UUID) {
        var s = openFolders
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        withAnimation(.easeOut(duration: 0.22)) {
            openFoldersRaw = s.map(\.uuidString).joined(separator: ",")
        }
    }

    private func folderRow(_ f: Folder, depth: Int) -> some View {
        let selected = selection == .folder(f.id)
        let color = Color(hex: Theme.folderColors[abs(f.colorIndex) % Theme.folderColors.count])
        let subs = store.subfolders(of: f.id).count
        let notes = store.notebookCount(inTree: f.id)
        let isOpen = openFolders.contains(f.id)
        var detail: [String] = []
        if subs > 0 { detail.append(subs == 1 ? "1 folder" : "\(subs) folders") }
        detail.append(notes == 1 ? "1 notebook" : "\(notes) notebooks")
        return HStack(spacing: 6) {
            // Open / close this folder's submenu.
            Button { toggleOpen(f.id) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(subs > 0 ? Color.secondary : Color.clear)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 22, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(subs == 0)

            Button { withAnimation(.snappy(duration: 0.28)) { selection = .folder(f.id) } } label: {
                HStack(spacing: 11) {
                    Image(systemName: f.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(detail.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.22) : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * 18)
        .contextMenu {
            FolderMenu(store: store, folder: f, onEdit: onEditFolder, onDelete: onDeleteFolder, onNewSubfolder: onNewSubfolder)
        }
        .draggable(LibraryDrag.payload(folder: f.id)) {
            Label(f.name, systemImage: f.icon)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.9)))
                .foregroundStyle(.white)
        }
        .libraryDropTarget(.folder(f.id), store: store, cornerRadius: 12)
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
    @State private var selecting = false
    @State private var picked: Set<UUID> = []
    @State private var confirmBulkDelete = false
    @State private var showImport = false
    @State private var importing: String?
    @State private var showSettings = false

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
                        if store.subfolders(of: nil).isEmpty { emptyState } else { foldersGrid(parent: nil) }
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
        .background(Theme.backdrop.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if selecting { selectionBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.easeOut(duration: 0.22), value: selecting)
        .onChange(of: selection) { _, _ in selecting = false; picked = [] }
        .searchable(text: $query, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selection != .folders && !items.isEmpty || selecting {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        picked = []
                    }
                    .fontWeight(selecting ? .semibold : .regular)
                }
            }
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
                                    onQuickCanvas: { pick { onQuickNote(.canvas) } },
                                    onImport: { pick { showImport = true } })
                        }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .sheet(isPresented: $showSettings) { LibrarySettingsView() }
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
            if DemoMode.selectMode {
                selecting = true
                picked = Set(items.prefix(3).map(\.id))
            }
            if DemoMode.settings {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showSettings = true }
            }
            if DemoMode.showNew {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showNewMenu = true }
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: FileImporter.types) { result in
            guard case .success(let url) = result else { return }
            importFile(url)
        }
        .overlay {
            if let importing {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Importing \(importing)…").font(.subheadline.weight(.medium))
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
                .transition(.opacity)
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

    /// A PDF, Word document or PowerPoint becomes a new notebook to write on (one page per page or slide).
    private func importFile(_ url: URL) {
        let title = url.deletingPathExtension().lastPathComponent
        withAnimation { importing = title }
        Task { @MainActor in
            // A PDF is kept as the PDF itself: sharp at any zoom and small on disk.
            if FileImporter.isPDF(url),
               let nb = FileImporter.withAccess(to: url, { store.importPDFNotebook(title: title, folderId: currentFolderId, url: url) }) {
                withAnimation { importing = nil }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onOpen(nb) }
                return
            }
            let images = await FileImporter.pages(from: url)
            withAnimation { importing = nil }
            guard let nb = store.importNotebook(title: title, folderId: currentFolderId, pages: images) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onOpen(nb) }
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
                    if selecting {
                        if picked.contains(nb.id) { picked.remove(nb.id) } else { picked.insert(nb.id) }
                    } else if !nb.isTrashed { onOpen(nb) }
                } label: {
                    NotebookTile(notebook: nb, zoomNS: zoomNS)
                        .overlay(alignment: .topLeading) {
                            if selecting { checkmark(picked.contains(nb.id)) }
                        }
                        .opacity(selecting && !picked.contains(nb.id) ? 0.75 : 1)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .contextMenu { menu(for: nb) }
                // Drag it onto a folder (while selecting, all the picked notebooks go together).
                .draggable(LibraryDrag.payload(notebooks: selecting && picked.contains(nb.id)
                                               ? items.map(\.id).filter { picked.contains($0) } : [nb.id])) {
                    NotebookTile(notebook: nb, zoomNS: nil)
                        .frame(width: 130)
                        .overlay(alignment: .topTrailing) {
                            if selecting && picked.count > 1 && picked.contains(nb.id) {
                                Text("\(picked.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Circle().fill(Theme.action))
                            }
                        }
                }
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
            .libraryDropTarget(.folder(nil), store: store, cornerRadius: 8)
            ForEach(chain) { f in
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                Button(f.name) { withAnimation(.snappy(duration: 0.28)) { selection = .folder(f.id) } }
                    .font(.subheadline.weight(.medium))
                    .libraryDropTarget(.folder(f.id), store: store, cornerRadius: 8)
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
                .draggable(LibraryDrag.payload(folder: f.id)) {
                    FolderCard(folder: f, notebooks: store.notebooks(in: f.id)).frame(width: 150)
                }
                .libraryDropTarget(.folder(f.id), store: store, cornerRadius: 22)
                .staggeredAppear(i)
            }
        }
    }
    private func checkmark(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.9), on ? Theme.action : Color.black.opacity(0.3))
            .symbolRenderingMode(.palette)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .padding(8)
    }

    /// Bottom bar while selecting notebooks: move or delete them together.
    private var selectionBar: some View {
        let ids = items.map(\.id).filter { picked.contains($0) }
        let none = ids.isEmpty
        return HStack(spacing: 18) {
            Button(picked.count == items.count && !items.isEmpty ? "Deselect All" : "Select All") {
                picked = picked.count == items.count ? [] : Set(items.map(\.id))
            }
            Text(none ? "Select notebooks" : "\(ids.count) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            if selection == .trash {
                Button { ids.forEach { store.restore($0) }; finishSelecting() } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .disabled(none)
                Button(role: .destructive) { confirmBulkDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(none)
            } else {
                Menu {
                    Button("Unfiled") { ids.forEach { store.moveNotebook($0, to: nil) }; finishSelecting() }
                    ForEach(store.folderTree(), id: \.folder.id) { item in
                        Button(String(repeating: "   ", count: item.depth) + item.folder.name) {
                            ids.forEach { store.moveNotebook($0, to: item.folder.id) }
                            finishSelecting()
                        }
                    }
                } label: {
                    Label("Move", systemImage: "folder")
                }
                .disabled(none)
                Button(role: .destructive) { ids.forEach { store.moveToTrash($0) }; finishSelecting() } label: {
                    Label("Trash", systemImage: "trash")
                }
                .disabled(none)
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.body.weight(.medium))
        .tint(Theme.action)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .glassBackground(Capsule())
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
        .confirmationDialog("Delete \(ids.count) notebooks forever?", isPresented: $confirmBulkDelete,
                            titleVisibility: .visible) {
            Button("Delete Forever", role: .destructive) {
                ids.forEach { store.deleteNotebook($0) }
                finishSelecting()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func finishSelecting() {
        withAnimation(.easeOut(duration: 0.22)) {
            picked = []
            selecting = false
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
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var emptyText: String {
        if !query.isEmpty { return "No notes match “\(query)”" }
        switch selection {
        case .trash: return "Trash is empty"
        case .starred: return "Star a notebook to see it here"
        case .folders: return "No folders"
        default: return "No notebooks"
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
    var onImport: () -> Void = {}

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
                Divider().padding(.leading, 52)
                row("Import PDF, Word or PowerPoint", "square.and.arrow.down", onImport)
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

/// App-wide settings, from the notebooks page.
struct LibrarySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("folio.lazyPages") private var lazyPages = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Load Only Nearby Pages", isOn: $lazyPages)
                } header: {
                    Text("Performance")
                } footer: {
                    Text("Only the pages around the one you're on are kept in memory, so big notebooks and PDFs open faster and use less battery. Turn it off if pages take a moment to appear when you scroll quickly. Takes effect the next time you open a notebook.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
