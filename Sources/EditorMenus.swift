import SwiftUI
import PhotosUI

/// Everything the editor's menus and toolbar can ask for.
enum EditorAction {
    case addPage, chooseTemplate, scanDocument, pageFromCamera, importFile
    case camera, stickyNote, textBox, emoji(String), sticker(String)
    case sharePDF, sharePNG, savePhoto, goToPage, bookmark, outline, duplicatePage, deletePage
    case zoomBox, readOnly, info, customizeToolbar, clearCanvas, background
    case tool(EditorTool), allNotes, search
}

// MARK: - Dark menu building blocks (Noteshelf-style)

private let menuAccent = Theme.action

struct MenuBlock<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#1C1C1E")))
    }
}

struct MenuRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var chevron = false
    var destructive = false
    var on: Bool? = nil
    var divider = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { MenuRowLabel(icon: icon, title: title, detail: detail, chevron: chevron,
                                              destructive: destructive, on: on, divider: divider) }
            .buttonStyle(.plain)
    }
}

struct MenuRowLabel: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var chevron = false
    var destructive = false
    var on: Bool? = nil
    var divider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(destructive ? Color.red : menuAccent)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(destructive ? Color.red : Color.white)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail).font(.system(size: 16)).foregroundStyle(.white.opacity(0.5))
                }
                if let on {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(on ? menuAccent : Color.white.opacity(0.35))
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .contentShape(Rectangle())
            if divider {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 56)
            }
        }
    }
}

struct MenuHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.top, 10)
    }
}

// MARK: - (+) menu

struct AddMenu: View {
    let isCanvas: Bool
    @Binding var pageImageItem: PhotosPickerItem?
    @Binding var photoItem: PhotosPickerItem?
    let onAction: (EditorAction) -> Void

    private enum Tab: Int { case page, media, tools }
    private enum Sub { case emoji, stickers }
    @State private var tab: Tab = .page
    @State private var sub: Sub?

