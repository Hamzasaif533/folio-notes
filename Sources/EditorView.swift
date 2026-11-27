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
        return vc
    }

    func updateUIViewController(_ vc: PagesViewController, context: Context) {
        vc.setTool(tool)
        vc.setInputMode(inputMode)
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
    @State private var showPen = false
    @State private var showHighlighter = false
    @State private var showEraser = false
    @State private var showPaper = false
    @State private var showPages = false
    @State private var confirmDeletePage = false
    @State private var shareItem: ShareItem?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            PagesHost(store: store, notebook: notebook, tool: tools.pkTool,
                      inputMode: tools.inputMode, controller: controller)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) { pagePill }
        }
        .background(Theme.toolbarBackground.ignoresSafeArea())
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
    }

    private var currentNotebook: Notebook { store.notebook(notebook.id) ?? notebook }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button {
                controller.vc?.saveAll()
                dismiss()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 36)
            }
            Text(currentNotebook.title)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: 170, alignment: .leading)

            Spacer(minLength: 8)

            toolButton(.pen, symbol: tools.pen.kind.symbol, color: Color(uiColor: tools.pen.uiColor), isPresented: $showPen) {
                PenSettingsView().environmentObject(tools)
            }
            toolButton(.highlighter, symbol: "highlighter", color: Color(uiColor: tools.highlighter.uiColor), isPresented: $showHighlighter) {
                HighlighterSettingsView().environmentObject(tools)
            }
            toolButton(.eraser, symbol: "eraser", color: nil, isPresented: $showEraser) {
                EraserSettingsView().environmentObject(tools)
            }
            toolButton(.lasso, symbol: "lasso", color: nil, isPresented: .constant(false)) {
                EmptyView()
            }

            Divider().frame(height: 26).padding(.horizontal, 6)

            favoritesBar

            Spacer(minLength: 8)

            Button { controller.vc?.performUndo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 36)
            }
            .disabled(!controller.canUndo)
            Button { controller.vc?.performRedo() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 36, height: 36)
            }
            .disabled(!controller.canRedo)
            Button { controller.vc?.addPage() } label: {
                Image(systemName: "doc.badge.plus").frame(width: 36, height: 36)
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
                Image(systemName: "ellipsis.circle").frame(width: 36, height: 36)
            }
        }
        .font(.system(size: 17))
        .padding(.horizontal, 12)
        .frame(height: 54)
    }

    private func toolButton<Content: View>(_ tool: EditorTool, symbol: String, color: Color?,
                                           isPresented: Binding<Bool>,
                                           @ViewBuilder settings: @escaping () -> Content) -> some View {
        let selected = tools.tool == tool
        return Button {
            if selected {
                if tool != .lasso { isPresented.wrappedValue = true }
            } else {
                tools.tool = tool
            }
        } label: {
            ZStack(alignment: .bottom) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: selected ? .semibold : .regular))
                    .frame(width: 42, height: 36)
                if let color {
                    Capsule().fill(color).frame(width: 16, height: 3).offset(y: -1)
                }
            }
            .foregroundStyle(selected ? Theme.accent : Color.primary)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent.opacity(0.14) : Color.clear))
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented, arrowEdge: .top) {
            settings()
        }
    }

    private var favoritesBar: some View {
        HStack(spacing: 8) {
            ForEach(tools.favorites.prefix(8)) { fav in
                let active = tools.tool == .pen && tools.pen.sameLook(as: fav)
                Button { tools.selectFavorite(fav) } label: {
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: fav.uiColor))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
                        Circle()
                            .stroke(active ? Theme.accent : Color.clear, lineWidth: 2.5)
                            .frame(width: 30, height: 30)
                    }
                    .frame(width: 32, height: 34)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { tools.removeFavorite(fav.id) } label: {
                        Label("Remove Favorite", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var pagePill: some View {
        Button { showPages = true } label: {
            Text("\(controller.pageIndex + 1) / \(controller.pageCount)")
                .font(.footnote.monospacedDigit().weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 18)
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
                                .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                                .overlay(Circle().stroke(Theme.accent, lineWidth: paper == p ? 3 : 0).padding(-4))
                                .onTapGesture { paper = p }
                        }
                    }
                    SectionTitle(text: "Template")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        ForEach(PageTemplate.allCases) { t in
                            VStack(spacing: 6) {
                                TemplateThumbnail(template: t, paper: paper)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: template == t ? 3 : 0))
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 14)], spacing: 14) {
                    ForEach(0..<max(count, 1), id: \.self) { i in
                        Button {
                            onSelect(i)
                            dismiss()
                        } label: {
                            Text("\(i + 1)")
                                .font(.headline.monospacedDigit())
                                .frame(width: 70, height: 90)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(i == current ? Theme.accent : Color.black.opacity(0.12), lineWidth: i == current ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .background(Theme.shelfBackground)
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
