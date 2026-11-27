import SwiftUI
import PencilKit

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
    /// Where Apple Pencil Pro was squeezed (opens the quick menu there).
    @Published var squeezePoint: CGPoint?
    @Published var doubleTaps = 0
}

/// Hosts the paged notebook or the infinite canvas.
struct SurfaceHost: UIViewControllerRepresentable {
    let store: LibraryStore
    let notebook: Notebook
    let tool: PKTool
    let inputMode: DrawingInput
    let ruler: Bool
    let controller: EditorController

    func makeUIViewController(context: Context) -> DrawingSurfaceController {
        let vc: DrawingSurfaceController = notebook.isCanvas
            ? CanvasViewController(store: store, notebook: notebook)
            : PagesViewController(store: store, notebook: notebook)
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    ctrl.squeezePoint = ctrl.squeezePoint == nil ? p : nil
                }
            }
        }
        vc.onDrawingStarted = {
            DispatchQueue.main.async {
                guard ctrl.squeezePoint != nil else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { ctrl.squeezePoint = nil }
            }
        }
        controller.surface = vc
        vc.setTool(tool)
        vc.setInputMode(inputMode)
        vc.setRuler(ruler)
        return vc
    }

    func updateUIViewController(_ vc: DrawingSurfaceController, context: Context) {
        vc.setTool(tool)
        vc.setInputMode(inputMode)
        vc.setRuler(ruler)
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

struct EditorView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var tools: ToolState
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook

    @StateObject private var controller = EditorController()
    @AppStorage("folio.toolbarDock") private var dockRaw = ToolbarDock.top.rawValue
    @State private var showToolSettings = false
    @State private var focusMode = false
    @State private var showPaper = false
    @State private var showSidebar = false
    @State private var confirmDeletePage = false
    @State private var shareItem: ShareItem?
    @State private var dragOffset: CGSize = .zero
    @State private var dragTarget: ToolbarDock?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var showPageBadge = false
    @State private var badgeTask: Task<Void, Never>?
    @Namespace private var toolNS

    private var dock: ToolbarDock { ToolbarDock(rawValue: dockRaw) ?? .top }
    private var isCanvas: Bool { notebook.isCanvas }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SurfaceHost(store: store, notebook: notebook, tool: tools.pkTool,
                            inputMode: tools.inputMode, ruler: tools.rulerActive, controller: controller)
                    .ignoresSafeArea()

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
                        .padding(.top, focusMode ? 14 : (dock == .top ? 128 : 70))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .zIndex(11)
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: focusMode)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showSidebar)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: toast)
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $showPaper) {
            PaperSheet(template: currentNotebook.template, paper: currentNotebook.paper) { t, p in
                controller.pages?.applyPaper(template: t, paper: p)
                controller.board?.applyPaper(template: t, paper: p)
            }
        }
        .confirmationDialog(isCanvas ? "Clear the whole canvas?" : "Delete this page?",
                            isPresented: $confirmDeletePage, titleVisibility: .visible) {
            Button(isCanvas ? "Clear Canvas" : "Delete Page \(controller.pageIndex + 1)", role: .destructive) {
                controller.pages?.deleteCurrentPage()
                controller.board?.clearAll()
            }
        } message: {
            Text("This can't be undone.")
        }
        .onChange(of: controller.doubleTaps) { _, _ in
            tools.toggleEraser()
            showToast(tools.toolTitle)
        }
        .onChange(of: controller.pageIndex) { _, _ in flashPageBadge() }
        .onAppear(perform: runDemoHooks)
    }

    private var currentNotebook: Notebook { store.notebook(notebook.id) ?? notebook }

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

            if let t = dragTarget {
                dockPlaceholder(t)
                    .transition(.opacity)
            }

            dockedTools(size: size)

            bottomPill
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 14)
                .padding(.bottom, 14)

            if showPageBadge && !isCanvas {
                pageBadge
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, dock == .bottom ? 128 : 22)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showPageBadge)
    }

    @ViewBuilder
    private func dockedTools(size: CGSize) -> some View {
        let bars = toolBars(vertical: dock.vertical)
            .offset(dragOffset)
            .gesture(dockDrag(size: size))
        switch dock {
        case .top:
            bars.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 8)
        case .bottom:
            bars.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 14)
        case .left:
            bars.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.leading, 14)
        case .right:
            bars.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.trailing, 14)
        }
    }

    @ViewBuilder
    private func toolBars(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
        let barsFirst = dock == .top || dock == .left
        GlassGroup(spacing: 14) {
            layout {
                if barsFirst { toolsGroup(vertical: vertical) }
                if tools.tool != .lasso {
                    contextBar(vertical: vertical)
                        .transition(.scale(scale: 0.9, anchor: barsFirst ? (vertical ? .leading : .top) : (vertical ? .trailing : .bottom))
                            .combined(with: .opacity))
                }
                if !barsFirst { toolsGroup(vertical: vertical) }
            }
        }
        .animation(.snappy(duration: 0.24), value: tools.tool)
    }

    private func dockDrag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { v in
                dragOffset = v.translation
                let target = nearestDock(v.location, in: size)
                if target != dragTarget {
                    withAnimation(.easeOut(duration: 0.15)) { dragTarget = target }
                }
            }
            .onEnded { v in
                let target = nearestDock(v.location, in: size)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                    dockRaw = target.rawValue
                    dragOffset = .zero
                    dragTarget = nil
                }
            }
    }

    private func nearestDock(_ p: CGPoint, in s: CGSize) -> ToolbarDock {
        let d: [(ToolbarDock, CGFloat)] = [(.top, p.y), (.bottom, s.height - p.y),
                                            (.left, p.x * 1.15), (.right, (s.width - p.x) * 1.15)]
        return d.min { $0.1 < $1.1 }?.0 ?? .top
    }

    private func dockPlaceholder(_ t: ToolbarDock) -> some View {
        let shape = Capsule()
        let fill = shape.fill(Theme.action.opacity(0.28))
            .overlay(shape.strokeBorder(Theme.action.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        return Group {
            switch t {
            case .top: fill.frame(width: 300, height: 50).frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
            case .bottom: fill.frame(width: 300, height: 50).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 14)
            case .left: fill.frame(width: 50, height: 300).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
            case .right: fill.frame(width: 50, height: 300).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14)
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
        .glassBackground(Capsule(), interactive: true)
    }

    private var rightGroup: some View {
        HStack(spacing: 0) {
            if !isCanvas {
                barButton("plus", label: "Add Page") { controller.pages?.addPage() }
            }
            barButton("arrow.up.left.and.arrow.down.right", label: "Focus Mode") {
                focusMode = true
                showToast("Focus mode")
            }
            Menu {
                if !isCanvas {
                    Button { showSidebar = true } label: { Label("Pages", systemImage: "square.grid.2x2") }
                }
                Button { showPaper = true } label: {
                    Label(isCanvas ? "Background" : "Paper & Template", systemImage: "doc.richtext")
                }
                Button { exportPDF() } label: { Label("Export as PDF", systemImage: "square.and.arrow.up") }
                Picker(selection: $tools.inputMode) {
                    ForEach(DrawingInput.allCases) { m in Text(m.title).tag(m) }
                } label: {
                    Label("Drawing Input", systemImage: "hand.draw")
                }
                Picker(selection: Binding(get: { dock }, set: { d in withAnimation(.spring) { dockRaw = d.rawValue } })) {
                    ForEach(ToolbarDock.allCases) { d in Text(d.title).tag(d) }
                } label: {
                    Label("Toolbar Position", systemImage: "rectangle.3.group")
                }
                Divider()
                Button(role: .destructive) { confirmDeletePage = true } label: {
                    Label(isCanvas ? "Clear Canvas" : "Delete Page", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
        .glassBackground(Capsule(), interactive: true)
    }

    private func toolsGroup(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            toolButton(.pen, symbol: tools.pen.kind.symbol, ink: tools.pen.colorHex, label: "Pen")
            toolButton(.highlighter, symbol: "highlighter", ink: tools.highlighter.colorHex, label: "Highlighter")
            toolButton(.eraser, symbol: "eraser", ink: nil, label: "Eraser")
            toolButton(.lasso, symbol: "lasso", ink: nil, label: "Lasso")
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: vertical ? 24 : 1, height: vertical ? 1 : 24)
                .padding(vertical ? .vertical : .horizontal, 4)
            Button {
                tools.rulerActive.toggle()
            } label: {
                Image(systemName: "ruler")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tools.rulerActive ? Theme.action : Color.primary)
                    .symbolEffect(.bounce, value: tools.rulerActive)
                    .frame(width: 42, height: 38)
                    .background(Capsule().fill(tools.rulerActive ? Theme.action.opacity(0.2) : Color.clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ruler")
            // Grip: drag the bar to any edge of the screen.
            Image(systemName: vertical ? "line.3.horizontal" : "line.3.horizontal")
                .rotationEffect(.degrees(vertical ? 0 : 90))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .frame(width: vertical ? 42 : 18, height: vertical ? 18 : 38)
                .contentShape(Rectangle())
                .accessibilityLabel("Move Toolbar")
        }
        .padding(vertical ? .vertical : .horizontal, 6)
        .frame(width: vertical ? 54 : nil, height: vertical ? nil : 50)
        .glassBackground(Capsule(), interactive: true)
        .popover(isPresented: $showToolSettings) {
            toolSettings
        }
    }

    private func toolButton(_ tool: EditorTool, symbol: String, ink: String?, label: String) -> some View {
        let selected = tools.tool == tool
        return Button {
            if selected {
                if tool == .pen || tool == .highlighter || tool == .eraser { showToolSettings = true }
            } else {
                tools.tool = tool
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: selected ? .semibold : .medium))
                    .symbolEffect(.bounce, value: selected)
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

    private func contextBar(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            switch tools.tool {
            case .pen:
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
            case .lasso:
                EmptyView()
            }
        }
        .padding(vertical ? .vertical : .horizontal, vertical ? 10 : 12)
        .frame(width: vertical ? 48 : nil, height: vertical ? nil : 46)
        .glassBackground(Capsule(), interactive: true)
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
            if selected { showToolSettings = true } else { select() }
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
        case .pen: PenSettingsView().environmentObject(tools)
        case .highlighter: HighlighterSettingsView().environmentObject(tools)
        case .eraser: EraserSettingsView().environmentObject(tools)
        case .lasso: EmptyView()
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
                Image(systemName: currentToolSymbol)
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
        .glassBackground(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
        .accessibilityLabel("Show Toolbar")
    }

    private var currentToolSymbol: String {
        switch tools.tool {
        case .pen: return tools.pen.kind.symbol
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        }
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
        }
        .font(.footnote.monospacedDigit().weight(.semibold))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 4)
        .glassBackground(Capsule(), interactive: true)
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

    // MARK: Pages sidebar

    private var sidebarLayer: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { showSidebar = false }
                .transition(.opacity)
            PageSidebar(title: currentNotebook.title,
                        template: currentNotebook.template, paper: currentNotebook.paper,
                        count: controller.pageCount, current: controller.pageIndex,
                        thumbnail: { i in controller.pages?.thumbnail(of: i, width: 120) },
                        onSelect: { i in controller.pages?.jump(to: i) },
                        onAdd: { controller.pages?.addPage() },
                        onClose: { showSidebar = false })
                .transition(.move(edge: .leading))
        }
        .zIndex(5)
    }

    // MARK: Helpers

    private func closeSqueeze() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { controller.squeezePoint = nil }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
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
        if let board = controller.board {
            let (drawing, rect) = board.drawingForExport()
            if let url = PDFExporter.exportCanvas(title: nb.title, paper: nb.paper, drawing: drawing, rect: rect) {
                shareItem = ShareItem(url: url)
            }
        } else if let pages = controller.pages,
                  let url = PDFExporter.export(title: nb.title, template: nb.template, paper: nb.paper,
                                               drawings: pages.drawingsForExport()) {
            shareItem = ShareItem(url: url)
        }
    }

    private func runDemoHooks() {
        if DemoMode.focus {
            focusMode = true
            showToast("Focus mode")
        }
        if let d = DemoMode.dock { dockRaw = d.rawValue } else if DemoMode.enabled { dockRaw = ToolbarDock.top.rawValue }
        if DemoMode.showPen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showToolSettings = true }
        }
        if DemoMode.squeeze {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.spring) { controller.squeezePoint = CGPoint(x: 520, y: 640) }
            }
        }
        if DemoMode.sidebar {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showSidebar = true }
        }
    }
}

/// Buttons shrink a little while pressed.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.88
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Small sheets

struct PaperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var template: PageTemplate
    @State var paper: PaperColor
    let onApply: (PageTemplate, PaperColor) -> Void

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
                    SectionTitle(text: "Template")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        ForEach(PageTemplate.allCases) { t in
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
            .navigationTitle("Paper & Template")
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