    var body: some View {
        VStack(spacing: 14) {
            if let sub {
                HStack {
                    Button { withAnimation(.easeOut(duration: 0.2)) { self.sub = nil } } label: {
                        Label("Back", systemImage: "chevron.left").font(.system(size: 16, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(menuAccent)
                    Spacer()
                    Text(sub == .emoji ? "Emojis" : "Stickers").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 60, height: 1)
                }
                .padding(.horizontal, 4)
                if sub == .emoji {
                    EmojiGrid { onAction(.emoji($0)) }
                } else {
                    StickerGrid { onAction(.sticker($0)) }
                }
            } else {
                tabs
                ScrollView {
                    VStack(spacing: 14) { tabContent }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(16)
        .frame(width: 360, height: 470)
        .presentationCompactAdaptation(.popover)
        .darkPanel()
        .onAppear { if isCanvas { tab = .media } }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            if !isCanvas { tabButton(.page, "doc") }
            tabButton(.media, "photo.on.rectangle")
            tabButton(.tools, "paperclip")
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func tabButton(_ t: Tab, _ icon: String) -> some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { tab = t } } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().fill(tab == t ? Color.white.opacity(0.22) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .page:
            MenuBlock {
                MenuRow(icon: "doc.badge.plus", title: "Add Page") { onAction(.addPage) }
                MenuRow(icon: "doc.text", title: "Choose Template…", divider: false) { onAction(.chooseTemplate) }
            }
            MenuBlock {
                PhotosPicker(selection: $pageImageItem, matching: .images) {
                    MenuRowLabel(icon: "photo.badge.plus", title: "Page from Image", chevron: true)
                }
                .buttonStyle(.plain)
                MenuRow(icon: "doc.viewfinder", title: "Scan Document") { onAction(.scanDocument) }
                MenuRow(icon: "camera", title: "Page from Camera", divider: false) { onAction(.pageFromCamera) }
            }
            MenuBlock {
                MenuRow(icon: "square.and.arrow.down", title: "Import File", divider: false) { onAction(.importFile) }
            }
        case .media:
            MenuBlock {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    MenuRowLabel(icon: "photo", title: "Image", chevron: true)
                }
                .buttonStyle(.plain)
                MenuRow(icon: "camera", title: "Camera", divider: false) { onAction(.camera) }
            }
            MenuBlock {
                MenuRow(icon: "textformat", title: "Text Box") { onAction(.textBox) }
                MenuRow(icon: "note.text", title: "Sticky Note", chevron: true) { onAction(.stickyNote) }
                MenuRow(icon: "face.smiling", title: "Emojis", chevron: true) {
                    withAnimation(.easeOut(duration: 0.2)) { sub = .emoji }
                }
                MenuRow(icon: "seal", title: "Stickers", chevron: true, divider: false) {
                    withAnimation(.easeOut(duration: 0.2)) { sub = .stickers }
                }
            }
        case .tools:
            MenuBlock {
                MenuRow(icon: "square.on.circle", title: "Shapes") { onAction(.tool(.shapes)) }
                MenuRow(icon: "wand.and.rays", title: "Laser Pointer") { onAction(.tool(.laser)) }
                MenuRow(icon: "bandage", title: "Tape", divider: isCanvas ? false : true) { onAction(.tool(.tape)) }
                if !isCanvas {
                    MenuRow(icon: "rectangle.and.text.magnifyingglass", title: "Zoom Box", divider: false) { onAction(.zoomBox) }
                }
            }
        }
    }
}

struct EmojiGrid: View {
    let onPick: (String) -> Void
    static let emojis = ["😀", "😂", "🥰", "😎", "🤔", "😴", "🥳", "😭", "👍", "👎", "👏", "🙏", "💪", "👀", "🔥", "✨",
                         "⭐️", "❤️", "💡", "📌", "📎", "✅", "❌", "⚠️", "❓", "❗️", "💯", "🎯", "📚", "✏️", "📝", "🧠",
                         "🔬", "🧪", "💻", "📈", "📉", "🗓️", "⏰", "🏆", "🎉", "☕️", "🍀", "🌈", "☀️", "🌙", "⚡️", "🚀"]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                ForEach(Self.emojis, id: \.self) { e in
                    Button { onPick(e) } label: {
                        Text(e).font(.system(size: 34)).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

struct StickerGrid: View {
    let onPick: (String) -> Void
    static let stickers = ["star.fill", "heart.fill", "checkmark.seal.fill", "xmark.octagon.fill", "exclamationmark.triangle.fill",
                           "lightbulb.fill", "flag.fill", "bookmark.fill", "pin.fill", "bolt.fill", "flame.fill", "crown.fill",
                           "arrow.right", "arrow.left", "arrow.up", "arrow.down", "arrow.uturn.right", "arrow.triangle.2.circlepath",
                           "questionmark.circle.fill", "info.circle.fill", "hand.thumbsup.fill", "graduationcap.fill",
                           "book.fill", "calendar", "clock.fill", "trophy.fill", "sparkles", "leaf.fill", "sun.max.fill", "moon.fill"]
    static let colors = ["#F5B700", "#E53935", "#2E9E5B", "#2F6FDE", "#8E44AD", "#FF7A00"]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 10) {
                ForEach(Array(Self.stickers.enumerated()), id: \.offset) { i, s in
                    Button { onPick(s + "|" + Self.colors[i % Self.colors.count]) } label: {
                        Image(systemName: s)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color(hex: Self.colors[i % Self.colors.count]))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

// MARK: - (…) menu

struct MoreMenu: View {
    let isCanvas: Bool
    let pageLabel: String
    let bookmarked: Bool
    let inOutline: Bool
    let zoomBoxOn: Bool
    let readOnly: Bool
    @Binding var horizontal: Bool
    @Binding var inputMode: DrawingInput
    @Binding var toolsDock: ToolbarDock
    @Binding var colorsDock: ToolbarDock
    let onAction: (EditorAction) -> Void

    @State private var shareOpen = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                MenuBlock {
                    MenuRow(icon: "square.and.arrow.up", title: "Share", chevron: true, divider: shareOpen || !isCanvas) {
                        withAnimation(.easeOut(duration: 0.2)) { shareOpen.toggle() }
                    }
                    if shareOpen {
                        MenuRow(icon: "doc.richtext", title: isCanvas ? "Canvas as PDF" : "Notebook as PDF") { onAction(.sharePDF) }
                        if !isCanvas {
                            MenuRow(icon: "photo", title: "Page as PNG") { onAction(.sharePNG) }
                            MenuRow(icon: "photo.badge.arrow.down", title: "Save Page to Photos") { onAction(.savePhoto) }
                        }
                    }
                    if !isCanvas {
                        MenuRow(icon: "doc.text.magnifyingglass", title: "Go to Page", detail: pageLabel, divider: false) {
                            onAction(.goToPage)
                        }
                    }
                }

                MenuHeader(text: isCanvas ? "Canvas" : "Page")
                MenuBlock {
                    MenuRow(icon: "doc.text", title: isCanvas ? "Change Background" : "Change Template") { onAction(.chooseTemplate) }
                    if !isCanvas {
                        MenuRow(icon: bookmarked ? "bookmark.fill" : "bookmark",
                                title: bookmarked ? "Remove Bookmark" : "Bookmark Page") { onAction(.bookmark) }
                        MenuRow(icon: "list.bullet.indent", title: inOutline ? "Rename in Outline" : "Add to Outline") { onAction(.outline) }
                        MenuRow(icon: "plus.square.on.square", title: "Duplicate Page") { onAction(.duplicatePage) }
                        MenuRow(icon: "trash", title: "Delete page", destructive: true, divider: false) { onAction(.deletePage) }
                    } else {
                        MenuRow(icon: "trash", title: "Clear Canvas", destructive: true, divider: false) { onAction(.clearCanvas) }
                    }
                }

                MenuHeader(text: isCanvas ? "Canvas" : "Notebook")
                MenuBlock {
                    if !isCanvas {
                        MenuRow(icon: "rectangle.and.text.magnifyingglass", title: "Zoom Box", on: zoomBoxOn) { onAction(.zoomBox) }
                    }
                    MenuRow(icon: "lock", title: "Read only Mode", on: readOnly) { onAction(.readOnly) }
                    MenuRow(icon: "info.circle", title: "Get Info", chevron: true, divider: false) { onAction(.info) }
                }

                MenuHeader(text: "Settings")
                MenuBlock {
                    if !isCanvas {
                        settingRow(icon: "rectangle.split.2x1", title: "View Mode") {
                            Picker("View Mode", selection: $horizontal) {
                                Text("Vertical").tag(false)
                                Text("Horizontal").tag(true)
                            }
                        }
                    }
                    settingRow(icon: "applepencil", title: "Stylus") {
                        Picker("Stylus", selection: $inputMode) {
                            ForEach(DrawingInput.allCases) { m in Text(m.title).tag(m) }
                        }
                    }
                    settingRow(icon: "rectangle.3.group", title: "Tools Bar") {
                        Picker("Tools Bar", selection: $toolsDock) {
                            ForEach(ToolbarDock.allCases) { d in Text(d.title).tag(d) }
                        }
                    }
                    settingRow(icon: "paintpalette", title: "Colour Bar", divider: false) {
                        Picker("Colour Bar", selection: $colorsDock) {
                            ForEach(ToolbarDock.allCases) { d in Text(d.title).tag(d) }
                        }
                    }
                }

                Button { onAction(.customizeToolbar) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 19))
                            .foregroundStyle(LinearGradient(colors: [Color(hex: "#5AC8FA"), Color(hex: "#F5B700")],
                                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 26)
                        Text("Customize Toolbar").font(.system(size: 17)).foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .frame(width: 370, height: 640)
        .presentationCompactAdaptation(.popover)
        .darkPanel()
    }

    private func settingRow<P: View>(icon: String, title: String, divider: Bool = true,
                                     @ViewBuilder picker: () -> P) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(menuAccent).frame(width: 26)
                Text(title).font(.system(size: 17)).foregroundStyle(.white)
                Spacer()
                Menu {
                    picker()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            if divider {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 56)
            }
        }
    }
}

// MARK: - Customize Toolbar

struct CustomizeToolbarSheet: View {
    @EnvironmentObject var tools: ToolState
    @Environment(\.dismiss) private var dismiss
    let isCanvas: Bool

    private var available: [ToolbarItemKind] {
        ToolbarItemKind.allCases.filter { !(isCanvas && $0.pagedOnly) }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Reset") {
                    withAnimation(.snappy) { tools.toolbarItems = ToolbarItemKind.defaults }
                }
                .foregroundStyle(menuAccent)
                Spacer()
                Text("Customize Toolbar").font(.headline).foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(menuAccent))
                }
                .accessibilityLabel("Done")
            }

            // The toolbar as it will look.
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(["pencil.tip", "highlighter", "eraser", "lasso"], id: \.self) { s in
                        Image(systemName: s).font(.system(size: 17)).foregroundStyle(.white.opacity(0.55))
                            .frame(width: 38, height: 38)
                    }
                    ForEach(tools.toolbarItems) { item in
                        Button {
                            withAnimation(.snappy) { tools.toolbarItems.removeAll { $0 == item } }
                        } label: {
                            Image(systemName: item.symbol).font(.system(size: 17)).foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white, .red)
                                        .offset(x: 3, y: -3)
                                }
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .background(Capsule().fill(Color.white.opacity(0.08)))

            Text("Tap a tool to add or remove it. Touch and hold to learn what it does.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            ScrollView {
                FlowLayout(spacing: 10) {
                    ForEach(available) { item in chip(item) }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .darkPanel()
    }

    private func chip(_ item: ToolbarItemKind) -> some View {
        let on = tools.toolbarItems.contains(item)
        return Button {
            withAnimation(.snappy) {
                if on { tools.toolbarItems.removeAll { $0 == item } } else { tools.toolbarItems.append(item) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol).font(.system(size: 14, weight: .medium))
                Text(item.title).font(.system(size: 15, weight: .medium))
                if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
            }
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(on ? menuAccent.opacity(0.55) : Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(on ? 0.0 : 0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .contextMenu {
            Text(item.info)
        } preview: {
            VStack(alignment: .leading, spacing: 8) {
                Label(item.title, systemImage: item.symbol).font(.headline)
                Text(item.info).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(width: 300, alignment: .leading)
        }
    }
}

/// Lays chips out in rows, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Centre each row, like Noteshelf's tool picker.
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > bounds.width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((v, s))
            x += s.width + spacing
        }
        var y = bounds.minY
        for row in rows {
            let w = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(row.count - 1, 0))
            var cx = bounds.minX + (bounds.width - w) / 2
            let h = row.map { $0.1.height }.max() ?? 0
            for (v, s) in row {
                v.place(at: CGPoint(x: cx, y: y), proposal: ProposedViewSize(s))
                cx += s.width + spacing
            }
            y += h + spacing
        }
    }
}
