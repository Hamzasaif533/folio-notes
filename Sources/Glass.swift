import SwiftUI

/// Liquid Glass on iPadOS 26+, with a frosted-material fallback on older versions.
extension View {
    @ViewBuilder
    func glassBackground<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if let tint { shape.fill(tint.opacity(0.85)) }
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
    }
}

extension View {
    /// Light glass for the editor's floating bars. Regular glass (not "clear") so the icons keep
    /// their contrast on white paper; the fallback is a thin frosted material.
    @ViewBuilder
    func clearGlass<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.interactive(), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.thinMaterial).opacity(0.85)
                    shape.stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        }
    }
}

@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var g: Glass = .regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
}

/// Groups glass shapes so they blend and morph together on iPadOS 26+.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
