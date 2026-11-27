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

/// Two notebooks at once. Drag the middle handle to resize; hold it to swap the sides,
/// turns the split between side by side and top and bottom, or ends the split.
struct SplitEditorView: View {
    @Binding var first: Notebook
    @Binding var second: Notebook
    /// Ends split screen, keeping the given notebook full screen.
    let onEnd: (Notebook) -> Void

    @AppStorage("folio.splitSideBySide") private var sideBySide = true
    @AppStorage("folio.splitFraction") private var fraction = 0.5
    /// How far the handle has been dragged; the sides only resize when it's let go.
    @State private var dragOffset: CGFloat?

    private static let divider: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let total = sideBySide ? geo.size.width : geo.size.height
            let usable = max(total - Self.divider, 1)
            let firstLength = max(0, usable * CGFloat(fraction))
            let pos = min(max(firstLength + (dragOffset ?? 0), usable * 0.2), usable * 0.8)
            let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            ZStack(alignment: .topLeading) {
                layout {
                    pane(first, other: second, bars: true, replace: { first = $0 })
                        .frame(width: sideBySide ? firstLength : nil, height: sideBySide ? nil : firstLength)
                    Rectangle()
                        .fill(Color(hex: "#1C1C1E"))
                        .frame(width: sideBySide ? Self.divider : nil, height: sideBySide ? nil : Self.divider)
                    pane(second, other: first, bars: false, replace: { second = $0 })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(.easeOut(duration: 0.25), value: sideBySide)

                // While dragging: a line showing where the split will land.
                if dragOffset != nil {
                    Rectangle()
                        .fill(Theme.action)
                        .frame(width: sideBySide ? Self.divider : geo.size.width,
                               height: sideBySide ? geo.size.height : Self.divider)
                        .shadow(color: .black.opacity(0.35), radius: 4)
                        .offset(x: sideBySide ? pos : 0, y: sideBySide ? 0 : pos)
                        .allowsHitTesting(false)
                }

                handle(firstLength: firstLength, usable: usable)
                    .position(x: sideBySide ? pos + Self.divider / 2 : geo.size.width / 2,
                              y: sideBySide ? geo.size.height / 2 : pos + Self.divider / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
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

    /// The grip in the middle of the divider: drag it to resize, hold it for the options.
    private func handle(firstLength: CGFloat, usable: CGFloat) -> some View {
        let dragging = dragOffset != nil
        return Capsule()
            .fill(dragging ? Theme.action : Color(hex: "#3A3A3C"))
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            .overlay(
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: sideBySide ? 3 : 26, height: sideBySide ? 26 : 3)
            )
            .frame(width: sideBySide ? 14 : 64, height: sideBySide ? 64 : 14)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .frame(width: sideBySide ? 44 : 100, height: sideBySide ? 100 : 44)
            .contentShape(Rectangle())
            .scaleEffect(dragging ? 1.15 : 1)
            .animation(.snappy(duration: 0.18), value: dragging)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { v in
                        dragOffset = sideBySide ? v.translation.width : v.translation.height
                    }
                    .onEnded { v in
                        let delta = sideBySide ? v.translation.width : v.translation.height
                        let f = Double((firstLength + delta) / usable)
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            fraction = min(max(f, 0.2), 0.8)
                            dragOffset = nil
                        }
                    }
            )
            .contextMenu {
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
            }
            .accessibilityLabel("Split divider. Drag to resize, hold for options")
            .zIndex(3)
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
