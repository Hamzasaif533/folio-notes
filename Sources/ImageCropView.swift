import SwiftUI

/// Crop a picture on the page: drag the corners or edges in, or drag the box to move it.
struct ImageCropView: View {
    let image: UIImage
    /// The crop so far (0…1 of the picture).
    @State var crop: CGRect
    let onDone: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var start: CGRect?

    private static let minSide: CGFloat = 0.06

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let area = CGRect(origin: .zero, size: geo.size).insetBy(dx: 36, dy: 40)
                let s = min(area.width / image.size.width, area.height / image.size.height)
                let shown = CGSize(width: image.size.width * s, height: image.size.height * s)
                let pic = CGRect(x: area.midX - shown.width / 2, y: area.midY - shown.height / 2,
                                 width: shown.width, height: shown.height)
                let box = CGRect(x: pic.minX + crop.minX * pic.width, y: pic.minY + crop.minY * pic.height,
                                 width: crop.width * pic.width, height: crop.height * pic.height)
                ZStack(alignment: .topLeading) {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: pic.width, height: pic.height)
                        .offset(x: pic.minX, y: pic.minY)
                    // Dim what gets cut off.
                    Path { p in
                        p.addRect(pic)
                        p.addRect(box)
                    }
                    .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    thirds(box)
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: box.width, height: box.height)
                        .offset(x: box.minX, y: box.minY)
                        .contentShape(Rectangle())
                        .gesture(drag(pic: pic) { r, dx, dy in
                            var m = r
                            m.origin.x = min(max(r.minX + dx, 0), 1 - r.width)
                            m.origin.y = min(max(r.minY + dy, 0), 1 - r.height)
                            return m
                        })
                    ForEach(Handle.allCases, id: \.self) { h in
                        handle(h, box: box, pic: pic)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .principal) {
                    Button("Reset") { withAnimation(.snappy) { crop = CGRect(x: 0, y: 0, width: 1, height: 1) } }
                        .disabled(crop == CGRect(x: 0, y: 0, width: 1, height: 1))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(crop) }.fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func thirds(_ box: CGRect) -> some View {
        Path { p in
            for i in 1...2 {
                let x = box.minX + box.width * CGFloat(i) / 3
                let y = box.minY + box.height * CGFloat(i) / 3
                p.move(to: CGPoint(x: x, y: box.minY)); p.addLine(to: CGPoint(x: x, y: box.maxY))
                p.move(to: CGPoint(x: box.minX, y: y)); p.addLine(to: CGPoint(x: box.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
        .allowsHitTesting(false)
    }

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
        /// Which edges it moves: left, top, right, bottom.
        var edges: (Bool, Bool, Bool, Bool) {
            switch self {
            case .topLeft: return (true, true, false, false)
            case .top: return (false, true, false, false)
            case .topRight: return (false, true, true, false)
            case .right: return (false, false, true, false)
            case .bottomRight: return (false, false, true, true)
            case .bottom: return (false, false, false, true)
            case .bottomLeft: return (true, false, false, true)
            case .left: return (true, false, false, false)
            }
        }
        var isCorner: Bool { [.topLeft, .topRight, .bottomRight, .bottomLeft].contains(self) }
    }

    private func point(_ h: Handle, in b: CGRect) -> CGPoint {
        let e = h.edges
        let x = e.0 ? b.minX : (e.2 ? b.maxX : b.midX)
        let y = e.1 ? b.minY : (e.3 ? b.maxY : b.midY)
        return CGPoint(x: x, y: y)
    }

    private func handle(_ h: Handle, box: CGRect, pic: CGRect) -> some View {
        let p = point(h, in: box)
        let horizontal = h == .top || h == .bottom
        return Group {
            if h.isCorner {
                Circle().fill(Color.white).frame(width: 18, height: 18)
            } else {
                Capsule().fill(Color.white).frame(width: horizontal ? 30 : 6, height: horizontal ? 6 : 30)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 2)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .position(p)
        .gesture(drag(pic: pic) { r, dx, dy in
            let e = h.edges
            var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
            if e.0 { minX = min(max(r.minX + dx, 0), maxX - Self.minSide) }
            if e.1 { minY = min(max(r.minY + dy, 0), maxY - Self.minSide) }
            if e.2 { maxX = max(min(r.maxX + dx, 1), minX + Self.minSide) }
            if e.3 { maxY = max(min(r.maxY + dy, 1), minY + Self.minSide) }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        })
    }

    /// A drag that changes the crop from where it was when the drag began.
    private func drag(pic: CGRect, change: @escaping (CGRect, CGFloat, CGFloat) -> CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let from = start ?? crop
                if start == nil { start = crop }
                crop = change(from, v.translation.width / max(pic.width, 1), v.translation.height / max(pic.height, 1))
            }
            .onEnded { _ in start = nil }
    }
}
