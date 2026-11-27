import SwiftUI

enum NotebookSheetMode: Identifiable {
    case create(folderId: UUID?)
    case edit(Notebook)
    var id: String {
        switch self {
        case .create: return "create"
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
    @State private var loaded = false

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
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
                            Button { cover.paletteIndex = i } label: {
                                NotebookCoverView(cover: CoverStyle(paletteIndex: i, pattern: cover.pattern))
                                    .aspectRatio(0.76, contentMode: .fit)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Theme.accent, lineWidth: cover.paletteIndex == i ? 3 : 0)
                                    }
                            }
                            .buttonStyle(.plain)
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

                    SectionTitle(text: "Page Template")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 6), spacing: 18) {
                        ForEach(PageTemplate.allCases) { t in
                            Button { template = t } label: {
                                VStack(spacing: 6) {
                                    TemplateThumbnail(template: t, paper: paper)
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
                    if isEdit {
                        Text("Paper and template changes apply to every page in this notebook.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(26)
            }
            .navigationTitle(isEdit ? "Cover & Paper" : "New Notebook")
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
        }
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
        }
    }

    private func commit() {
        switch mode {
        case .create(let folderId):
            let nb = store.createNotebook(title: title, folderId: folderId, cover: cover,
                                          template: template, paper: paper)
            dismiss()
            onCreate(nb)
        case .edit(let original):
            guard var nb = store.notebook(original.id) else { dismiss(); return }
            nb.title = title.isEmpty ? "Untitled" : title
            nb.cover = cover
            nb.template = template
            nb.paper = paper
            store.updateNotebook(nb)
            dismiss()
        }
    }
}

enum FolderSheetMode: Identifiable {
    case create
    case edit(Folder)
    var id: String {
        switch self {
        case .create: return "create"
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
    @State private var loaded = false

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
                if case .edit(let f) = mode {
                    name = f.name
                    colorIndex = f.colorIndex
                    icon = f.icon
                } else {
                    colorIndex = store.folders.count % Theme.folderColors.count
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
            store.createFolder(name: name, colorIndex: colorIndex, icon: icon)
        case .edit(let f):
            var updated = f
            updated.name = name.isEmpty ? f.name : name
            updated.colorIndex = colorIndex
            updated.icon = icon
            store.updateFolder(updated)
        }
        dismiss()
    }
}
