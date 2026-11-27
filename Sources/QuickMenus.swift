import SwiftUI

/// Apple Pencil Pro squeeze menu: two arcs around the pencil tip with tools,
/// colours and sizes, plus undo/redo. Closes when you pick a tool, start
/// writing, squeeze again or tap the middle.
struct SqueezeMenu: View {
    @EnvironmentObject var tools: ToolState
    let center: CGPoint
    let area: CGSize
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClose: () -> Void

    @State private var shown = false

    private let innerR: CGFloat = 76
    private let outerR: CGFloat = 132
    private let toolAngles: [Double] = [135, 170, 205, 240, 275]
    private let colorAngles: [Double] = [150, 173, 196]
    private let sizeAngles: [Double] = [226, 249, 272]
    private static let band = Color(hex: "#232325").opacity(0.94)

    private var c: CGPoint {
        CGPoint(x: min(max(center.x, 175), area.width - 70),
                y: min(max(center.y, 175), area.height - 110))
    }

    private func pos(_ angle: Double, _ r: CGFloat) -> CGPoint {
        let a = angle * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArcBand(center: c, radius: outerR, start: 150, end: 272)
                .trim(from: 0, to: shown ? 1 : 0)
                .stroke(Self.band, style: StrokeStyle(lineWidth: 48, lineCap: .round))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            ArcBand(center: c, radius: innerR, start: 135, end: 275)
                .trim(from: 0, to: shown ? 1 : 0)
                .stroke(Self.band, style: StrokeStyle(lineWidth: 52, lineCap: .round))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            let items = toolItems
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                toolButton(item)
                    .position(pos(toolAngles[i], innerR))
                    .modifier(PopIn(shown: shown, delay: Double(i) * 0.02))
            }
            ForEach(0..<3, id: \.self) { i in
                colorButton(i)
                    .position(pos(colorAngles[i], outerR))
                    .modifier(PopIn(shown: shown, delay: 0.08 + Double(i) * 0.02))
            }
            ForEach(0..<3, id: \.self) { i in
                sizeButton(i)
                    .position(pos(sizeAngles[i], outerR))
                    .modifier(PopIn(shown: shown, delay: 0.14 + Double(i) * 0.02))
            }
            roundButton("arrow.uturn.backward", enabled: canUndo, label: "Undo", action: onUndo)
                .position(pos(100, innerR + 6))
                .modifier(PopIn(shown: shown, delay: 0.04))
            roundButton("arrow.uturn.forward", enabled: canRedo, label: "Redo", action: onRedo)
                .position(pos(64, innerR + 14))
                .modifier(PopIn(shown: shown, delay: 0.06))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Self.band))
            }
            .buttonStyle(PressableStyle())
            .position(c)
            .modifier(PopIn(shown: shown, delay: 0))
            .accessibilityLabel("Close Menu")
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .onAppear {
            // A quick, smooth reveal: no overshoot or wobble.
            withAnimation(.easeOut(duration: 0.2)) { shown = true }
        }
    }

    private struct ToolItem {
        let tool: EditorTool?
        let symbol: String
        let label: String
    }

    private var toolItems: [ToolItem] {
        [ToolItem(tool: .pen, symbol: tools.pen.kind.symbol, label: "Pen"),
         ToolItem(tool: .highlighter, symbol: "highlighter", label: "Highlighter"),
         ToolItem(tool: .eraser, symbol: "eraser", label: "Eraser"),
         ToolItem(tool: .lasso, symbol: "lasso", label: "Lasso"),
         ToolItem(tool: nil, symbol: "ruler", label: "Ruler")]
    }

    private func toolButton(_ item: ToolItem) -> some View {
        let selected = item.tool.map { tools.tool == $0 } ?? tools.rulerActive
        return Button {
            if let t = item.tool {
                tools.tool = t
                onClose()
            } else {
                tools.rulerActive.toggle()
            }
        } label: {
            Image(systemName: item.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(selected ? Theme.action.opacity(0.55) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(item.label)
    }

    private var usesHighlighter: Bool { tools.tool == .highlighter }

    private func colorButton(_ i: Int) -> some View {
        let hex = usesHighlighter ? tools.highlighterQuickColors[i] : tools.penQuickColors[i]
        let current = usesHighlighter ? tools.highlighter.colorHex : tools.pen.colorHex
        let selected = current == hex && (tools.tool == .pen || tools.tool == .highlighter)
        return Button {
            if usesHighlighter {
                tools.highlighter.colorHex = hex
            } else {
                tools.pen.colorHex = hex
                tools.tool = .pen
            }
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: selected ? 22 : 26, height: selected ? 22 : 26)
                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
                .padding(3)
                .overlay(Circle().stroke(.white, lineWidth: selected ? 2.5 : 0))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }

    private func sizeButton(_ i: Int) -> some View {
        let selected: Bool
        switch tools.tool {
        case .highlighter: selected = abs(tools.highlighter.width - tools.highlighterQuickSizes[i]) < 0.05
        case .eraser: selected = abs(tools.eraserWidth - tools.eraserQuickSizes[i]) < 0.05
        default: selected = abs(tools.pen.width - tools.penQuickSizes[i]) < 0.05
        }
        return Button {
            switch tools.tool {
            case .highlighter: tools.highlighter.width = tools.highlighterQuickSizes[i]
            case .eraser:
                tools.eraserMode = .pixel
                tools.eraserWidth = tools.eraserQuickSizes[i]
            default:
                tools.pen.width = tools.penQuickSizes[i]
                tools.tool = .pen
            }
        } label: {
            Capsule()
                .fill(.white)
                .frame(width: 18, height: [2, 3.5, 6][i])
                .frame(width: 38, height: 38)
                .background(Circle().fill(selected ? Theme.action.opacity(0.55) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(["Thin", "Medium", "Thick"][i])
    }

    private func roundButton(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Self.band))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// An arc drawn by sampling points (angles in degrees, 90° = straight down).
struct ArcBand: Shape {
    let center: CGPoint
    let radius: CGFloat
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = 48
        for s in 0...steps {
            let a = (start + (end - start) * Double(s) / Double(steps)) * .pi / 180
            let pt = CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
            if s == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// Fades a view in with a slight grow, staggered a touch. Eased, never bouncy.
struct PopIn: ViewModifier {
    let shown: Bool
    let delay: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.88)
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: 0.18).delay(delay * 0.5), value: shown)
    }
}

/// Dark panel on the left with page thumbnails (like Noteshelf's page sidebar):
/// search, Bookmarks / Outline / Photos filters and a bookmark ribbon on each page.
/// What you can do to one page from the pages panel.
enum PageAction { case copy, paste, duplicate, bookmark, addBefore, addAfter, delete }

struct PageSidebar: View {
    let title: String
    let template: PageTemplate
    let paper: PaperColor
    let count: Int
    let current: Int
    let thumbnail: (Int) -> UIImage?
    let bookmarked: (Int) -> Bool
    let outlineTitle: (Int) -> String?
    let hasPhotos: (Int) -> Bool
    let pageText: (Int) -> String
    let onToggleBookmark: (Int) -> Void
    let onSelect: (Int) -> Void
    let onAdd: () -> Void
    let onAllNotes: () -> Void
    let onClose: () -> Void
    var canPaste = false
    var onPageAction: (Int, PageAction) -> Void = { _, _ in }

    private enum Filter: String, CaseIterable { case all = "All", bookmarks = "Bookmarks", outline = "Outline", photos = "Photos" }
    @State private var filter: Filter = .all
    @State private var query = ""

    private var shown: [Int] {
        (0..<count).filter { i in
            switch filter {
            case .all: break
            case .bookmarks: if !bookmarked(i) { return false }
            case .outline: if outlineTitle(i) == nil { return false }
            case .photos: if !hasPhotos(i) { return false }
            }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return "\(i + 1)" == q
                || (outlineTitle(i)?.lowercased().contains(q) ?? false)
                || pageText(i).lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Button(action: onAllNotes) {
                    Image(systemName: "sidebar.left").font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("All Notes")
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("New Page")
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close")
            }
            .foregroundStyle(Theme.action)
            HStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Search", text: $query)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Button { withAnimation(.easeOut(duration: 0.18)) { filter = f } } label: {
                            Text(f.rawValue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(filter == f ? Color.white : Theme.action)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Capsule().fill(filter == f ? Theme.action.opacity(0.7) : Color.clear))
                                .overlay(Capsule().stroke(Color.white.opacity(filter == f ? 0 : 0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            ScrollViewReader { proxy in
                ScrollView {
                    if shown.isEmpty {
                        Text(filter == .all ? "No pages match" : "No \(filter.rawValue.lowercased()) yet")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                        ForEach(shown, id: \.self) { i in
                            PageThumb(index: i, template: template, paper: paper,
                                      selected: i == current, image: thumbnail(i),
                                      bookmarked: bookmarked(i), caption: outlineTitle(i),
                                      onBookmark: { onToggleBookmark(i) },
                                      menu: { pageMenu(i) })
                                .id(i)
                                .onTapGesture { onSelect(i) }
                                .contextMenu { pageMenu(i) }
                        }
                    }
                    // Room for the selection ring so it isn't clipped at the edges.
                    .padding(.vertical, 10)
                    .padding(.horizontal, 7)
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .padding(18)
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(Color(hex: "#111113").ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func pageMenu(_ i: Int) -> some View {
        Button { onPageAction(i, .copy) } label: { Label("Copy", systemImage: "doc.on.doc") }
        if canPaste {
            Button { onPageAction(i, .paste) } label: { Label("Paste After", systemImage: "doc.on.clipboard") }
        }
        Button { onPageAction(i, .duplicate) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button { onPageAction(i, .bookmark) } label: {
            Label(bookmarked(i) ? "Remove Bookmark" : "Bookmark",
                  systemImage: bookmarked(i) ? "bookmark.slash" : "bookmark")
        }
        Divider()
        Button { onPageAction(i, .addBefore) } label: { Label("Add Page Before", systemImage: "arrow.up.doc") }
        Button { onPageAction(i, .addAfter) } label: { Label("Add Page After", systemImage: "arrow.down.doc") }
        Divider()
        Button(role: .destructive) { onPageAction(i, .delete) } label: { Label("Delete", systemImage: "trash") }
    }
}

private struct PageThumb<MenuContent: View>: View {
    let index: Int
    let template: PageTemplate
    let paper: PaperColor
    let selected: Bool
    let image: UIImage?
    let bookmarked: Bool
    let caption: String?
    let onBookmark: () -> Void
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                } else {
                    TemplateThumbnail(template: template, paper: paper)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onBookmark) {
                    Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(bookmarked ? Theme.action : Color.gray.opacity(0.55))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(bookmarked ? "Remove bookmark" : "Bookmark page")
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Theme.action : Color.clear, lineWidth: 3).padding(-5))
            HStack(spacing: 4) {
                Text("\(index + 1)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                if let caption {
                    Text(caption).font(.caption).lineLimit(1)
                }
                Spacer(minLength: 0)
                Menu { menu() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 22)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Page \(index + 1) options")
            }
            .foregroundStyle(selected ? Theme.action : .white.opacity(0.75))
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

/// "All Notes": every notebook, newest first, to jump straight to another one.
struct AllNotesPanel: View {
    @EnvironmentObject var store: LibraryStore
    let current: UUID
    let onBack: () -> Void
    let onOpen: (Notebook) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Back")
                Spacer()
                Text("All Notes").font(.system(size: 22, weight: .regular, design: .serif)).foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 20, height: 1)
            }
            .foregroundStyle(.white)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.sorted(store.activeNotebooks, by: .modified)) { nb in
                        Button {
                            if nb.id != current { onOpen(nb) }
                        } label: {
                            HStack(spacing: 12) {
                                NotebookCoverView(cover: nb.cover)
                                    .frame(width: 38, height: 50)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(nb.title).font(.system(size: 16, weight: .medium)).foregroundStyle(.white).lineLimit(2)
                                    Text(NotebookTile.dateText(nb.modifiedAt)).font(.caption).foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(nb.id == current ? Color.white.opacity(0.12) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}