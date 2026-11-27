import SwiftUI

/// What the library presents full screen: one notebook, or two side by side.
struct EditorRoot: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var tools: ToolState
    /// Leaving split screen keeps this one; switching notebooks outside split goes through the library.
    let onSwitch: (Notebook) -> Void
    @State private var primary: Notebook
    @State private var secondary: Notebook?

    init(start: Notebook, onSwitch: @escaping (Notebook) -> Void) {
        self.onSwitch = onSwitch
        _primary = State(initialValue: start)
        _secondary = State(initialValue: nil)
    }

    var body: some View {
        Group {
            if let second = secondary {
                SplitEditorView(first: $primary, second: Binding(get: { second }, set: { secondary = $0 }),
                                onEnd: { keep in
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        primary = keep
                                        secondary = nil
                                    }
                                })
                .transition(.opacity)
            } else {
                EditorView(notebook: primary, onSwitch: onSwitch, onSplit: { other in
                    withAnimation(.easeOut(duration: 0.25)) { secondary = other }
                })
                .id(primary.id)
                .transition(.opacity)
            }
        }
        .onAppear {
            if DemoMode.split, let other = store.activeNotebooks.first(where: { $0.id != primary.id && !$0.isCanvas }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { secondary = other }
            }
        }
    }
}

/// Two notebooks at once. Drag the divider to resize; its handle swaps the sides,
/// turns the split between side by side and top and bottom, or ends the split.
struct SplitEditorView: View {
    @Binding var first: Notebook
    @Binding var second: Notebook
    /// Ends split screen, keeping the given notebook full screen.
    let onEnd: (Notebook) -> Void

    @AppStorage("folio.splitSideBySide") private var sideBySide = true
    @AppStorage("folio.splitFraction") private var fraction = 0.5
    @State private var dragStart: Double?

    private static let divider: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let total = sideBySide ? geo.size.width : geo.size.height
            let firstLength = max(0, (total - Self.divider) * CGFloat(fraction))
            let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                pane(first, other: second, bars: true, replace: { first = $0 })
                    .frame(width: sideBySide ? firstLength : nil, height: sideBySide ? nil : firstLength)
                dividerBar(total: total)
                pane(second, other: first, bars: false, replace: { second = $0 })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeOut(duration: 0.25), value: sideBySide)
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
    }

    /// Both sides share one set of tools, so only the first side shows the tool bars.
    private func pane(_ nb: Notebook, other: Notebook, bars: Bool, replace: @escaping (Notebook) -> Void) -> some View {
        EditorView(notebook: nb, onSwitch: { replace($0) }, onClose: { onEnd(other) },
                   inSplit: true, showsToolBars: bars)
            .id(nb.id)
            .clipped()
    }

    private func dividerBar(total: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color(hex: "#1C1C1E"))
            Menu {
                Button {
                    let a = first
                    first = second
                    second = a
                } label: { Label("Swap Sides", systemImage: "arrow.left.arrow.right") }
                Button { sideBySide.toggle() } label: {
                    Label(sideBySide ? "Top and Bottom" : "Side by Side",
                          systemImage: sideBySide ? "rectangle.split.1x2" : "rectangle.split.2x1")
                }
                Button { fraction = 0.5 } label: { Label("Equal Sizes", systemImage: "equal") }
                Divider()
                Button(role: .destructive) { onEnd(second) } label: {
                    Label(sideBySide ? "Close Left" : "Close Top", systemImage: "xmark")
                }
                Button(role: .destructive) { onEnd(first) } label: {
                    Label(sideBySide ? "Close Right" : "Close Bottom", systemImage: "xmark")
                }
            } label: {
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: sideBySide ? 5 : 56, height: sideBySide ? 56 : 5)
                    .frame(width: sideBySide ? Self.divider + 16 : 90, height: sideBySide ? 90 : Self.divider + 16)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Split screen options")
        }
        .frame(width: sideBySide ? Self.divider : nil, height: sideBySide ? nil : Self.divider)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { v in
                    if dragStart == nil { dragStart = fraction }
                    let delta = sideBySide ? v.translation.width : v.translation.height
                    let f = (dragStart ?? 0.5) + Double(delta / max(total - Self.divider, 1))
                    fraction = min(max(f, 0.25), 0.75)
                }
                .onEnded { _ in dragStart = nil }
        )
        .zIndex(2)
    }
}

/// The notebook chooser shown by a five-finger tap (or More > Split Screen).
struct SplitPicker: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let current: UUID
    let onPick: (Notebook) -> Void

    private var choices: [Notebook] {
        store.sorted(store.activeNotebooks.filter { $0.id != current }, by: .modified)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if choices.isEmpty {
                    Text("No other notebooks")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 24)], spacing: 28) {
                    ForEach(choices) { nb in
                        Button { onPick(nb) } label: { NotebookTile(notebook: nb) }
                            .buttonStyle(PressableStyle(scale: 0.95))
                    }
                }
                .padding(24)
            }
            .navigationTitle("Open Next to This Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}
