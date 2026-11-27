import SwiftUI

extension View {
    /// The notebook cover that the editor zooms out of (iPadOS 18+).
    @ViewBuilder
    func zoomSource<ID: Hashable>(id: ID, in ns: Namespace.ID?) -> some View {
        if let ns {
            if #available(iOS 18.0, *) {
                self.matchedTransitionSource(id: id, in: ns) { $0.clipShape(RoundedRectangle(cornerRadius: 8)) }
            } else {
                self
            }
        } else {
            self
        }
    }

    /// Opens the editor by zooming out of the tapped notebook cover (iPadOS 18+).
    @ViewBuilder
    func zoomTransition<ID: Hashable>(id: ID, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            self
        }
    }
}

/// Grid items fade and scale in one after another the first time they appear.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.92)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(min(Double(index), 12) * 0.035)) {
                    shown = true
                }
            }
    }
}

extension View {
    func staggeredAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}
