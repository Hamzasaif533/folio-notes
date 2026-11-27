import SwiftUI

/// "Add Space to Page": drag the handles around the page outwards to give it more room
/// on any side. The writing stays where it is; the new area gets the same paper.
struct AddSpaceView: View {
    let pageImage: UIImage?
    /// Current size of the page in page units.
    let pageSize: CGSize
    let canApplyToAll: Bool
    let onCancel: () -> Void
    let onDone: (PageExtent, Bool) -> Void

    @State private var add = PageExtent()
    @State private var start = PageExtent()
    @State private var dragging = false
    @State private var allPages = false

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
        var moves: (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
            switch self {
            case .topLeft: return (1, 1, 0, 0)
            case .top: return (0, 1, 0, 0)
            case .topRight: return (0, 1, 1, 0)
            case .right: return (0, 0, 1, 0)
            case .bottomRight: return (0, 0, 1, 1)
            case .bottom: return (0, 0, 0, 1)
            case .bottomLeft: return (1, 0, 0, 1)
            case .left: return (1, 0, 0, 0)
            }
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Text("Add Space to Page")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                HStack {
                    pill("Cancel", tint: .white, action: onCancel)
                    Spacer()
                    pill("Done", tint: Theme.action) { onDone(add, allPages) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            GeometryReader { geo in
                let area = geo.size
                // The page takes about half the area, so there's room to grow it on every side.
                let s = min(area.width * 0.46 / pageSize.width, area.height * 0.52 / pageSize.height)
                let pw = pageSize.width * s
                let ph = pageSize.height * s
                let page = CGRect(x: (area.width - pw) / 2, y: (area.height - ph) / 2, width: pw, height: ph)
                let grown = CGRect(x: page.minX - add.left * s, y: page.minY - add.top * s,
                                   width: pw + (add.left + add.right) * s,
                                   height: ph + (add.top + add.bottom) * s)
                ZStack(alignment: .topLeading) {
                    GridBackdrop()
                    directionArrows(page: page, in: area)

                    // The new paper, then the page as it is now on top of it.
                    Rectangle()
                        .fill(Color.white)
                        .overlay(GridLines(step: 14).stroke(Color(hex: "#BCCADB").opacity(0.7), lineWidth: 0.5))
                        .frame(width: grown.width, height: grown.height)
                        .offset(x: grown.minX, y: grown.minY)
                    Group {
                        if let pageImage {
                            Image(uiImage: pageImage).resizable()
                        } else {
                            Rectangle().fill(Color.white)
                        }
                    }
                    .frame(width: pw, height: ph)
                    .offset(x: page.minX, y: page.minY)
                    .opacity(dragging ? 0.92 : 1)

                    Rectangle()
                        .stroke(Theme.action, lineWidth: 2)
                        .frame(width: grown.width, height: grown.height)
                        .offset(x: grown.minX, y: grown.minY)

                    ForEach(Handle.allCases, id: \.self) { h in
                        handle(h, grown: grown, page: page, scale: s, area: area)
                    }
                }
                .frame(width: area.width, height: area.height)
            }
            .background(Color(hex: "#232325"))
            .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 28)

            if canApplyToAll {
                HStack(spacing: 0) {
                    scopeButton("Current Page", on: !allPages) { allPages = false }
                    Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 24)
                    scopeButton("All Pages", on: allPages) { allPages = true }
                }
                .padding(.horizontal, 6)
                .frame(height: 56)
                .background(Capsule().fill(Color(hex: "#2C2C2E")))
            }
            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#111113").ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private func handle(_ h: Handle, grown: CGRect, page: CGRect, scale s: CGFloat, area: CGSize) -> some View {
        let m = h.moves
        let x = m.left > 0 ? grown.minX : (m.right > 0 ? grown.maxX : grown.midX)
        let y = m.top > 0 ? grown.minY : (m.bottom > 0 ? grown.maxY : grown.midY)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(hex: "#9ED3E6"))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Theme.action, lineWidth: 1.5))
            .frame(width: 13, height: 13)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging { start = add; dragging = true }
                        let dx = v.translation.width / s, dy = v.translation.height / s
                        // How far each side can grow before it leaves the box.
                        let maxL = (page.minX - 10) / s, maxR = (area.width - page.maxX - 10) / s
                        let maxT = (page.minY - 10) / s, maxB = (area.height - page.maxY - 10) / s
                        var n = start
                        if m.left > 0 { n.left = min(max(start.left - dx, 0), maxL) }
                        if m.right > 0 { n.right = min(max(start.right + dx, 0), maxR) }
                        if m.top > 0 { n.top = min(max(start.top - dy, 0), maxT) }
                        if m.bottom > 0 { n.bottom = min(max(start.bottom + dy, 0), maxB) }
                        add = n
                    }
                    .onEnded { _ in dragging = false }
            )
    }

    private func directionArrows(page: CGRect, in area: CGSize) -> some View {
        let gap: CGFloat = 70
        let spots: [(String, CGPoint)] = [
            ("arrow.up.left", CGPoint(x: page.minX - gap, y: page.minY - gap)),
            ("arrow.up", CGPoint(x: page.midX, y: page.minY - gap)),
            ("arrow.up.right", CGPoint(x: page.maxX + gap, y: page.minY - gap)),
            ("arrow.right", CGPoint(x: page.maxX + gap, y: page.midY)),
            ("arrow.down.right", CGPoint(x: page.maxX + gap, y: page.maxY + gap)),
            ("arrow.down", CGPoint(x: page.midX, y: page.maxY + gap)),
            ("arrow.down.left", CGPoint(x: page.minX - gap, y: page.maxY + gap)),
            ("arrow.left", CGPoint(x: page.minX - gap, y: page.midY))
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, s in
                Image(systemName: s.0)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.22))
                    .position(s.1)
            }
        }
        .frame(width: area.width, height: area.height)
        .allowsHitTesting(false)
    }

    private func pill(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func scopeButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Theme.action : Color.white.opacity(0.6))
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(on ? Color.white : Color.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Faint grid behind the page, like a cutting mat.
private struct GridBackdrop: View {
    var body: some View {
        GridLines(step: 30)
            .stroke(Color.white.opacity(0.07), lineWidth: 1)
    }
}

private struct GridLines: Shape {
    let step: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX
        while x <= r.maxX { p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)); x += step }
        var y = r.minY
        while y <= r.maxY { p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)); y += step }
        return p
    }
}
