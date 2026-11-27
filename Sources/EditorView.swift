import SwiftUI
import PencilKit
import PhotosUI
import UniformTypeIdentifiers

@MainActor
final class EditorController: ObservableObject {
    weak var surface: DrawingSurfaceController?
    var pages: PagesViewController? { surface as? PagesViewController }
    var board: CanvasViewController? { surface as? CanvasViewController }
    @Published var pageIndex = 0
    @Published var pageCount = 1
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var zoomPercent = 100
    @Published var zoomBoxOpen = false
    /// Where Apple Pencil Pro was squeezed (opens the quick menu there).
    @Published var squeezePoint: CGPoint?
    @Published var doubleTaps = 0
}

/// Hosts the paged notebook or the infinite canvas.
struct SurfaceHost: UIViewControllerRepresentable {
    let store: LibraryStore
    let notebook: Notebook
    let tool: PKTool
    let editorTool: EditorTool
    let feel: InkFeel
    let readOnly: Bool
    let horizontal: Bool
    let textColor: String
    let textSize: CGFloat
    let inputMode: DrawingInput
    let ruler: Bool
    let controller: EditorController

    func makeUIViewController(context: Context) -> DrawingSurfaceController {
        let vc: DrawingSurfaceController = notebook.isCanvas
            ? CanvasViewController(store: store, notebook: notebook)
            : PagesViewController(store: store, notebook: notebook, horizontal: horizontal)
        let ctrl = controller
        vc.onPageChanged = { i, n in
            DispatchQueue.main.async {
                if ctrl.pageIndex != i { ctrl.pageIndex = i }
                if ctrl.pageCount != n { ctrl.pageCount = n }
            }
        }
        vc.onUndoChanged = { u, r in
            DispatchQueue.main.async {
                ctrl.canUndo = u
                ctrl.canRedo = r
            }
        }
        vc.onZoomChanged = { z in
            DispatchQueue.main.async { if ctrl.zoomPercent != z { ctrl.zoomPercent = z } }
        }
        vc.onPencilDoubleTap = { DispatchQueue.main.async { ctrl.doubleTaps += 1 } }
        vc.onPencilSqueeze = { p in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.18)) {
                    ctrl.squeezePoint = ctrl.squeezePoint == nil ? p : nil
                }
            }
        }
        vc.onDrawingStarted = {
            DispatchQueue.main.async {
                guard ctrl.squeezePoint != nil else { return }
                withAnimation(.easeOut(duration: 0.15)) { ctrl.squeezePoint = nil }
            }
        }
        (vc as? PagesViewController)?.onZoomBox = { open in
            DispatchQueue.main.async { ctrl.zoomBoxOpen = open }
        }
        controller.surface = vc
        apply(to: vc)
        return vc
    }

    func updateUIViewController(_ vc: DrawingSurfaceController, context: Context) {
        apply(to: vc)
    }

    private func apply(to vc: DrawingSurfaceController) {
        vc.setTool(tool)
        vc.setInputMode(inputMode)
        vc.setRuler(ruler)
        vc.textColorHex = textColor
        vc.textSize = textSize
        vc.setMode(tool: editorTool, feel: feel, readOnly: readOnly)
        (vc as? PagesViewController)?.setHorizontal(horizontal)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum ToolbarDock: String, CaseIterable, Identifiable {
    case top, bottom, left, right
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var vertical: Bool { self == .left || self == .right }
}

/// The two floating bars, each docked to its own edge.
private enum BarKind { case tools, colors }

private enum EditorCover: String, Identifiable {
    case scanner, cameraPage, cameraPhoto
    var id: String { rawValue }
}

struct EditorView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var tools: ToolState
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook
    var onSwitch: (Notebook) -> Void = { _ in }

    @StateObject private var controller = EditorController()
    @AppStorage("folio.toolbarDock") private var dockRaw = ToolbarDock.top.rawValue
    @AppStorage("folio.colorbarDock") private var colorDockRaw = ToolbarDock.top.rawValue
    @AppStorage("folio.horizontalPages") private var horizontal = false
    @State private var showToolSettings = false
    @State private var focusMode = false
    @State private var showPaper = false
    @State private var showSidebar = false
    @State private var showAllNotes = false
    @State private var confirmDeletePage = false
    @State private var shareItem: ShareItem?
    @State private var dragBar: BarKind?
    @State private var dragOffset: CGSize = .zero
    @State private var dragTarget: ToolbarDock?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var showPageBadge = false
    @State private var badgeTask: Task<Void, Never>?
    @State private var showAdd = false
    @State private var showMore = false
    @State private var showCustomize = false
    @State private var readOnly = false
    @State private var pageImageItem: PhotosPickerItem?
    @State private var photoItem: PhotosPickerItem?
    @State private var toolbarPhotoItem: PhotosPickerItem?
    @State private var cover: EditorCover?
    @State private var showImporter = false
    @State private var showGoTo = false
    @State private var goToText = ""
    @State private var showOutline = false
    @State private var outlineText = ""
    @State private var showInfo = false
    @State private var showEmojiPopover = false
    @State private var showStickerPopover = false
    @Namespace private var toolNS

    private var toolsDock: ToolbarDock { ToolbarDock(rawValue: dockRaw) ?? .top }
    private var colorsDock: ToolbarDock { ToolbarDock(rawValue: colorDockRaw) ?? .top }
    private var isCanvas: Bool { notebook.isCanvas }
    private var currentNotebook: Notebook { store.notebook(notebook.id) ?? notebook }
    private var currentPageId: UUID? {
        let pages = currentNotebook.pages
        return pages.indices.contains(controller.pageIndex) ? pages[controller.pageIndex] : nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SurfaceHost(store: store, notebook: notebook, tool: tools.pkTool, editorTool: tools.tool,
                            feel: tools.pen.inkFeel, readOnly: readOnly, horizontal: horizontal,
                            textColor: tools.textColorHex, textSize: tools.textSize,
                            inputMode: tools.inputMode, ruler: tools.rulerActive, controller: controller)
                    .ignoresSafeArea()

                if !isCanvas && !showSidebar {
                    edgeSwipeArea
                }

                if focusMode {
                    focusExitButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
                } else {
                    chrome(size: geo.size)
                        .transition(.opacity)
                }

                if showSidebar && !isCanvas {
                    sidebarLayer
                }

                if let p = controller.squeezePoint {
                    SqueezeMenu(center: p, area: geo.size,
                                canUndo: controller.canUndo, canRedo: controller.canRedo,
                                onUndo: { controller.surface?.performUndo() },
                                onRedo: { controller.surface?.performRedo() },
                                onClose: closeSqueeze)
                        .environmentObject(tools)
                        .transition(.opacity)
                        .zIndex(10)
                }

                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.black.opacity(0.82)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, toastTop)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .zIndex(11)
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: focusMode)
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: showSidebar)
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: showAllNotes)
        .animation(.easeOut(duration: 0.25), value: toast)
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $showPaper) {
            PaperSheet(template: currentNotebook.template, paper: currentNotebook.paper, isCanvas: isCanvas) { t, p in
                controller.pages?.applyPaper(template: t, paper: p)
                controller.board?.applyPaper(template: t, paper: p)
            }
        }
        .sheet(isPresented: $showCustomize) {
            CustomizeToolbarSheet(isCanvas: isCanvas)
                .environmentObject(tools)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $cover) { c in
            switch c {
            case .scanner:
                DocumentScannerView { images in
                    cover = nil
                    addPages(images)
                }
                .ignoresSafeArea()
            case .cameraPage, .cameraPhoto:
                CameraPicker { image in
                    cover = nil
                    guard let image else { return }
                    if c == .cameraPage { addPages([image]) } else { placePhoto(image) }
                }
                .ignoresSafeArea()
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: FileImporter.types) { result in
            guard case .success(let url) = result else { return }
            let images = FileImporter.pages(from: url)
            if isCanvas { images.first.map(placePhoto) } else { addPages(images) }
        }
        .alert("Go to Page", isPresented: $showGoTo) {
            TextField("Page number", text: $goToText).keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Go") {
                if let n = Int(goToText), n >= 1, n <= controller.pageCount { controller.pages?.jump(to: n - 1) }
            }
        } message: {
            Text("1 to \(controller.pageCount)")
        }
        .alert("Outline", isPresented: $showOutline) {
            TextField("Page title", text: $outlineText)
            Button("Cancel", role: .cancel) {}
            if let pid = currentPageId, currentNotebook.outlineTitle(pid) != nil {
                Button("Remove", role: .destructive) {
                    store.setOutline(notebookId: notebook.id, pageId: pid, title: nil)
                }
            }
            Button("Save") {
                if let pid = currentPageId {
                    store.setOutline(notebookId: notebook.id, pageId: pid, title: outlineText)
                    showToast("Added to outline")
                }
            }
        } message: {
            Text("Name this page so you can find it in the Outline.")
        }
        .alert(currentNotebook.title, isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoText)
        }
        .confirmationDialog(isCanvas ? "Clear the whole canvas?" : "Delete this page?",
                            isPresented: $confirmDeletePage, titleVisibility: .visible) {
            Button(isCanvas ? "Clear Canvas" : "Delete Page \(controller.pageIndex + 1)", role: .destructive) {
                controller.pages?.deleteCurrentPage()
                controller.board?.clearAll()
                controller.zoomBoxOpen = controller.pages?.isZoomBoxOpen ?? false
            }
        } message: {
            Text("This can't be undone.")
        }
        .onChange(of: controller.doubleTaps) { _, _ in
            tools.toggleEraser()
            showToast(tools.toolTitle)
        }
        .onChange(of: controller.pageIndex) { _, _ in flashPageBadge() }
        .onChange(of: pageImageItem) { _, item in
            guard let item else { return }
            pageImageItem = nil
            closeMenus()
            load(item) { addPages([$0]) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            closeMenus()
            load(item, then: placePhoto)
        }
        .onChange(of: toolbarPhotoItem) { _, item in
            guard let item else { return }
            toolbarPhotoItem = nil
            load(item, then: placePhoto)
        }
        .onAppear(perform: runDemoHooks)
    }

    private var toastTop: CGFloat {
        if focusMode { return 14 }
        var top: CGFloat = 70
        if toolsDock == .top { top = 70 }
        if colorsDock == .top && tools.tool.hasContextBar { top = 128 }
        return top
    }

    private var infoText: String {
        let nb = currentNotebook
        let kind = nb.isCanvas ? "Infinite canvas" : "\(nb.pages.count) page\(nb.pages.count == 1 ? "" : "s")"
        let folder = nb.folderId.map { store.folderPath($0) } ?? "Unfiled"
        return "\(kind)\nFolder: \(folder)\nCreated: \(nb.createdAt.formatted(date: .abbreviated, time: .shortened))\nEdited: \(nb.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: Chrome

    private func chrome(size: CGSize) -> some View {
        ZStack {
            HStack(alignment: .top) {
                leftGroup
                Spacer()
                rightGroup
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)

            if let t = dragTarget, let b = dragBar {
                dockPlaceholder(t, vertical: t.vertical, long: b == .tools ? 300 : 240)
                    .transition(.opacity)
            }

            placed(.tools, size: size)
            if tools.tool.hasContextBar && !readOnly {
                placed(.colors, size: size)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }

            bottomPill
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 14)
                .padding(.bottom, 14)

            if showPageBadge && !isCanvas {
                pageBadge
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, (toolsDock == .bottom || colorsDock == .bottom) ? 128 : 22)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showPageBadge)
        .animation(.easeOut(duration: 0.2), value: tools.tool.hasContextBar)
        // The bars are see-through, so their icons follow the paper, not the system theme.
        .environment(\.colorScheme, currentNotebook.paper == .dark ? .dark : .light)
    }

    private func dock(of bar: BarKind) -> ToolbarDock { bar == .tools ? toolsDock : colorsDock }

    @ViewBuilder
    private func placed(_ bar: BarKind, size: CGSize) -> some View {
        let d = dock(of: bar)
        // When both bars share an edge the colour bar sits just inside the tools bar.
        let extra: CGFloat = (bar == .colors && toolsDock == colorsDock) ? (d.vertical ? 62 : 58) : 0
        let content = Group {
            if bar == .tools { toolsGroup(vertical: d.vertical, size: size) } else { contextBar(vertical: d.vertical) }
        }
        .offset(dragBar == bar ? dragOffset : .zero)
        .gesture(dockDrag(bar, size: size))
        switch d {
        case .top:
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 8 + extra)
        case .bottom:
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 14 + extra)
        case .left:
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.leading, 14 + extra)
        case .right:
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.trailing, 14 + extra)
        }
    }

    private func dockDrag(_ bar: BarKind, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { v in
                if dragBar != bar { dragBar = bar }
                dragOffset = v.translation
                let target = nearestDock(v.location, in: size)
                if target != dragTarget {
                    withAnimation(.easeOut(duration: 0.15)) { dragTarget = target }
                }
            }
            .onEnded { v in
                let target = nearestDock(v.location, in: size)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    if bar == .tools { dockRaw = target.rawValue } else { colorDockRaw = target.rawValue }
                    dragOffset = .zero
                    dragTarget = nil
                    dragBar = nil
                }
            }
    }

    private func nearestDock(_ p: CGPoint, in s: CGSize) -> ToolbarDock {
        let d: [(ToolbarDock, CGFloat)] = [(.top, p.y), (.bottom, s.height - p.y),
                                            (.left, p.x * 1.15), (.right, (s.width - p.x) * 1.15)]
        return d.min { $0.1 < $1.1 }?.0 ?? .top
    }

    private func dockPlaceholder(_ t: ToolbarDock, vertical: Bool, long: CGFloat) -> some View {
        let shape = Capsule()
        let fill = shape.fill(Theme.action.opacity(0.22))
            .overlay(shape.strokeBorder(Theme.action.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .frame(width: vertical ? 50 : long, height: vertical ? long : 50)
        return Group {
            switch t {
            case .top: fill.frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
            case .bottom: fill.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 14)
            case .left: fill.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
            case .right: fill.frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14)
            }
        }
        .allowsHitTesting(false)
    }

    private var leftGroup: some View {
        HStack(spacing: 0) {
            barButton("chevron.left", label: "Back to Library") {
                controller.surface?.saveAll()
                dismiss()
            }
            if !isCanvas {
                barButton("square.grid.2x2", label: "Pages") { showSidebar.toggle() }
            }
            barButton("arrow.uturn.backward", label: "Undo", enabled: controller.canUndo) {
                controller.surface?.performUndo()
            }
            barButton("arrow.uturn.forward", label: "Redo", enabled: controller.canRedo) {
                controller.surface?.performRedo()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
        .clearGlass(Capsule())
    }

    private var rightGroup: some View {
        HStack(spacing: 0) {
            barButton("plus", label: "Add") { showAdd = true }
                .popover(isPresented: $showAdd, arrowEdge: .top) {
                    AddMenu(isCanvas: isCanvas, pageImageItem: $pageImageItem, photoItem: $photoItem, onAction: perform)
                }
            barButton("arrow.up.left.and.arrow.down.right", label: "Focus Mode") {
                focusMode = true
                showToast("Focus mode")
            }
            barButton("ellipsis.circle", label: "More") { showMore = true }
                .popover(isPresented: $showMore, arrowEdge: .top) {
                    MoreMenu(isCanvas: isCanvas,
                             pageLabel: "\(controller.pageIndex + 1) of \(controller.pageCount)",
                             bookmarked: currentPageId.map(currentNotebook.isBookmarked) ?? false,
                             inOutline: currentPageId.flatMap(currentNotebook.outlineTitle) != nil,
                             zoomBoxOn: controller.zoomBoxOpen,
                             readOnly: readOnly,
                             horizontal: $horizontal,
                             inputMode: $tools.inputMode,
                             toolsDock: Binding(get: { toolsDock }, set: { d in withAnimation(.spring) { dockRaw = d.rawValue } }),
                             colorsDock: Binding(get: { colorsDock }, set: { d in withAnimation(.spring) { colorDockRaw = d.rawValue } }),
                             onAction: perform)
                }
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
        .clearGlass(Capsule())
    }

    // MARK: Tools bar

    private var extraItems: [ToolbarItemKind] {
        tools.toolbarItems.filter { !(isCanvas && $0.pagedOnly) }
    }

    private func toolsGroup(vertical: Bool, size: CGSize) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        let items = extraItems
        // Leave room for the side groups; extra tools scroll when they don't fit.
        let available = vertical ? size.height - 170 : size.width - (toolsDock == .top ? 430 : 120)
        let room = max(88, available - 232)
        let extrasLength = CGFloat(items.count) * 44
        return layout {
            grip(vertical: vertical)
            toolButton(.pen, symbol: tools.pen.kind.symbol, ink: tools.pen.colorHex, label: "Pen")
            toolButton(.highlighter, symbol: "highlighter", ink: tools.highlighter.colorHex, label: "Highlighter")
            toolButton(.eraser, symbol: "eraser", ink: nil, label: "Eraser")
            toolButton(.lasso, symbol: "lasso", ink: nil, label: "Lasso")
            if !items.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: vertical ? 24 : 1, height: vertical ? 1 : 24)
                    .padding(vertical ? .vertical : .horizontal, 3)
                if extrasLength > room {
                    ScrollView(vertical ? .vertical : .horizontal) {
                        extrasStack(items, vertical: vertical)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: vertical ? 46 : room, height: vertical ? room : 40)
                } else {
                    extrasStack(items, vertical: vertical)
                }
            }
        }
        .padding(vertical ? .vertical : .horizontal, 6)
        .frame(width: vertical ? 54 : nil, height: vertical ? nil : 50)
        .clearGlass(Capsule())
        .opacity(readOnly ? 0.55 : 1)
        .popover(isPresented: $showToolSettings) {
            toolSettings
        }
    }

    private func extrasStack(_ items: [ToolbarItemKind], vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ForEach(items) { item in extraButton(item) }
        }
    }

    private func grip(vertical: Bool) -> some View {
        Image(systemName: "line.3.horizontal")
            .rotationEffect(.degrees(vertical ? 0 : 90))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .frame(width: vertical ? 42 : 18, height: vertical ? 18 : 38)
            .contentShape(Rectangle())
            .accessibilityLabel("Move bar")
    }

    @ViewBuilder
    private func extraButton(_ item: ToolbarItemKind) -> some View {
        if let t = item.tool {
            toolButton(t, symbol: t.symbol, ink: nil, label: item.title)
        } else {
            switch item {
            case .photo:
                PhotosPicker(selection: $toolbarPhotoItem, matching: .images) {
                    extraIcon(item.symbol, on: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            case .emoji:
                extraAction(item, on: false) { showEmojiPopover = true }
                    .popover(isPresented: $showEmojiPopover) {
                        EmojiGrid { e in showEmojiPopover = false; perform(.emoji(e)) }
                            .padding(14)
                            .frame(width: 340, height: 360)
                            .presentationCompactAdaptation(.popover)
                            .darkPanel()
                    }
            case .stickers:
                extraAction(item, on: false) { showStickerPopover = true }
                    .popover(isPresented: $showStickerPopover) {
                        StickerGrid { s in showStickerPopover = false; perform(.sticker(s)) }
                            .padding(14)
                            .frame(width: 340, height: 380)
                            .presentationCompactAdaptation(.popover)
                            .darkPanel()
                    }
            case .ruler:
                extraAction(item, on: tools.rulerActive) { tools.rulerActive.toggle() }
            case .readOnly:
                extraAction(item, on: readOnly) { perform(.readOnly) }
            case .zoomBox:
                extraAction(item, on: controller.zoomBoxOpen) { perform(.zoomBox) }
            case .viewMode:
                extraAction(item, on: horizontal) {
                    horizontal.toggle()
                    showToast(horizontal ? "Horizontal pages" : "Vertical pages")
                }
            case .bookmark:
                extraAction(item, on: currentPageId.map(currentNotebook.isBookmarked) ?? false) { perform(.bookmark) }
            default:
                extraAction(item, on: false) {
                    switch item {
                    case .stickyNote: perform(.stickyNote)
                    case .camera: perform(.camera)
                    case .addPage: perform(.addPage)
                    case .duplicatePage: perform(.duplicatePage)
                    case .outline: perform(.outline)
                    case .search: perform(.search)
                    case .allNotes: perform(.allNotes)
                    case .sharePDF: perform(.sharePDF)
                    case .sharePNG: perform(.sharePNG)
                    case .savePhoto: perform(.savePhoto)
                    default: break
                    }
                }
            }
        }
    }

    private func extraAction(_ item: ToolbarItemKind, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { extraIcon(item.symbol, on: on) }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(item.title)
    }

    private func extraIcon(_ symbol: String, on: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(on ? Theme.action : Color.primary)
            .frame(width: 44, height: 38)
            .background(Capsule().fill(on ? Theme.action.opacity(0.2) : Color.clear))
            .contentShape(Rectangle())
    }

    private func toolButton(_ tool: EditorTool, symbol: String, ink: String?, label: String) -> some View {
        let selected = tools.tool == tool
        return Button {
            if selected {
                if tool == .pen || tool == .highlighter || tool == .eraser || tool == .shapes { showToolSettings = true }
            } else {
                tools.tool = tool
                if tool == .text { showToast("Tap the page to type") }
                if tool == .tape { showToast("Drag across writing to cover it") }
                if tool == .shapes { showToast("Draw a shape and it snaps clean") }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: selected ? .semibold : .medium))
                if let ink {
                    // Ink colour bar with an outline so white/yellow ink is still visible.
                    Capsule()
                        .fill(Color(hex: ink))
                        .frame(width: 14, height: 3.5)
                        .overlay(Capsule().stroke(Color.primary.opacity(0.35), lineWidth: 0.5))
                }
            }
            .foregroundStyle(selected ? Theme.action : Color.primary)
            .frame(width: 44, height: 38)
            .background {
                if selected {
                    Capsule().fill(Theme.action.opacity(0.2))
                        .matchedGeometryEffect(id: "selectedTool", in: toolNS)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Colour & size bar

    private func contextBar(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            grip(vertical: vertical)
            switch tools.tool {
            case .pen, .shapes:
                ForEach(0..<3, id: \.self) { i in
                    quickColor(hex: tools.penQuickColors[i], selected: tools.pen.colorHex == tools.penQuickColors[i]) {
                        tools.pen.colorHex = tools.penQuickColors[i]
                    } replace: {
                        tools.penQuickColors[i] = tools.pen.colorHex
                    }
                }
                moreButton
                barDivider(vertical)
                ForEach(0..<3, id: \.self) { i in
                    quickSize(index: i, selected: abs(tools.pen.width - tools.penQuickSizes[i]) < 0.05) {
                        tools.pen.width = tools.penQuickSizes[i]
                    }
                }
            case .highlighter:
                ForEach(0..<3, id: \.self) { i in
                    quickColor(hex: tools.highlighterQuickColors[i],
                               selected: tools.highlighter.colorHex == tools.highlighterQuickColors[i]) {
                        tools.highlighter.colorHex = tools.highlighterQuickColors[i]
                    } replace: {
                        tools.highlighterQuickColors[i] = tools.highlighter.colorHex
                    }
                }
                moreButton
                barDivider(vertical)
                ForEach(0..<3, id: \.self) { i in
                    quickSize(index: i, selected: abs(tools.highlighter.width - tools.highlighterQuickSizes[i]) < 0.05) {
                        tools.highlighter.width = tools.highlighterQuickSizes[i]
                    }
                }
            case .eraser:
                eraserModeButton(.stroke, symbol: "scribble", label: "Whole Stroke", compact: vertical)
                eraserModeButton(.pixel, symbol: "circle.dotted", label: "Precise", compact: vertical)
                if tools.eraserMode == .pixel {
                    barDivider(vertical)
                    ForEach(0..<3, id: \.self) { i in
                        quickSize(index: i, selected: abs(tools.eraserWidth - tools.eraserQuickSizes[i]) < 0.05) {
                            tools.eraserWidth = tools.eraserQuickSizes[i]
                        }
                    }
                }
            case .text:
                ForEach(Array((["#1C1C1E"] + tools.penQuickColors).enumerated()), id: \.offset) { _, hex in
                    quickColor(hex: hex, selected: tools.textColorHex == hex) {
                        tools.textColorHex = hex
                    } replace: {}
                }
                barDivider(vertical)
                ForEach(Array([16, 22, 32].enumerated()), id: \.offset) { i, s in
                    Button { tools.textSize = CGFloat(s) } label: {
                        Text("A")
                            .font(.system(size: [12, 16, 21][i], weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 36, height: 30)
                            .background(Capsule().fill(abs(tools.textSize - CGFloat(s)) < 0.5 ? Theme.action.opacity(0.25) : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(["Small text", "Medium text", "Large text"][i])
                }
            default:
                EmptyView()
            }
        }
        .padding(vertical ? .vertical : .horizontal, vertical ? 10 : 12)
        .frame(width: vertical ? 48 : nil, height: vertical ? nil : 46)
        .clearGlass(Capsule())
        .animation(.snappy(duration: 0.2), value: tools.pen.colorHex)
        .animation(.snappy(duration: 0.2), value: tools.highlighter.colorHex)
    }

    private func barDivider(_ vertical: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: vertical ? 22 : 1, height: vertical ? 1 : 22)
    }

    private func quickColor(hex: String, selected: Bool, select: @escaping () -> Void,
                            replace: @escaping () -> Void) -> some View {
        Button {
            if selected && tools.tool != .text { showToolSettings = true } else { select() }
        } label: {
            ZStack {
                Circle()
                    .stroke(selected ? Color.primary : Color.clear, lineWidth: 2)
                    .frame(width: 30, height: 30)
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: selected ? 21 : 25, height: selected ? 21 : 25)
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(action: replace) {
                Label("Use Current Color Here", systemImage: "eyedropper")
            }
        }
    }

    private func quickSize(index: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Capsule()
                .fill(Color.primary)
                .frame(width: 20, height: [2, 3.5, 6][index])
                .frame(width: 40, height: 30)
                .background(Capsule().fill(selected ? Theme.action.opacity(0.25) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(["Thin", "Medium", "Thick"][index])
    }

    private var moreButton: some View {
        Button { showToolSettings = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.secondary)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.secondary.opacity(0.6), lineWidth: 1.2))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("More Pen Options")
    }

    @ViewBuilder
    private var toolSettings: some View {
        switch tools.tool {
        case .pen, .shapes: PenSettingsView().environmentObject(tools)
        case .highlighter: HighlighterSettingsView().environmentObject(tools)
        case .eraser: EraserSettingsView().environmentObject(tools)
        default: EmptyView()
        }
    }

    private func eraserModeButton(_ mode: EraserMode, symbol: String, label: String, compact: Bool) -> some View {
        let selected = tools.eraserMode == mode
        return Button { tools.eraserMode = mode } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                if !compact { Text(label).font(.subheadline.weight(.medium)) }
            }
            .foregroundStyle(selected ? Theme.action : Color.primary)
            .padding(.horizontal, compact ? 0 : 12)
            .frame(width: compact ? 36 : nil, height: 32)
            .background(Capsule().fill(selected ? Theme.action.opacity(0.2) : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func barButton(_ symbol: String, label: String, enabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.primary.opacity(enabled ? 1 : 0.3))
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var focusExitButton: some View {
        Button {
            focusMode = false
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tools.toolSymbol)
                    .font(.system(size: 20, weight: .medium))
                if tools.tool == .pen {
                    Capsule().fill(Color(hex: tools.pen.colorHex)).frame(width: 14, height: 3.5)
                        .overlay(Capsule().stroke(Color.primary.opacity(0.35), lineWidth: 0.5))
                }
            }
            .foregroundStyle(Theme.action)
            .frame(width: 50, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .clearGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Show Toolbar")
    }

    /// Bottom-left: pages panel, page number and zoom (tap the zoom to fit the page again).
    private var bottomPill: some View {
        HStack(spacing: 0) {
            if !isCanvas {
                Button { showSidebar.toggle() } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Pages")
                pillDivider
                Text("\(controller.pageIndex + 1) of \(controller.pageCount)")
                    .contentTransition(.numericText())
                    .padding(.horizontal, 12)
                pillDivider
            } else {
                Image(systemName: "infinity")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 38)
                pillDivider
            }
            Button { controller.surface?.resetZoom() } label: {
                Text("\(controller.zoomPercent)%")
                    .contentTransition(.numericText())
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom \(controller.zoomPercent) percent. Tap to reset.")
            if readOnly {
                pillDivider
                Button { perform(.readOnly) } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.action)
                        .frame(width: 40, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Read only. Tap to edit.")
            }
        }
        .font(.footnote.monospacedDigit().weight(.semibold))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 4)
        .clearGlass(Capsule())
        .animation(.snappy, value: controller.pageIndex)
        .animation(.snappy, value: controller.zoomPercent)
    }

    private var pillDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 18)
    }

    private var pageBadge: some View {
        VStack(spacing: 1) {
            Text(currentNotebook.title).font(.footnote.weight(.semibold)).lineLimit(1)
            Text("Page \(controller.pageIndex + 1) of \(controller.pageCount)")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.82)))
    }

    // MARK: Pages sidebar & All Notes

    /// Swipe in from the left edge to open the pages panel (like Noteshelf).
    private var edgeSwipeArea: some View {
        Color.clear
            .frame(width: 18)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 14).onEnded { v in
                if v.translation.width > 40 { showSidebar = true }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .ignoresSafeArea()
    }

    private var sidebarLayer: some View {
        let nb = currentNotebook
        let ids = nb.pages
        return ZStack(alignment: .leading) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { showSidebar = false; showAllNotes = false }
                .transition(.opacity)
            HStack(spacing: 0) {
                if showAllNotes {
                    AllNotesPanel(current: notebook.id,
                                  onBack: { showAllNotes = false },
                                  onOpen: { other in
                                      controller.surface?.saveAll()
                                      onSwitch(other)
                                  })
                        .environmentObject(store)
                        .transition(.move(edge: .leading))
                }
                PageSidebar(title: nb.title,
                            template: nb.template, paper: nb.paper,
                            count: controller.pageCount, current: controller.pageIndex,
                            thumbnail: { i in controller.pages?.thumbnail(of: i, width: 120) },
                            bookmarked: { i in ids.indices.contains(i) && nb.isBookmarked(ids[i]) },
                            outlineTitle: { i in ids.indices.contains(i) ? nb.outlineTitle(ids[i]) : nil },
                            hasPhotos: { i in controller.pages?.pageHasPhotos(i) ?? false },
                            pageText: { i in controller.pages?.pageText(i) ?? "" },
                            onToggleBookmark: { i in
                                if ids.indices.contains(i) { store.toggleBookmark(notebookId: notebook.id, pageId: ids[i]) }
                            },
                            onSelect: { i in controller.pages?.jump(to: i) },
                            onAdd: { controller.pages?.addPage() },
                            onAllNotes: { showAllNotes.toggle() },
                            onClose: { showSidebar = false; showAllNotes = false })
                    .transition(.move(edge: .leading))
                    .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { v in
                        guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                        if v.translation.width > 60 {
                            showAllNotes = true
                        } else if v.translation.width < -60 {
                            if showAllNotes { showAllNotes = false } else { showSidebar = false }
                        }
                    })
            }
        }
        .zIndex(5)
    }

    // MARK: Actions

    private func closeMenus(then action: (() -> Void)? = nil) {
        showAdd = false
        showMore = false
        if let action {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
        }
    }

    private func perform(_ a: EditorAction) {
        switch a {
        case .addPage:
            closeMenus()
            controller.pages?.addPage()
            showToast("Page added")
        case .chooseTemplate, .background:
            closeMenus { showPaper = true }
        case .scanDocument:
            closeMenus { cover = .scanner }
        case .pageFromCamera:
            closeMenus { cover = .cameraPage }
        case .importFile:
            closeMenus { showImporter = true }
        case .camera:
            closeMenus { cover = .cameraPhoto }
        case .stickyNote:
            closeMenus()
            place { u in PageElement(kind: .sticky, x: u.x - 110, y: u.y - 110, w: 220, h: 220,
                                     text: "", colorHex: ElementView.softColors[0], fontSize: 24) }
        case .textBox:
            closeMenus()
            tools.tool = .text
            showToast("Tap the page to type")
        case .emoji(let e):
            closeMenus()
            place { u in PageElement(kind: .emoji, x: u.x - 45, y: u.y - 45, w: 90, h: 90, text: e) }
        case .sticker(let s):
            closeMenus()
            let parts = s.split(separator: "|").map(String.init)
            place { u in PageElement(kind: .emoji, x: u.x - 50, y: u.y - 50, w: 100, h: 100,
                                     colorHex: parts.count > 1 ? parts[1] : "#F5B700", symbol: parts.first) }
        case .sharePDF:
            closeMenus { exportPDF() }
        case .sharePNG:
            closeMenus { sharePNG() }
        case .savePhoto:
            closeMenus()
            savePageToPhotos()
        case .goToPage:
            closeMenus {
                goToText = ""
                showGoTo = true
            }
        case .bookmark:
            guard let pid = currentPageId else { return }
            store.toggleBookmark(notebookId: notebook.id, pageId: pid)
            showToast(currentNotebook.isBookmarked(pid) ? "Page bookmarked" : "Bookmark removed")
        case .outline:
            closeMenus {
                outlineText = currentPageId.flatMap(currentNotebook.outlineTitle) ?? "Page \(controller.pageIndex + 1)"
                showOutline = true
            }
        case .duplicatePage:
            closeMenus()
            controller.pages?.duplicateCurrentPage()
            showToast("Page duplicated")
        case .deletePage, .clearCanvas:
            closeMenus { confirmDeletePage = true }
        case .zoomBox:
            closeMenus()
            controller.pages?.toggleZoomBox()
            controller.zoomBoxOpen = controller.pages?.isZoomBoxOpen ?? false
            if controller.zoomBoxOpen && !tools.tool.inks && tools.tool != .eraser { tools.tool = .pen }
        case .readOnly:
            closeMenus()
            readOnly.toggle()
            showToast(readOnly ? "Read only" : "Editing")
        case .info:
            closeMenus { showInfo = true }
        case .customizeToolbar:
            closeMenus { showCustomize = true }
        case .tool(let t):
            closeMenus()
            tools.tool = t
            showToast(tools.toolTitle)
        case .allNotes:
            closeMenus()
            showSidebar = true
            showAllNotes = true
        case .search:
            closeMenus()
            showSidebar = true
        }
    }

    /// Puts a new object in the middle of the screen and switches to the
    /// object tool so it can be moved and resized straight away.
    private func place(_ make: @escaping (CGPoint) -> PageElement) {
        guard !readOnly else { showToast("Read only"); return }
        controller.surface?.placeObject(make)
        tools.tool = .text
        showToast("Drag to move · pull the corner to resize")
    }

    private func placePhoto(_ image: UIImage) {
        guard let name = store.saveImageAsset(image, notebookId: notebook.id) else { return }
        let ratio = image.size.height / max(image.size.width, 1)
        let w: CGFloat = ratio > 1.3 ? 260 : 380
        place { u in PageElement(kind: .image, x: u.x - w / 2, y: u.y - w * ratio / 2, w: w, h: w * ratio, imageFile: name) }
    }

    private func addPages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        if isCanvas {
            images.first.map(placePhoto)
            return
        }
        controller.pages?.insertPages(count: images.count, backgrounds: images)
        showToast(images.count == 1 ? "Page added" : "\(images.count) pages added")
    }

    private func load(_ item: PhotosPickerItem, then use: @escaping (UIImage) -> Void) {
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                use(img)
            }
        }
    }

    private func closeSqueeze() {
        withAnimation(.easeOut(duration: 0.15)) { controller.squeezePoint = nil }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    private func flashPageBadge() {
        guard !isCanvas else { return }
        badgeTask?.cancel()
        showPageBadge = true
        badgeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            showPageBadge = false
        }
    }

    private func exportPDF() {
        let nb = currentNotebook
        let nbId = nb.id
        let lib = store
        if let board = controller.board {
            let (drawing, elements, rect) = board.drawingForExport()
            if let url = PDFExporter.exportCanvas(title: nb.title, paper: nb.paper, drawing: drawing, elements: elements,
                                                  rect: rect, imageLoader: board.imageLoader) {
                shareItem = ShareItem(url: url)
            }
        } else if let pages = controller.pages,
                  let url = PDFExporter.export(title: nb.title, template: nb.template, paper: nb.paper,
                                               pages: pages.pageContents(),
                                               imageLoader: { lib.loadImageAsset($0, notebookId: nbId) }) {
            shareItem = ShareItem(url: url)
        }
    }

    private func sharePNG() {
        guard let pages = controller.pages,
              let image = pages.pageImage(controller.pageIndex, width: 1600),
              let url = PDFExporter.exportPNG(title: "\(currentNotebook.title) p\(controller.pageIndex + 1)", image: image)
        else { return }
        shareItem = ShareItem(url: url)
    }

    private func savePageToPhotos() {
        guard let image = controller.pages?.pageImage(controller.pageIndex, width: 1600) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showToast("Saved to Photos")
    }

    private func runDemoHooks() {
        if DemoMode.focus {
            focusMode = true
            showToast("Focus mode")
        }
        if let d = DemoMode.dock { dockRaw = d.rawValue } else if DemoMode.enabled { dockRaw = ToolbarDock.top.rawValue }
        if DemoMode.enabled { colorDockRaw = (DemoMode.colorsDock ?? .top).rawValue }
        if DemoMode.enabled { horizontal = DemoMode.horizontal }
        if DemoMode.enabled { tools.toolbarItems = DemoMode.customize ? ToolbarItemKind.defaults + [.tape, .zoomBox, .stickyNote] : ToolbarItemKind.defaults }
        if DemoMode.textTool { tools.tool = .text }
        let after = { (delay: Double, work: @escaping () -> Void) in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
        if DemoMode.showPen { after(1.2) { showToolSettings = true } }
        if DemoMode.squeeze { after(1.2) { withAnimation(.easeOut(duration: 0.2)) { controller.squeezePoint = CGPoint(x: 520, y: 640) } } }
        if DemoMode.sidebar { after(1.0) { showSidebar = true } }
        if DemoMode.allNotes { after(1.0) { showSidebar = true; showAllNotes = true } }
        if DemoMode.showAdd { after(1.2) { showAdd = true } }
        if DemoMode.showMore { after(1.2) { showMore = true } }
        if DemoMode.customize { after(1.2) { showCustomize = true } }
        if DemoMode.zoomBox { after(1.2) { perform(.zoomBox) } }
    }
}

/// Buttons shrink a little while pressed.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Small sheets

struct PaperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var template: PageTemplate
    @State var paper: PaperColor
    var isCanvas = false
    let onApply: (PageTemplate, PaperColor) -> Void

    private var templates: [PageTemplate] { isCanvas ? [.blank, .grid, .dotted, .ruled] : PageTemplate.allCases }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SectionTitle(text: "Paper Color")
                    HStack(spacing: 14) {
                        ForEach(PaperColor.allCases) { p in
                            Circle()
                                .fill(Color(uiColor: p.uiColor))
                                .frame(width: 38, height: 38)
                                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                                .overlay(Circle().stroke(Theme.action, lineWidth: paper == p ? 3 : 0).padding(-4))
                                .onTapGesture { withAnimation(.snappy) { paper = p } }
                        }
                    }
                    SectionTitle(text: isCanvas ? "Background" : "Template")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        ForEach(templates) { t in
                            VStack(spacing: 6) {
                                TemplateThumbnail(template: t, paper: paper)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.action, lineWidth: template == t ? 3 : 0))
                                Text(t.title).font(.caption)
                            }
                            .onTapGesture { withAnimation(.snappy) { template = t } }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle(isCanvas ? "Background" : "Paper & Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(template, paper)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
