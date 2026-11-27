import SwiftUI
import Combine
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
    /// Kept outside the controller's own @Published values: it changes every frame
    /// of a pinch, and redrawing the whole editor that often made zooming stutter.
    let zoom = ZoomReadout()
    @Published var zoomBoxOpen = false
    /// Where Apple Pencil Pro was squeezed (opens the quick menu there).
    @Published var squeezePoint: CGPoint?
    @Published var doubleTaps = 0
    @Published var zoomLocked = false
    @Published var fiveTaps = 0
    @Published var fourTaps = 0
    @Published var eraseEnds = 0
    @Published var lassoSwitches = 0
    /// Short messages from the page (e.g. "Undo" after a two-finger tap).
    @Published var messageCount = 0
    var lastMessage = ""
    /// Buttons on the card after the last page.
    let endCard = PassthroughSubject<EndCardAction, Never>()
}

@MainActor
final class ZoomReadout: ObservableObject {
    @Published var percent = 100
}

/// The "100%" in the bottom pill; only this redraws while you pinch.
private struct ZoomPercentText: View {
    @ObservedObject var readout: ZoomReadout
    var body: some View {
        Text("\(readout.percent)%")
            .contentTransition(.numericText())
            .animation(.snappy, value: readout.percent)
            .accessibilityLabel("Zoom \(readout.percent) percent")
    }
}

