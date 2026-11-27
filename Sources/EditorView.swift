import SwiftUI
import PencilKit

@MainActor
final class EditorController: ObservableObject {
    weak var vc: PagesViewController?
    @Published var pageIndex = 0
    @Published var pageCount = 1
    @Published var canUndo = false
    @Published var canRedo = false
}

struct PagesHost: UIViewControllerRepresentable {
    let store: LibraryStore
    let notebook: Notebook
    let tool: PKTool
    let inputMode: DrawingInput
    let ruler: Bool
    let controller: EditorController

    func makeUIViewController(context: Context) -> PagesViewController {
        let vc = PagesViewController(store: store, notebook: notebook)
        let ctrl = controller
        vc.onPageChanged = { i, n in
            DispatchQueue.main.async {
                ctrl.pageIndex = i
                ctrl.pageCount = n
            }
        }
        vc.onUndoChanged = { u, r in
            DispatchQueue.main.async {
                ctrl.canUndo = u
                ctrl.canRedo = r
            }
        }
        controller.vc = vc
        vc.setTool(tool)
        vc.setInputMode(inputMode)
        vc.setRuler(ruler)
        return vc
    }

    func updateUIViewController(_ vc: PagesViewController, context: Context) {
        vc.setTool(tool)
        vc.setInputMode(inputMode)
        vc.setRuler(ruler)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct EditorView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var tools: ToolState
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook

    @StateObject private var controller = EditorController()
    @State private var showToolSettings = false
    @State private var focusMode = false
    @State private var showPaper = false
    @State private var showPages = false
    @State private var confirmDeletePage = false
    @State private var shareItem: ShareItem?

    var body: some View {
        ZStack(alignment: .top) {
            PagesHost(store: store, notebook: notebook, tool: tools.pkTool,
                      inputMode: tools.inputMode, ruler: tools.rulerActive, controller: controller)
                .ignoresSafeArea()

            if focusMode {
                HStack {
                    Spacer()
                    focusExitButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            } else {
                toolbars
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .bottom) {
            if !focusMode { pagePill }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $showPaper) {
            PaperSheet(template: currentNotebook.template, paper: currentNotebook.paper) { t, p in
                controller.vc?.applyPaper(template: t, paper: p)
            }
        }
        .sheet(isPresented: $showPages) {
            PageNavigatorSheet(count: controller.pageCount, current: controller.pageIndex) { i in
                controller.vc?.jump(to: i)
            }
        }
        .confirmationDialog("Delete this page?", isPresented: $confirmDeletePage, titleVisibility: .visible) {
            Button("Delete Page \(controller.pageIndex + 1)", role: .destructive) {
                controller.vc?.deleteCurrentPage()
            }
        } message: {
            Text("This can't be undone.")
        }
        .onAppear {
            if DemoMode.focus { focusMode = true }
            if DemoMode.showPen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showToolSettings = true }
            }
        }
    }

    private var currentNotebook: Notebook { store.notebook(notebook.id) ?? notebook }

    // MARK: Toolbars

    private var toolbars: some View {
        GlassGroup(spacing: 16) {
            ZStack(alignment: .top) {
                HStack(alignment: .top) {
                    leftGroup
                    Spacer()
                    rightGroup
                }
                VStack(spacing: 8) {
                    toolsGroup
                    if tools.tool != .lasso {
                        contextBar
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    }
                }
                .animation(.snappy(duration: 0.22), value: tools.tool)
            }
        }
    }

    private var leftGroup: some View {
        HStack(spacing: 0) {
            barButton("chevron.left", label: "Back to Library") {
                controller.vc?.saveAll()
                dismiss()
            }
            barButton("square.grid.2x2", label: "Pages") { showPages = true }
            barButton("arrow.uturn.backward", label: "Undo", enabled: controller.canUndo) {
                controller.vc?.performUndo()
            }
            barButton("arrow.uturn.forward", label: "Redo", enabled: controller.canRedo) {
                controller.vc?.performRedo()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
        .glassBackground(Capsule(), interactive: true)
    }

    private var rightGroup: some View {
        HStack(spacing: 0) {
            barButton("plus", label: "Add Page") { controller.vc?.addPage() }
            barButton("arrow.up.left.and.arrow.down.right", label: "Focus Mode") {
                withAnimation(.snappy) { focusMode = true }
            }
            Menu {
                Button { showPages = true } label: { Label("Go to Page", systemImage: "square.grid.3x3") }
                Button { showPaper = true } label: { Label("Paper & Template", systemImage: "doc.richtext") }
                Button { exportPDF() } label: { Label("Export as PDF", systemImage: "square.and.arrow.up") }
                Picker(selection: $tools.inputMode) {
                    ForEach(DrawingInput.allCases) { m in Text(m.title).tag(m) }
                } label: {
                    Label("Drawing Input", systemImage: "hand.draw")
                }
                Divider()
                Button(role: .destructive) { confirmDeletePage = true } label: {
                    Label("Delete Page", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
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

    private var toolsGroup: some View {
        HStack(spacing: 4) {
            toolButton(.pen, symbol: tools.pen.kind.symbol, ink: tools.pen.colorHex, label: "Pen")
            toolButton(.highlighter, symbol: "highlighter", ink: tools.highlighter.colorHex, label: "Highlighter")
            toolButton(.eraser, symbol: "eraser", ink: nil, label: "Eraser")
            toolButton(.lasso, symbol: "lasso", ink: nil, label: "Lasso")
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 24)
                .padding(.horizontal, 4)
            Button {
                tools.rulerActive.toggle()
            } label: {
                Image(systemName: "ruler")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tools.rulerActive ? Theme.action : Color.primary)
                    .frame(width: 42, height: 38)
                    .background(Capsule().fill(tools.rulerActive ? Theme.action.opacity(0.2) : Color.clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ruler")
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
        .glassBackground(Capsule(), interactive: true)
    }

    private func toolButton(_ tool: EditorTool, symbol: String, ink: String?, label: String) -> some View {
        let selected = tools.tool == tool
        return Button {
            if selected {
                if tool == .pen || tool == .highlighter { showToolSettings = true }
            } else {
                tools.tool = tool
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
            .background(Capsule().fill(selected ? Theme.action.opacity(0.2) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var contextBar: some View {
        HStack(spacing: 10) {
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
                barDivider
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
                barDivider
                ForEach(0..<3, id: \.self) { i in
                    quickSize(index: i, selected: abs(tools.highlighter.width - tools.highlighterQuickSizes[i]) < 0.05) {
                        tools.highlighter.width = tools.highlighterQuickSizes[i]
                    }
                }
            case .eraser:
                eraserModeButton(.stroke, symbol: "scribble", label: "Whole Stroke")
                eraserModeButton(.pixel, symbol: "circle.dotted", label: "Precise")
                if tools.eraserMode == .pixel {
                    barDivider
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
        .padding(.horizontal, 12)
        .frame(height: 46)
        .glassBackground(Capsule(), interactive: true)
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 22)
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
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
        .accessibilityLabel("More Pen Options")
        .popover(isPresented: $showToolSettings, arrowEdge: .top) {
            toolSettings
        }
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

    private func eraserModeButton(_ mode: EraserMode, symbol: String, label: String) -> some View {
        let selected = tools.eraserMode == mode
        return Button { tools.eraserMode = mode } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(label).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(selected ? Theme.action : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(selected ? Theme.action.opacity(0.2) : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var focusExitButton: some View {
        Button {
            withAnimation(.snappy) { focusMode = false }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: currentToolSymbol)
                    .font(.system(size: 20, weight: .medium))
                if tools.tool == .pen {
                    Capsule().fill(Color(hex: tools.pen.colorHex)).frame(width: 14, height: 3.5)
                        .overlay(Capsule().stroke(Color.primary.opacity(0.35), lineWidth: 0.5))
                }
            }
            .foregroundStyle(Color.primary)
            .frame(width: 50, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var pagePill: some View {
        Button { showPages = true } label: {
            Text("\(controller.pageIndex + 1) of \(controller.pageCount)")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassBackground(Capsule(), interactive: true)
        .padding(.bottom, 16)
    }

    private func exportPDF() {
        guard let vc = controller.vc else { return }
        let nb = currentNotebook
        if let url = PDFExporter.export(title: nb.title, template: nb.template, paper: nb.paper,
                                        drawings: vc.drawingsForExport()) {
            shareItem = ShareItem(url: url)
        }
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
                                .onTapGesture { paper = p }
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
                            .onTapGesture { template = t }
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

struct PageNavigatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let count: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 14)], spacing: 14) {
                    ForEach(0..<max(count, 1), id: \.self) { i in
                        Button {
                            onSelect(i)
                            dismiss()
                        } label: {
                            Text("\(i + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Color.black.opacity(0.75))
                                .frame(width: 76, height: 98)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(i == current ? Theme.action : Color.primary.opacity(0.15), lineWidth: i == current ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .background(Theme.libraryBackground)
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
