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
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { shown = true }
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

/// Springs a view in from nothing, with a small delay for a staggered effect.
struct PopIn: ViewModifier {
    let shown: Bool
    let delay: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .animation(.spring(response: 0.36, dampingFraction: 0.68).delay(delay), value: shown)
    }
}

/// Dark panel on the left with page thumbnails (like Noteshelf's page sidebar).
struct PageSidebar: View {
    let title: String
    let template: PageTemplate
    let paper: PaperColor
    let count: Int
    let current: Int
    let thumbnail: (Int) -> UIImage?
    let onSelect: (Int) -> Void
    let onAdd: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "sidebar.left").font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close Pages")
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close")
            }
            .foregroundStyle(Theme.action)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(count == 1 ? "1 page" : "\(count) pages")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                        ForEach(0..<count, id: \.self) { i in
                            PageThumb(index: i, template: template, paper: paper,
                                      selected: i == current, image: thumbnail(i))
                                .id(i)
                                .onTapGesture { onSelect(i) }
                        }
                        Button(action: onAdd) {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Theme.action)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(TemplateRenderer.pageSize.width / TemplateRenderer.pageSize.height, contentMode: .fit)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                                Text("New Page").font(.caption.weight(.medium)).foregroundStyle(Theme.action)
                            }
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .padding(18)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(Color(hex: "#111113").ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}

private struct PageThumb: View {
    let index: Int
    let template: PageTemplate
    let paper: PaperColor
    let selected: Bool
    let image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            TemplateThumbnail(template: template, paper: paper)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? Theme.action : Color.clear, lineWidth: 3).padding(-3))
                .scaleEffect(selected ? 1.02 : 1)
            Text("\(index + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(selected ? Theme.action : .white.opacity(0.75))
        }
        .contentShape(Rectangle())
        .animation(.snappy, value: selected)
    }
}