/// Hosts the paged notebook or the infinite canvas.
struct SurfaceHost: UIViewControllerRepresentable {
    let store: LibraryStore
    let notebook: Notebook
    let tool: InkTool
    let editorTool: EditorTool
    let feel: InkFeel
    let readOnly: Bool
    let horizontal: Bool
    let textColor: String
    let textSize: CGFloat
    let tapeColor: String
    let tapeWidth: CGFloat
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
            DispatchQueue.main.async { if ctrl.zoom.percent != z { ctrl.zoom.percent = z } }
        }
        vc.onPencilDoubleTap = { DispatchQueue.main.async { ctrl.doubleTaps += 1 } }
        vc.onFiveFingerTap = { DispatchQueue.main.async { ctrl.fiveTaps += 1 } }
        vc.onFourFingerTap = { DispatchQueue.main.async { ctrl.fourTaps += 1 } }
        vc.onEraseFinished = { DispatchQueue.main.async { ctrl.eraseEnds += 1 } }
        vc.onSwitchToLasso = { DispatchQueue.main.async { ctrl.lassoSwitches += 1 } }
        vc.onMessage = { m in
            DispatchQueue.main.async {
                ctrl.lastMessage = m
                ctrl.messageCount += 1
            }
        }
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
        (vc as? PagesViewController)?.onEndCard = { a in
            DispatchQueue.main.async { ctrl.endCard.send(a) }
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
        vc.tapeColorHex = tapeColor
        vc.tapeWidth = tapeWidth
        vc.setMode(tool: editorTool, feel: feel, readOnly: readOnly)
        if vc.zoomLocked != controller.zoomLocked { vc.zoomLocked = controller.zoomLocked }
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
private enum BarKind: Hashable { case tools, colors }

private struct BarSizeKey: PreferenceKey {
    static var defaultValue: [BarKind: CGSize] = [:]
    static func reduce(value: inout [BarKind: CGSize], nextValue: () -> [BarKind: CGSize]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Where a bar was dropped: its centre as fractions of the screen, and whether it stands upright.
private struct BarPlace {
    var x: CGFloat
    var y: CGFloat
    var vertical: Bool

    init(x: CGFloat, y: CGFloat, vertical: Bool) {
        self.x = x; self.y = y; self.vertical = vertical
    }

    init?(_ raw: String) {
        let p = raw.split(separator: ",").compactMap { Double($0) }
        guard p.count == 3 else { return nil }
        x = CGFloat(p[0]); y = CGFloat(p[1]); vertical = p[2] > 0.5
    }

    var raw: String { "\(Double(x)),\(Double(y)),\(vertical ? 1 : 0)" }
}

/// A copied page, kept while the app runs so it can be pasted into any notebook.
struct PageClip {
    let notebookId: UUID
    let pageId: UUID
    static var current: PageClip?
}

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
    /// Set inside split screen: the back arrow closes just this side.
    var onClose: (() -> Void)? = nil
    /// Opens another notebook next to this one (nil while already split).
    var onSplit: ((Notebook) -> Void)? = nil
    /// One side of split screen: no pages panel or All Notes here.
    var inSplit = false
    /// In split screen only one side shows the tool and colour bars (the tools are shared).
    var showsToolBars = true

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
    /// Free positions of the bars after the user moves them ("x,y,vertical", x/y as fractions of the screen).
    @AppStorage("folio.toolsPlace") private var toolsPlaceRaw = ""
    @AppStorage("folio.colorsPlace") private var colorsPlaceRaw = ""
    @State private var barSizes: [BarKind: CGSize] = [:]
    @State private var barMovedAt = Date.distantPast
    @State private var showPenTypes = false
    @State private var editingColor: Int?
    @State private var editingSize: Int?
    @State private var pageClip: PageClip? = PageClip.current
    @State private var pendingDeleteIndex: Int?
    @State private var showSplitPicker = false
    @State private var showAddSpace = false
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
    @State private var showPomodoro = false
    @State private var showPomodoroFromPill = false
    @Namespace private var toolNS

    /// Both bars stay fixed along the top edge.
    private var toolsDock: ToolbarDock { .top }
    private var colorsDock: ToolbarDock { .top }

    /// The screen edge a freely placed bar is closest to.
    private static func edge(_ p: BarPlace) -> ToolbarDock {
        if p.vertical { return p.x < 0.5 ? .left : .right }
        return p.y < 0.5 ? .top : .bottom
    }

    /// True for a moment after a bar was dragged, so the button under the finger doesn't fire.
    private var barJustMoved: Bool { Date().timeIntervalSince(barMovedAt) < 0.5 }
    private var isCanvas: Bool { notebook.isCanvas }
    private var currentNotebook: Notebook { store.notebook(notebook.id) ?? notebook }
    private var currentPageId: UUID? {
        let pages = currentNotebook.pages
        return pages.indices.contains(controller.pageIndex) ? pages[controller.pageIndex] : nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SurfaceHost(store: store, notebook: notebook, tool: tools.inkTool, editorTool: tools.tool,
                            feel: tools.pen.inkFeel, readOnly: readOnly, horizontal: horizontal,
                            textColor: tools.textColorHex, textSize: tools.textSize,
                            tapeColor: tools.tapeColorHex, tapeWidth: tools.tapeWidth,
                            inputMode: tools.inputMode, ruler: tools.rulerActive, controller: controller)
                    .ignoresSafeArea()

                if !isCanvas && !showSidebar && !inSplit {
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

                if showSidebar && !isCanvas && !inSplit {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture { showSidebar = false; showAllNotes = false }
                        .transition(.opacity)
                        .zIndex(5)
                    sidebarLayer
                        .transition(.move(edge: .leading))
                        .zIndex(6)
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

                if showAddSpace, let pages = controller.pages {
                    AddSpaceView(pageImage: pages.thumbnail(of: controller.pageIndex, width: 700),
                                 pageSize: pages.currentPageSize,
                                 canApplyToAll: controller.pageCount > 1,
                                 onCancel: { showAddSpace = false },
                                 onDone: { add, all in
                                     showAddSpace = false
                                     guard add != .zero else { return }
                                     pages.addSpace(add, allPages: all)
                                     showToast(all ? "Space added to every page" : "Space added")
                                 })
                        .transition(.opacity)
                        .zIndex(20)
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
        .animation(.easeOut(duration: 0.22), value: showAddSpace)
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
            showToast("Importing \(url.lastPathComponent)…")
            Task { @MainActor in
                // A PDF is kept as the PDF itself: sharp at any zoom and small on disk.
                if !isCanvas, FileImporter.isPDF(url), let pages = controller.pages {
                    let n = FileImporter.withAccess(to: url) { pages.insertPDF(url) }
                    if n > 0 {
                        showToast(n == 1 ? "Page added" : "\(n) pages added")
                        return
                    }
                }
                let images = await FileImporter.pages(from: url)
                if images.isEmpty { showToast("Couldn't open that file"); return }
                if isCanvas { images.first.map(placePhoto) } else { addPages(images) }
            }
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
            Button(isCanvas ? "Clear Canvas" : "Delete Page \((pendingDeleteIndex ?? controller.pageIndex) + 1)", role: .destructive) {
                controller.pages?.deletePage(at: pendingDeleteIndex ?? controller.pageIndex)
                pendingDeleteIndex = nil
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
        .onChange(of: controller.messageCount) { _, _ in showToast(controller.lastMessage) }
        .onChange(of: controller.fiveTaps) { _, _ in startSplit() }
        .onChange(of: controller.fourTaps) { _, _ in
            focusMode.toggle()
            showToast(focusMode ? "Focus mode" : "Focus mode off")
        }
        .onChange(of: controller.eraseEnds) { _, _ in tools.leaveEraser() }
        .onChange(of: controller.lassoSwitches) { _, _ in tools.tool = .lasso }
        .sheet(isPresented: $showSplitPicker) {
            SplitPicker(current: notebook.id) { other in
                showSplitPicker = false
                controller.surface?.saveAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onSplit?(other) }
            }
            .environmentObject(store)
        }
        .onChange(of: controller.zoomLocked) { _, locked in controller.surface?.zoomLocked = locked }
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
        .onReceive(controller.endCard) { a in
            switch a {
            case .newPage: perform(.addPage)
            case .template: perform(.chooseTemplate)
            case .importFile: perform(.importFile)
            case .scan: perform(.scanDocument)
            case .camera: perform(.pageFromCamera)
            case .image(let img): addPages([img])
            }
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

            if showsToolBars {
                placed(.tools, size: size)
            }
            if showsToolBars && tools.tool.hasContextBar && !readOnly {
                placed(.colors, size: size)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }

            bottomPill
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 14)
                .padding(.bottom, 14)

            // The Pomodoro countdown, while one is running or paused.
            if showsToolBars {
                PomodoroBadge(timer: Pomodoro.shared, onTap: { showPomodoroFromPill = true }, onFinish: { p in
                    showToast(p == .focus ? "Focus session done. Take a break" : "Break's over. Time to focus")
                })
                .popover(isPresented: $showPomodoroFromPill) { PomodoroPanel(timer: Pomodoro.shared) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 14)
                .padding(.bottom, (toolsDock == .bottom || colorsDock == .bottom) ? 76 : 14)
            }
            // Split screen flashes both sides from its own view.
            if !inSplit { PomodoroEdgeFlash(timer: Pomodoro.shared) }

            if showPageBadge && !isCanvas {
                pageBadge
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, (toolsDock == .bottom || colorsDock == .bottom) ? 128 : 22)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showPageBadge)
        .onPreferenceChange(BarSizeKey.self) { barSizes = $0 }
        .animation(.easeOut(duration: 0.2), value: tools.tool.hasContextBar)
        // The bars are see-through, so their icons follow the paper, not the system theme.
        .environment(\.colorScheme, currentNotebook.paper == .dark ? .dark : .light)
    }

    private func dock(of bar: BarKind) -> ToolbarDock { bar == .tools ? toolsDock : colorsDock }

    private func place(of bar: BarKind) -> BarPlace? { nil }

    private func isVertical(_ bar: BarKind) -> Bool { place(of: bar)?.vertical ?? dock(of: bar).vertical }

    /// The bar's size, swapped if it was measured before it turned upright (or flat).
    private func barSize(_ bar: BarKind) -> CGSize {
        let v = isVertical(bar)
        guard let s = barSizes[bar] else {
            let long: CGFloat = bar == .tools ? 330 : 260
            return v ? CGSize(width: 54, height: long) : CGSize(width: long, height: 50)
        }
        return (s.height > s.width) == v ? s : CGSize(width: s.height, height: s.width)
    }

    /// Where the bar's centre goes: wherever it was dropped, or its default spot on its edge.
    private func center(of bar: BarKind, in size: CGSize) -> CGPoint {
        let sz = barSize(bar)
        var p: CGPoint
        if let pl = place(of: bar) {
            p = CGPoint(x: pl.x * size.width, y: pl.y * size.height)
        } else {
            let d = dock(of: bar)
            // With both bars on the same edge the colour bar sits just inside the tools bar.
            let extra: CGFloat = (bar == .colors && place(of: .tools) == nil && toolsDock == colorsDock)
                ? (d.vertical ? 62 : 58) : 0
            switch d {
            // In a narrow window (split screen) the top bars drop below the back, + and ⋯ buttons.
            case .top: p = CGPoint(x: size.width / 2, y: 8 + (size.width < 820 ? 58 : 0) + extra + sz.height / 2)
            case .bottom: p = CGPoint(x: size.width / 2, y: size.height - 14 - extra - sz.height / 2)
            case .left: p = CGPoint(x: 14 + extra + sz.width / 2, y: size.height / 2)
            case .right: p = CGPoint(x: size.width - 14 - extra - sz.width / 2, y: size.height / 2)
            }
        }
        // Keep the whole bar on screen.
        p.x = min(max(p.x, sz.width / 2 + 8), max(sz.width / 2 + 8, size.width - sz.width / 2 - 8))
        p.y = min(max(p.y, sz.height / 2 + 8), max(sz.height / 2 + 8, size.height - sz.height / 2 - 8))
        return p
    }

    @ViewBuilder
    private func placed(_ bar: BarKind, size: CGSize) -> some View {
        let vertical = isVertical(bar)
        let c = center(of: bar, in: size)
        let lifted = dragBar == bar
        Group {
            if bar == .tools { toolsGroup(vertical: vertical, size: size) } else { contextBar(vertical: vertical) }
        }
        .fixedSize()
        .background(GeometryReader { g in Color.clear.preference(key: BarSizeKey.self, value: [bar: g.size]) })
        .scaleEffect(lifted ? 1.06 : 1)
        .shadow(color: .black.opacity(lifted ? 0.2 : 0), radius: 16, x: 0, y: 8)
        .position(x: c.x + (lifted ? dragOffset.width : 0), y: c.y + (lifted ? dragOffset.height : 0))
    }

    /// Where a dropped bar lands: snapped flat against the nearest screen edge, upright on the
    /// left and right edges, keeping clear of the corner buttons and of the other bar.
    private func snapped(_ bar: BarKind, droppedAt p: CGPoint, in size: CGSize) -> (center: CGPoint, vertical: Bool) {
        let w = size.width, h = size.height
        let edges: [(ToolbarDock, CGFloat)] = [(.left, p.x), (.right, w - p.x), (.top, p.y), (.bottom, h - p.y)]
        let edge = edges.min { $0.1 < $1.1 }?.0 ?? .top
        let vertical = edge.vertical
        let s0 = barSize(bar)
        let sz = (s0.height > s0.width) == vertical ? s0 : CGSize(width: s0.height, height: s0.width)
        let margin: CGFloat = 14
        // Keeps a value inside a range, or centres it when the range is too small.
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat, mid: CGFloat) -> CGFloat {
            lo <= hi ? min(max(v, lo), hi) : mid
        }
        // The back/undo buttons sit top left, the notebook buttons top right, the page pill bottom left.
        let topClear: CGFloat = w < 820 ? 66 : 8
        let cornerW: CGFloat = 290
        var c: CGPoint
        switch edge {
        case .left, .right:
            let x = edge == .left ? margin + sz.width / 2 : w - margin - sz.width / 2
            c = CGPoint(x: x, y: clamp(p.y, 64 + sz.height / 2, h - 64 - sz.height / 2, mid: h / 2))
        case .top:
            let y = topClear + sz.height / 2
            let lo = w < 820 ? margin + sz.width / 2 : cornerW + sz.width / 2
            let hi = w < 820 ? w - margin - sz.width / 2 : w - cornerW - sz.width / 2
            c = CGPoint(x: clamp(p.x, lo, hi, mid: w / 2), y: y)
        case .bottom:
            let y = h - margin - sz.height / 2
            c = CGPoint(x: clamp(p.x, 190 + sz.width / 2, w - margin - sz.width / 2, mid: w / 2), y: y)
        }
        // Don't land on top of the other bar: stack just inside it instead.
        let other: BarKind = bar == .tools ? .colors : .tools
        let otherShown = other == .tools ? showsToolBars : (showsToolBars && tools.tool.hasContextBar && !readOnly)
        if otherShown {
            let oc = center(of: other, in: size), os = barSize(other)
            let oRect = CGRect(x: oc.x - os.width / 2, y: oc.y - os.height / 2, width: os.width, height: os.height)
            let mine = CGRect(x: c.x - sz.width / 2, y: c.y - sz.height / 2, width: sz.width, height: sz.height)
            if mine.insetBy(dx: -4, dy: -4).intersects(oRect) {
                switch edge {
                case .left: c.x = oRect.maxX + 8 + sz.width / 2
                case .right: c.x = oRect.minX - 8 - sz.width / 2
                case .top: c.y = oRect.maxY + 8 + sz.height / 2
                case .bottom: c.y = oRect.minY - 8 - sz.height / 2
                }
            }
        }
        return (c, vertical)
    }

    /// Hold a bar for a moment, then it follows your finger; let go and it snaps to the nearest
    /// edge, standing upright on the left and right.
    private func moveGesture(_ bar: BarKind, size: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragBar != bar {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeOut(duration: 0.15)) { dragBar = bar }
                }
                let t = drag?.translation ?? .zero
                if hypot(t.width, t.height) > 4 { barMovedAt = Date() }
                dragOffset = t
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value,
                      hypot(drag.translation.width, drag.translation.height) > 4 else {
                    withAnimation(.easeOut(duration: 0.15)) { dragOffset = .zero; dragBar = nil }
                    return
                }
                barMovedAt = Date()
                let c = center(of: bar, in: size)
                let p = CGPoint(x: c.x + drag.translation.width, y: c.y + drag.translation.height)
                let s = snapped(bar, droppedAt: p, in: size)
                let raw = BarPlace(x: s.center.x / max(size.width, 1), y: s.center.y / max(size.height, 1),
                                   vertical: s.vertical).raw
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    if bar == .tools { toolsPlaceRaw = raw } else { colorsPlaceRaw = raw }
                    dragOffset = .zero
                    dragBar = nil
                }
            }
    }

    private var leftGroup: some View {
        HStack(spacing: 0) {
            barButton("chevron.left", label: "Back to Library") {
                controller.surface?.saveAll()
                if let onClose { onClose() } else { dismiss() }
            }
            if !isCanvas && !inSplit {
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
                             toolsDock: Binding(get: { toolsDock }, set: { d in withAnimation(.spring) { dockRaw = d.rawValue; toolsPlaceRaw = "" } }),
                             colorsDock: Binding(get: { colorsDock }, set: { d in withAnimation(.spring) { colorDockRaw = d.rawValue; colorsPlaceRaw = "" } }),
                             onAction: perform)
                }
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
        .clearGlass(Capsule())
    }

    // MARK: Tools bar

    private var extraItems: [ToolbarItemKind] {
        tools.toolbarItems.filter { !(isCanvas && $0.pagedOnly) && !(inSplit && ($0 == .allNotes || $0 == .search)) }
    }

    private func toolsGroup(vertical: Bool, size: CGSize) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        let items = extraItems
        // Leave room for the side groups; extra tools scroll when they don't fit.
        let available = vertical ? size.height - 170 : size.width - (toolsDock == .top && size.width >= 820 ? 430 : 60)
        let room = max(88, available - 232)
        let extrasLength = CGFloat(items.count) * 44
        return layout {
            toolButton(.pen, symbol: tools.pen.kind.symbol, ink: nil, label: "Pen")
                .popover(isPresented: $showPenTypes) {
                    PenTypePicker().environmentObject(tools)
                }
            toolButton(.highlighter, symbol: "highlighter", ink: nil, label: "Highlighter")
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
            case .timer:
                Button { if !barJustMoved { showPomodoro = true } } label: { PomodoroToolIcon(timer: Pomodoro.shared) }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(item.title)
                    .popover(isPresented: $showPomodoro) { PomodoroPanel(timer: Pomodoro.shared) }
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
        Button { if !barJustMoved { action() } } label: { extraIcon(item.symbol, on: on) }
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
            guard !barJustMoved else { return }
            if selected {
                // Tapping the chosen pen again offers the pen types; the eraser shows its options.
                if tool == .pen { showPenTypes = true }
                if tool == .eraser { showToolSettings = true }
            } else {
                tools.tool = tool
                if tool == .text { showToast("Tap the page to type") }
                if tool == .tape { showToast("Drag across writing to cover it") }
                if tool == .shapes { showToast("Draw a shape and it snaps clean") }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: selected ? .semibold : .medium))
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
            switch tools.tool {
            case .pen, .shapes:
                colorSlots(\.penQuickColors, current: \.pen.colorHex)
                barDivider(vertical)
                sizeSlots(\.penQuickSizes, current: \.pen.width, range: tools.pen.kind.widthRange, color: tools.pen.colorHex)
            case .highlighter:
                colorSlots(\.highlighterQuickColors, current: \.highlighter.colorHex)
                barDivider(vertical)
                sizeSlots(\.highlighterQuickSizes, current: \.highlighter.width, range: 4...60, color: tools.highlighter.colorHex)
            case .eraser:
                eraserModeButton(.stroke, symbol: "scribble", label: "Whole Stroke", compact: vertical)
                eraserModeButton(.pixel, symbol: "circle.dotted", label: "Precise", compact: vertical)
                if tools.eraserMode == .pixel {
                    barDivider(vertical)
                    sizeSlots(\.eraserQuickSizes, current: \.eraserWidth, range: 4...100, color: "#8E8E93")
                }
            case .tape:
                ForEach(ElementView.tapeColors, id: \.self) { hex in
                    quickColor(hex: hex, selected: tools.tapeColorHex == hex) { tools.tapeColorHex = hex }
                }
                barDivider(vertical)
                sizeSlots(\.tapeQuickSizes, current: \.tapeWidth, range: 8...90, color: tools.tapeColorHex, flat: true)
            case .text:
                ForEach(Array((["#1C1C1E"] + tools.penQuickColors).enumerated()), id: \.offset) { _, hex in
                    quickColor(hex: hex, selected: tools.textColorHex == hex) {
                        tools.textColorHex = hex
                    }
                }
                barDivider(vertical)
                ForEach(Array([16, 22, 32].enumerated()), id: \.offset) { i, s in
                    Button { if !barJustMoved { tools.textSize = CGFloat(s) } } label: {
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
        .animation(.snappy(duration: 0.2), value: tools.penQuickColors)
        .animation(.snappy(duration: 0.2), value: tools.highlighterQuickColors)
        .onChange(of: tools.tool) { _, _ in editingColor = nil; editingSize = nil }
    }

    /// The three size holes for a tool. Tap one to use it; tap the one in use to fine-tune it with a slider.
    @ViewBuilder
    private func sizeSlots(_ slots: ReferenceWritableKeyPath<ToolState, [CGFloat]>,
                           current: ReferenceWritableKeyPath<ToolState, CGFloat>,
                           range: ClosedRange<CGFloat>, color: String, flat: Bool = false) -> some View {
        let list = tools[keyPath: slots]
        ForEach(Array(list.prefix(3).enumerated()), id: \.offset) { i, w in
            let selected = abs(tools[keyPath: current] - w) < 0.05
            quickSize(index: i, value: w, range: range, selected: selected) {
                if selected { editingSize = i } else { tools[keyPath: current] = w }
            }
            .popover(isPresented: Binding(get: { editingSize == i }, set: { if !$0 { editingSize = nil } })) {
                SizeSlotPicker(
                    value: Binding(
                        get: { tools[keyPath: slots].indices.contains(i) ? tools[keyPath: slots][i] : w },
                        set: { new in
                            let v = (new * 10).rounded() / 10
                            if tools[keyPath: slots].indices.contains(i) { tools[keyPath: slots][i] = v }
                            tools[keyPath: current] = v
                        }),
                    range: range, colorHex: color, flat: flat)
            }
        }
    }

    /// The colour holes for a tool. Tap one to use it; tap the one in use to change its colour
    /// (or delete it); + adds another hole.
    @ViewBuilder
    private func colorSlots(_ slots: ReferenceWritableKeyPath<ToolState, [String]>,
                            current: ReferenceWritableKeyPath<ToolState, String>) -> some View {
        let list = tools[keyPath: slots]
        ForEach(Array(list.enumerated()), id: \.offset) { i, hex in
            let selected = tools[keyPath: current].lowercased() == hex.lowercased()
            quickColor(hex: hex, selected: selected) {
                if selected { editingColor = i } else { tools[keyPath: current] = hex }
            }
            .popover(isPresented: Binding(get: { editingColor == i }, set: { if !$0 { editingColor = nil } })) {
                ColorSlotPicker(
                    hex: Binding(
                        get: { tools[keyPath: slots].indices.contains(i) ? tools[keyPath: slots][i] : hex },
                        set: { new in
                            if tools[keyPath: slots].indices.contains(i) { tools[keyPath: slots][i] = new }
                            tools[keyPath: current] = new
                        }),
                    onDelete: list.count > 1 ? {
                        editingColor = nil
                        var l = tools[keyPath: slots]
                        guard l.indices.contains(i) else { return }
                        l.remove(at: i)
                        tools[keyPath: slots] = l
                        if let first = l.first, !l.contains(tools[keyPath: current]) { tools[keyPath: current] = first }
                    } : nil)
            }
        }
        if list.count < 8 {
            Button {
                guard !barJustMoved else { return }
                var l = tools[keyPath: slots]
                l.append(tools[keyPath: current])
                tools[keyPath: slots] = l
                let index = l.count - 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { editingColor = index }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.6), lineWidth: 1.2))
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Add Colour")
        }
    }

    private func barDivider(_ vertical: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: vertical ? 22 : 1, height: vertical ? 1 : 22)
    }

    private func quickColor(hex: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if !barJustMoved { action() }
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
    }

    private func quickSize(index: Int, value: CGFloat, range: ClosedRange<CGFloat>, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        // The line gets thicker with the real size, so a tuned size still looks right.
        let t = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.01)
        return Button { if !barJustMoved { action() } } label: {
            Capsule()
                .fill(Color.primary)
                .frame(width: 20, height: 1.5 + sqrt(min(max(t, 0), 1)) * 8)
                .frame(width: 40, height: 30)
                .background(Capsule().fill(selected ? Theme.action.opacity(0.25) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(["Thin", "Medium", "Thick"][index])
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
        return Button { if !barJustMoved { tools.eraserMode = mode } } label: {
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
            Image(systemName: tools.toolSymbol)
                .font(.system(size: 20, weight: .medium))
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
            Menu {
                Button { controller.surface?.resetZoom() } label: {
                    Label(isCanvas ? "Zoom to 100%" : "Zoom to Fit Page", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                }
                Button { controller.zoomLocked.toggle() } label: {
                    Label(controller.zoomLocked ? "Unlock Zoom" : "Lock Zoom",
                          systemImage: controller.zoomLocked ? "lock.open" : "lock")
                }
            } label: {
                HStack(spacing: 4) {
                    if controller.zoomLocked {
                        Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                    }
                    ZoomPercentText(readout: controller.zoom)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if readOnly {
                pillDivider
                Button { perform(.readOnly) } label: {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.action)
                        .frame(width: 40, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Reading mode. Tap to edit.")
            }
        }
        .font(.footnote.monospacedDigit().weight(.semibold))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 4)
        .clearGlass(Capsule())
        .animation(.snappy, value: controller.pageIndex)
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
        return HStack(spacing: 0) {
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
                            onClose: { showSidebar = false; showAllNotes = false },
                            canPaste: pageClip != nil,
                            onPageAction: pageAction,
                            onMovePages: { list, to in
                                controller.pages?.movePages(list, to: to)
                                showToast(list.count == 1 ? "Page moved" : "\(list.count) pages moved")
                            },
                            onDeletePages: { list in
                                controller.pages?.deletePages(list)
                                showToast(list.count == 1 ? "Page deleted" : "\(list.count) pages deleted")
                            },
                            onExportPages: exportPDF(pages:))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Actions

    /// Five-finger tap or More > Split Screen: pick a notebook to open next to this one.
    private func startSplit() {
        guard onSplit != nil else {
            showToast("Already in split screen")
            return
        }
        showSplitPicker = true
    }

    private func pageAction(_ i: Int, _ action: PageAction) {
        guard let pages = controller.pages else { return }
        switch action {
        case .copy:
            guard let pid = pages.pageId(at: i) else { return }
            pages.saveAll()
            PageClip.current = PageClip(notebookId: notebook.id, pageId: pid)
            pageClip = PageClip.current
            showToast("Page \(i + 1) copied")
        case .paste:
            guard let c = pageClip else { return }
            pages.pastePage(from: c.notebookId, pageId: c.pageId, at: i + 1)
            showToast("Page pasted")
        case .duplicate:
            pages.duplicatePage(at: i)
        case .bookmark:
            if let pid = pages.pageId(at: i) { store.toggleBookmark(notebookId: notebook.id, pageId: pid) }
        case .addBefore:
            pages.insertPages(count: 1, backgrounds: [], at: i)
        case .addAfter:
            pages.insertPages(count: 1, backgrounds: [], at: i + 1)
        case .delete:
            pendingDeleteIndex = i
            confirmDeletePage = true
        }
    }

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
        case .splitScreen:
            closeMenus { startSplit() }
        case .addSpace:
            closeMenus { if controller.pages != nil { showAddSpace = true } }
        case .readOnly:
            closeMenus()
            readOnly.toggle()
            showToast(readOnly ? "Reading mode: the Pencil scrolls" : "Editing")
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
            guard !inSplit else { showToast("Close split screen to see All Notes"); return }
            showSidebar = true
            showAllNotes = true
        case .search:
            closeMenus()
            guard !inSplit else { showToast("Close split screen to search pages"); return }
            showSidebar = true
        }
    }

    /// Puts a new object in the middle of the screen and switches to the
    /// object tool so it can be moved and resized straight away.
    private func place(_ make: @escaping (CGPoint) -> PageElement) {
        guard !readOnly else { showToast("Reading mode"); return }
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

    /// Some of the pages as a PDF (a selection or a range from the page sidebar).
    private func exportPDF(pages list: [Int]) {
        let nb = currentNotebook
        let nbId = nb.id
        let lib = store
        guard let pages = controller.pages, !list.isEmpty else { return }
        let sorted = list.sorted()
        let range = sorted.count == 1 ? "p\(sorted[0] + 1)" : "p\(sorted[0] + 1)-\(sorted[sorted.count - 1] + 1)"
        if let url = PDFExporter.export(title: "\(nb.title) \(range)", template: nb.template, paper: nb.paper,
                                        pages: pages.pageContents(sorted),
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
        if DemoMode.enabled { toolsPlaceRaw = ""; colorsPlaceRaw = "" }
        if let d = DemoMode.dock { dockRaw = d.rawValue } else if DemoMode.enabled { dockRaw = ToolbarDock.top.rawValue }
        if DemoMode.enabled { colorDockRaw = (DemoMode.colorsDock ?? .top).rawValue }
        if DemoMode.enabled { horizontal = DemoMode.horizontal }
        if DemoMode.enabled { tools.toolbarItems = DemoMode.customize ? ToolbarItemKind.defaults + [.tape, .zoomBox, .stickyNote] : ToolbarItemKind.defaults }
        if DemoMode.textTool { tools.tool = .text }
        if DemoMode.tapeTool { tools.tool = .tape }
        let after = { (delay: Double, work: @escaping () -> Void) in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
        if DemoMode.showPen { after(1.2) { showPenTypes = true } }
        if DemoMode.editColor { tools.tool = .pen; tools.pen.colorHex = tools.penQuickColors[0]; after(1.2) { editingColor = 0 } }
        if DemoMode.squeeze { after(1.2) { withAnimation(.easeOut(duration: 0.2)) { controller.squeezePoint = CGPoint(x: 520, y: 640) } } }
        if DemoMode.sidebar { after(1.0) { showSidebar = true } }
        if DemoMode.allNotes { after(1.0) { showSidebar = true; showAllNotes = true } }
        if DemoMode.showAdd { after(1.2) { showAdd = true } }
        if DemoMode.showMore { after(1.2) { showMore = true } }
        if DemoMode.customize { after(1.2) { showCustomize = true } }
        if DemoMode.zoomBox { after(1.2) { perform(.zoomBox) } }
        if DemoMode.addSpace { after(1.2) { showAddSpace = true } }
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
