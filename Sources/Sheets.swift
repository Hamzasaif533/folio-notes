import SwiftUI
import PhotosUI

enum NotebookSheetMode: Identifiable {
    case create(folderId: UUID?, kind: NotebookKind)
    case edit(Notebook)
    var id: String {
        switch self {
        case .create(_, let kind): return "create-\(kind.rawValue)"
        case .edit(let nb): return nb.id.uuidString
        }
    }
}

/// Create a notebook, or change an existing notebook's cover and paper.
struct NotebookSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let mode: NotebookSheetMode
    var onCreate: (Notebook) -> Void = { _ in }

    @State private var title = ""
    @State private var cover = CoverStyle(paletteIndex: Int.random(in: 0..<Theme.coverPalettes.count), pattern: .plain)
    @State private var template: PageTemplate = .ruled
    @State private var paper: PaperColor = .white
    @State private var spacing: Double = 1
    @State private var format = PageFormat.standard
    @State private var darkPages = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoToEdit: EditablePhoto?
    @State private var loaded = false

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isCanvas: Bool {
        switch mode {
        case .create(_, let kind): return kind == .canvas
        case .edit(let nb): return (store.notebook(nb.id) ?? nb).isCanvas
        }
    }

    private var templates: [PageTemplate] {
        isCanvas ? [.blank, .grid, .dotted, .ruled] : PageTemplate.allCases
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .center, spacing: 26) {
                        NotebookCoverView(cover: cover, title: title.isEmpty ? "Untitled" : title)
                            .frame(width: 150, height: 197)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 2, y: 5)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Title").font(.caption).foregroundStyle(.secondary)
                            TextField("Untitled", text: $title)
                                .font(.title3)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    SectionTitle(text: "Cover")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 14) {
                        ForEach(0..<Theme.coverPalettes.count, id: \.self) { i in
                            Button {
                                cover.paletteIndex = i
                                cover.customHex = nil
                                cover.photo = nil
                            } label: {
                                NotebookCoverView(cover: CoverStyle(paletteIndex: i, pattern: cover.pattern))
                                    .aspectRatio(0.76, contentMode: .fit)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Theme.accent, lineWidth: isPalette(i) ? 3 : 0)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 12) {
                        ColorPicker(selection: Binding(
                            get: { Color(hex: cover.customHex ?? cover.colors.0) },
                            set: { c in
                                cover.customHex = UIColor(c).hexString
                                cover.photo = nil
                            }), supportsOpacity: false) {
                            Label("Custom Colour", systemImage: "paintpalette")
                                .font(.subheadline.weight(.medium))
                        }
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Capsule().fill(cover.customHex != nil && cover.photo == nil
                                                   ? Theme.accent.opacity(0.18) : Color.secondary.opacity(0.12)))
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(cover.photo == nil ? "Photo from Gallery" : "Change Photo", systemImage: "photo")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(Capsule().fill(cover.photo != nil ? Theme.accent.opacity(0.18)
                                                                              : Color.secondary.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        if cover.photo != nil {
                            Button(role: .destructive) { cover.photo = nil } label: {
                                Label("Remove Photo", systemImage: "xmark.circle")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(CoverPattern.allCases) { p in
                            Button { cover.pattern = p } label: {
                                Text(p.title)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(cover.pattern == p ? Theme.accent : Color.secondary.opacity(0.12)))
                                    .foregroundStyle(cover.pattern == p ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SectionTitle(text: "Paper Color")
                    HStack(spacing: 14) {
                        ForEach(PaperColor.allCases) { p in
                            Button { paper = p } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(uiColor: p.uiColor))
                                        .frame(width: 38, height: 38)
                                        .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                                        .overlay(Circle().stroke(Theme.accent, lineWidth: paper == p ? 3 : 0).padding(-4))
                                    Text(p.title).font(.caption2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SectionTitle(text: isCanvas ? "Background" : "Page Template")
                    if isCanvas {
                        Label("An endless whiteboard: scroll and zoom out as far as you like.", systemImage: "infinity")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 6), spacing: 18) {
                        ForEach(templates) { t in
                            Button { withAnimation(.snappy) { template = t } } label: {
                                VStack(spacing: 6) {
                                    TemplateThumbnail(template: t, paper: paper, spacing: spacing)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Theme.accent, lineWidth: template == t ? 3 : 0)
                                        }
                                    Text(t.title).font(.caption2).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if template != .blank {
                        SectionTitle(text: "Line Spacing")
                        LineSpacingControl(spacing: $spacing)
                    }
                    if isEdit {
                        Text("Paper, template and line spacing changes apply to every page in this notebook.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !isCanvas {
                        SectionTitle(text: "Page Size")
                        PageSizePicker(format: $format)
                        if isEdit {
                            Text("A new page size is used for pages you add from now on. Pages you already have keep their size.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Toggle(isOn: $darkPages) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dark Imported Pages").font(.subheadline.weight(.semibold))
                                Text("Show PDFs and pictures you import with dark paper and light text. Exports stay as they are.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: 520)
                    }
                }
                .padding(26)
            }
            .navigationTitle(isEdit ? "Cover & Paper" : (isCanvas ? "New Canvas" : "New Notebook"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Save" : "Create") { commit() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await MainActor.run { photoToEdit = EditablePhoto(image: img.scaledDown(maxSide: 2400)) }
                    }
                    await MainActor.run { photoItem = nil }
                }
            }
            .fullScreenCover(item: $photoToEdit) { p in
                CoverPhotoEditor(image: p.image, onDone: { img in
                    if let name = CoverPhotos.save(img) { cover.photo = name }
                    photoToEdit = nil
                }, onCancel: { photoToEdit = nil })
            }
        }
    }

    private func isPalette(_ i: Int) -> Bool {
        cover.paletteIndex == i && cover.customHex == nil && cover.photo == nil
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if case .edit(let nb) = mode {
            let current = store.notebook(nb.id) ?? nb
            title = current.title
            cover = current.cover
            template = current.template
            paper = current.paper
            spacing = current.lineSpacing ?? 1
            format = current.pageFormat ?? .standard
            darkPages = current.isDarkPages
        } else if isCanvas {
            template = .dotted
        }
    }

    private func commit() {
        switch mode {
        case .create(let folderId, let kind):
            let nb = store.createNotebook(title: title, folderId: folderId, cover: cover,
                                          template: template, paper: paper, kind: kind,
                                          format: format, lineSpacing: spacing)
            if darkPages, var made = store.notebook(nb.id) {
                made.darkPages = true
                store.updateNotebook(made)
            }
            dismiss()
            onCreate(nb)
        case .edit(let original):
            guard var nb = store.notebook(original.id) else { dismiss(); return }
            nb.title = title.isEmpty ? "Untitled" : title
            nb.cover = cover
            nb.template = template
            nb.paper = paper
            nb.lineSpacing = abs(spacing - 1) < 0.001 ? nil : spacing
            if !nb.isCanvas {
                nb.pageFormat = format == .standard ? nil : format
                nb.darkPages = darkPages ? true : nil
            }
            store.updateNotebook(nb)
            dismiss()
        }
    }
}

/// A picked photo waiting to be fitted to the cover.
struct EditablePhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum FolderSheetMode: Identifiable {
    /// A new folder, optionally inside another one.
    case create(parent: UUID?)
    case edit(Folder)
    var id: String {
        switch self {
        case .create(let p): return "create-\(p?.uuidString ?? "top")"
        case .edit(let f): return f.id.uuidString
        }
    }
}

struct FolderSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let mode: FolderSheetMode

    @State private var name = ""
    @State private var colorIndex = 0
    @State private var icon = "folder.fill"
    @State private var parentId: UUID?
    @State private var loaded = false

    /// Folders this one may go inside (not itself or its own subfolders).
    private var parentChoices: [(folder: Folder, depth: Int)] {
        var blocked = Set<UUID>()
        if case .edit(let f) = mode { blocked = store.descendants(of: f.id).union([f.id]) }
        return store.folderTree().filter { !blocked.contains($0.folder.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        FolderCard(folder: Folder(name: name.isEmpty ? "New Folder" : name, colorIndex: colorIndex, icon: icon),
                                   notebooks: [])
                            .frame(width: 220)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("Folder name", text: $name)
                }
                Section("Inside") {
                    Picker("Location", selection: $parentId) {
                        Label("Top Level", systemImage: "square.stack.3d.up").tag(UUID?.none)
                        ForEach(parentChoices, id: \.folder.id) { item in
                            Text(String(repeating: "    ", count: item.depth) + item.folder.name)
                                .tag(UUID?.some(item.folder.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(0..<Theme.folderColors.count, id: \.self) { i in
                            Circle()
                                .fill(Color(hex: Theme.folderColors[i]))
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.primary, lineWidth: colorIndex == i ? 2.5 : 0).padding(-4))
                                .onTapGesture { colorIndex = i }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 14) {
                        ForEach(Theme.folderIcons, id: \.self) { s in
                            Image(systemName: s)
                                .font(.system(size: 20))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(icon == s ? Color(hex: Theme.folderColors[colorIndex]).opacity(0.25) : Color.clear))
                                .onTapGesture { icon = s }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(isEdit ? "Edit Folder" : "New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Save" : "Create") { commit() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                switch mode {
                case .edit(let f):
                    name = f.name
                    colorIndex = f.colorIndex
                    icon = f.icon
                    parentId = f.parentId
                case .create(let parent):
                    colorIndex = store.folders.count % Theme.folderColors.count
                    parentId = parent
                }
            }
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func commit() {
        switch mode {
        case .create:
            store.createFolder(name: name, colorIndex: colorIndex, icon: icon, parentId: parentId)
        case .edit(let f):
            var updated = store.folder(f.id) ?? f
            updated.name = name.isEmpty ? f.name : name
            updated.colorIndex = colorIndex
            updated.icon = icon
            updated.parentId = parentId
            store.updateFolder(updated)
        }
        dismiss()
    }
}
