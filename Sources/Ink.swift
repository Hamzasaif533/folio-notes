import UIKit
import PencilKit // only to read notebooks saved before Folio had its own pens

// MARK: - Model

/// Folio's own pens. Stored as one byte per stroke: 0–5 are the pens, and 16–31 are the
/// 1.9–1.10 flat-nib fountain pen at 16 levels of flatness.
struct InkStyle: Hashable {
    let rawValue: UInt8

    init?(rawValue: UInt8) {
        guard rawValue <= 5 || (16...31).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }
    private init(_ v: UInt8) { rawValue = v }

    static let ballpoint = InkStyle(0)
    static let fountain = InkStyle(1)
    static let highlighter = InkStyle(2)
    /// Soft brush: very pressure sensitive, pointed ends.
    static let brush = InkStyle(3)
    /// Flat calligraphy nib written by 1.9 (flatness 0.85).
    static let nib = InkStyle(4)
    /// The fountain pen since 1.11: an oval tip that spreads sideways as you press.
    /// Each stroke keeps its tip's shape (`InkTip`).
    static let oval = InkStyle(5)

    /// The flat-nib fountain pen at a flatness from 0 (square nib) to 1 (thinnest hairlines).
    static func nibStyle(flatness f: Double) -> InkStyle {
        InkStyle(16 + UInt8((min(max(f, 0), 1) * 15).rounded()))
    }

    var isNib: Bool { rawValue == 4 || rawValue >= 16 }
    var nibFlatness: CGFloat { rawValue >= 16 ? CGFloat(rawValue - 16) / 15 : 0.85 }
    /// The nib's thickness as a share of its length.
    var nibThickness: CGFloat { 0.05 + 0.95 * pow(1 - nibFlatness, 1.5) }
}

/// One sampled point of a stroke, in page units, with the line width at that point.
struct InkPoint: Equatable {
    var x: Float
    var y: Float
    var w: Float

    init(x: Float, y: Float, w: Float) { self.x = x; self.y = y; self.w = w }
    init(_ p: CGPoint, w: CGFloat) { x = Float(p.x); y = Float(p.y); self.w = Float(w) }

    var cg: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
    var width: CGFloat { CGFloat(w) }
}

/// The oval fountain pen's tip for one stroke. Each point's width is the tip's width
/// (it spreads sideways as you press); the tip's height follows from it: it grows only a
/// little with pressure, and shrinks with the width where the line tapers to a point.
struct InkTip: Equatable {
    /// Tip width and height at the lightest pressure (page units).
    var hMin: Float
    var vMin: Float
    /// How much the height grows for each unit the width grows with pressure.
    var slope: Float

    func height(forWidth w: CGFloat) -> CGFloat {
        let hm = CGFloat(hMin), vm = CGFloat(vMin)
        guard hm > 0.0001 else { return w }
        if w <= hm { return vm * w / hm } // a tapering end shrinks the whole tip
        return vm + CGFloat(slope) * (w - hm)
    }

    func scaled(_ s: Float) -> InkTip { InkTip(hMin: hMin * s, vMin: vMin * s, slope: slope) }
}

struct InkColor: Equatable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) { self.r = r; self.g = g; self.b = b; self.a = a }

    init(_ color: UIColor) {
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        func c(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(r: c(rr), g: c(gg), b: c(bb), a: c(aa))
    }

    init(hex: String, opacity: CGFloat = 1) {
        self.init(UIColor(hex: hex).withAlphaComponent(opacity))
    }

    var uiColor: UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
    /// The colour without its transparency (transparency is applied to the whole stroke).
    var opaqueCG: CGColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1).cgColor
    }
    var alpha: CGFloat { CGFloat(a) / 255 }

    /// How the colour shows on a page shown dark: black and near-black ink turn light so it
    /// stays readable. Other colours stay as they are. (Saved ink never changes.)
    func shown(dark: Bool) -> InkColor {
        guard dark else { return self }
        let lum = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        guard lum < 70 else { return self }
        let v = UInt8(255 - lum * 0.6)
        return InkColor(r: v, g: v, b: v, a: a)
    }
}

/// A finished line. Strokes never change: editing one makes a new stroke with a new id.
struct InkStroke: Identifiable, Equatable {
    var id = UUID()
    var style: InkStyle
    var color: InkColor
    var points: [InkPoint]
    /// The oval fountain pen's tip (nil for every other pen).
    var tip: InkTip?
    /// Everything the stroke covers, including its width.
    private(set) var bounds: CGRect

    init(id: UUID = UUID(), style: InkStyle, color: InkColor, points: [InkPoint], tip: InkTip? = nil) {
        self.id = id
        self.tip = tip
        self.style = style
        self.color = color
        self.points = points
        bounds = Self.measure(points)
        // The oval tip can be taller than it is wide (light pressure): leave room for it.
        if let tip, !bounds.isNull {
            let maxW = CGFloat(points.map(\.w).max() ?? 0)
            let extra = max(tip.height(forWidth: maxW) - maxW, 0) / 2
            if extra > 0 { bounds = bounds.insetBy(dx: -extra, dy: -extra) }
        }
    }

    static func measure(_ pts: [InkPoint]) -> CGRect {
        guard let f = pts.first else { return .null }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y, maxW = f.w
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            maxW = max(maxW, p.w)
        }
        let pad = CGFloat(maxW) / 2 + 1
        return CGRect(x: CGFloat(minX) - pad, y: CGFloat(minY) - pad,
                      width: CGFloat(maxX - minX) + pad * 2, height: CGFloat(maxY - minY) + pad * 2)
    }

    var averageWidth: CGFloat {
        guard !points.isEmpty else { return 1 }
        return CGFloat(points.reduce(Float(0)) { $0 + $1.w } / Float(points.count))
    }

    /// A copy moved/rotated/scaled by `t` (widths scale too). Gets a new id.
    func applying(_ t: CGAffineTransform) -> InkStroke {
        let s = Float(sqrt(abs(t.a * t.d - t.b * t.c)))
        let pts = points.map { p -> InkPoint in
            let q = p.cg.applying(t)
            return InkPoint(x: Float(q.x), y: Float(q.y), w: p.w * s)
        }
        return InkStroke(style: style, color: color, points: pts, tip: tip?.scaled(s))
    }

    func recolored(_ c: InkColor) -> InkStroke {
        var copy = InkStroke(style: style, color: c, points: points, tip: tip)
        if style == .highlighter { copy.color.a = color.a }
        return copy
    }
}

/// All the ink on one page (or on the endless canvas).
struct InkDrawing: Equatable {
    var strokes: [InkStroke] = []

    init(strokes: [InkStroke] = []) { self.strokes = strokes }

    var isEmpty: Bool { strokes.isEmpty }

    var bounds: CGRect {
        strokes.reduce(CGRect.null) { $0.union($1.bounds) }
    }

    func transformed(using t: CGAffineTransform) -> InkDrawing {
        InkDrawing(strokes: strokes.map { $0.applying(t) })
    }

    // MARK: Saving (a small binary format: "FNK2", then each stroke's style, colour, tip and points;
    // "FNK1", from before 1.11, has no tip)

    private static let magic1: [UInt8] = Array("FNK1".utf8)
    private static let magic2: [UInt8] = Array("FNK2".utf8)

    func dataRepresentation() -> Data {
        var d = Data()
        d.reserveCapacity(8 + strokes.reduce(0) { $0 + 22 + $1.points.count * 12 })
        d.append(contentsOf: Self.magic2)
        d.appendLE(UInt32(strokes.count))
        for s in strokes {
            d.append(s.style.rawValue)
            d.append(contentsOf: [s.color.r, s.color.g, s.color.b, s.color.a])
            if let t = s.tip {
                d.append(1)
                d.appendLE(t.hMin.bitPattern)
                d.appendLE(t.vMin.bitPattern)
                d.appendLE(t.slope.bitPattern)
            } else {
                d.append(0)
            }
            d.appendLE(UInt32(s.points.count))
            for p in s.points {
                d.appendLE(p.x.bitPattern)
                d.appendLE(p.y.bitPattern)
                d.appendLE(p.w.bitPattern)
            }
        }
        return d
    }

    init?(data: Data) {
        var r = ByteReader(data: data)
        guard let m = r.bytes(4), m == Self.magic1 || m == Self.magic2, let count = r.u32() else { return nil }
        let hasTips = m == Self.magic2
        var out: [InkStroke] = []
        out.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let st = r.u8(), let c = r.bytes(4) else { return nil }
            var tip: InkTip?
            if hasTips {
                guard let flag = r.u8() else { return nil }
                if flag & 1 != 0 {
                    guard let h = r.f32(), let v = r.f32(), let k = r.f32() else { return nil }
                    tip = InkTip(hMin: h, vMin: v, slope: k)
                }
            }
            guard let n = r.u32(), r.remaining >= Int(n) * 12 else { return nil }
            var pts: [InkPoint] = []
            pts.reserveCapacity(Int(n))
            for _ in 0..<n {
                guard let x = r.f32(), let y = r.f32(), let w = r.f32() else { return nil }
                pts.append(InkPoint(x: x, y: y, w: w))
            }
            out.append(InkStroke(style: InkStyle(rawValue: st) ?? .ballpoint,
                                 color: InkColor(r: c[0], g: c[1], b: c[2], a: c[3]), points: pts, tip: tip))
        }
        strokes = out
    }

    // MARK: Old notebooks

    /// Turns a PencilKit drawing (Folio 1.0–1.5) into Folio ink, keeping each line's shape,
    /// width and colour. Parts rubbed out with the old precise eraser stay rubbed out.
    init(pencilKit d: PKDrawing) {
        var out: [InkStroke] = []
        let light = UITraitCollection(userInterfaceStyle: .light)
        for s in d.strokes {
            let style: InkStyle
            switch s.ink.inkType {
            case .fountainPen: style = .fountain
            case .marker: style = .highlighter
            default: style = .ballpoint
            }
            let color = InkColor(s.ink.color.resolvedColor(with: light))
            let t = s.transform
            let scale = sqrt(abs(t.a * t.d - t.b * t.c))
            var runs: [[InkPoint]] = [[]]
            for p in s.path.interpolatedPoints(by: .distance(1.5)) {
                if let mask = s.mask, !mask.contains(p.location) {
                    if !(runs.last?.isEmpty ?? true) { runs.append([]) }
                    continue
                }
                let loc = p.location.applying(t)
                runs[runs.count - 1].append(InkPoint(loc, w: max(p.size.width, 0.3) * scale))
            }
            for run in runs where !run.isEmpty {
                out.append(InkStroke(style: style, color: color, points: run))
            }
        }
        strokes = out
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

private struct ByteReader {
    let data: Data
    var offset = 0
    var remaining: Int { data.count - offset }

    init(data: Data) { self.data = data }

    mutating func bytes(_ n: Int) -> [UInt8]? {
        guard remaining >= n else { return nil }
        let start = data.startIndex + offset
        offset += n
        return Array(data[start..<(start + n)])
    }

    mutating func u8() -> UInt8? { bytes(1)?.first }

    mutating func u32() -> UInt32? {
        guard let b = bytes(4) else { return nil }
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    mutating func f32() -> Float? { u32().map { Float(bitPattern: $0) } }
}

// MARK: - Tools

struct InkPen: Equatable {
    var style: InkStyle
    var colorHex: String
    var width: CGFloat
    var opacity: CGFloat = 1
    /// The Shapes tool: the stroke snaps to a clean line, circle, rectangle…
    var shapes = false
    /// Pressure, pointed ends, flat nib and steadiness (Pen Settings).
    var feel: InkFeel = .standard

    /// Line width for a pressure (0…1) and a direction of travel (radians).
    func width(pressure p: CGFloat, direction: CGFloat) -> CGFloat {
        if style == .highlighter || shapes { return width }
        let k = CGFloat(feel.pressure)
        if style == .oval {
            // Width here is the tip's width: it spreads as you press, in step with the pressure
            // (no easing, so light writing really is thin and pressing really is bold).
            let r = ovalRange
            let pe = min(max(p, 0), 1)
            return width * (r.hLo + (r.hHi - r.hLo) * pe)
        }
        if style.isNib {
            // Width here is the nib's length; the stroke's thickness comes from its direction.
            let pe = sin(min(max(p, 0), 1) * .pi / 2)
            return width * 1.35 * max(1 - 0.5 * k + 0.8 * k * pe, 0.3)
        }
        var w: CGFloat
        switch style {
        case .fountain:
            // Eased pressure (soft at first, then full) like a real nib flexing.
            let pe = sin(min(max(p, 0), 1) * .pi / 2)
            w = width * max(1 - 0.7 * k + 1.25 * k * pe, 0.2)
        case .brush: w = width * max(1 - 1.5 * k + 2.6 * k * p, 0.06)
        default: w = width * max(1 - 0.56 * k + 1.12 * k * p, 0.12)
        }
        // A nib held at 45°: thin going one way, full going the other.
        let flat = min(0.8 * CGFloat(feel.tipFlatness), 0.8)
        if flat > 0 { w *= 1 - flat * (1 - abs(sin(direction - .pi / 4))) }
        return w
    }

    /// The oval tip's width (h) and height (v) at the lightest and hardest pressure, as
    /// multiples of the pen size. Tip Flatness sets how far the tip spreads sideways:
    /// round (0) just gets a little bigger all round, the middle is a soft oval that turns
    /// down-strokes bold, and flat (1) is a thin bar with very bold down-strokes and thin
    /// cross-strokes. Pressure Sensitivity stretches or shrinks the light-to-hard range.
    var ovalRange: (hLo: CGFloat, hHi: CGFloat, vLo: CGFloat, vHi: CGFloat) {
        let round: [CGFloat] = [0.80, 1.20, 0.80, 1.20]
        let middle: [CGFloat] = [0.72, 1.45, 0.92, 1.22]
        let flat: [CGFloat] = [0.75, 1.75, 0.30, 0.40]
        let s = CGFloat(min(max(feel.tipFlatness, 0), 1))
        let (a, b, t) = s < 0.5 ? (round, middle, s / 0.5) : (middle, flat, (s - 0.5) / 0.5)
        var v = zip(a, b).map { $0 + ($1 - $0) * t }
        // Default sensitivity (0.5) gives the ranges above; 0 is no pressure, 1 twice the range.
        let f = CGFloat(min(max(feel.pressure, 0), 1)) / 0.5
        for (lo, hi) in [(0, 1), (2, 3)] {
            let mid = (v[lo] + v[hi]) / 2
            v[lo] = max(mid - (mid - v[lo]) * f, 0.15)
            v[hi] = mid + (v[hi] - mid) * f
        }
        return (v[0], v[1], v[2], v[3])
    }

    /// The tip that goes with this pen's strokes (only the oval fountain pen has one).
    var tip: InkTip? {
        guard style == .oval, !shapes else { return nil }
        let r = ovalRange
        let dh = r.hHi - r.hLo
        return InkTip(hMin: Float(width * r.hLo), vMin: Float(width * r.vLo),
                      slope: dh > 0.001 ? Float((r.vHi - r.vLo) / dh) : 0)
    }

    /// How far (page units) the pointed start and end reach.
    var taperLength: CGFloat {
        style == .highlighter || shapes || style == .oval ? 0 : width * 7 * CGFloat(feel.tipSharpness)
    }

    /// The oval pen's ends: a quick lift leaves a pointed tail; stopping before lifting leaves
    /// the round end. `speed` is how fast the Pencil was moving as it lifted (points a second).
    func liftTapered(_ pts: [InkPoint], speed: CGFloat) -> [InkPoint] {
        guard style == .oval, !shapes, pts.count > 2 else { return pts }
        let quick = min(max((speed - 250) / 1100, 0), 1)
        let L = width * 6 * CGFloat(feel.tipSharpness) * quick
        guard L > 0.05 else { return pts }
        var along = [CGFloat](repeating: 0, count: pts.count)
        for i in 1..<pts.count {
            along[i] = along[i - 1] + hypot(pts[i].cg.x - pts[i - 1].cg.x, pts[i].cg.y - pts[i - 1].cg.y)
        }
        let total = along[pts.count - 1]
        let reach = min(L, total * 0.45)
        guard reach > 0.05 else { return pts }
        return pts.indices.map { i in
            let f = min(max((total - along[i]) / reach, 0), 1)
            var p = pts[i]
            // Eased, so the tail narrows smoothly into a fine point.
            p.w = Float(p.width * (0.08 + 0.92 * sin(f * .pi / 2)))
            return p
        }
    }

    /// Thins the first and last `taperLength` of a line to a point.
    func tapered(_ pts: [InkPoint], start: Bool = true, end: Bool = true) -> [InkPoint] {
        let L = taperLength
        guard L > 0.01, pts.count > 2 else { return pts }
        var along = [CGFloat](repeating: 0, count: pts.count)
        for i in 1..<pts.count {
            along[i] = along[i - 1] + hypot(pts[i].cg.x - pts[i - 1].cg.x, pts[i].cg.y - pts[i - 1].cg.y)
        }
        let total = along[pts.count - 1]
        let reach = min(L, total * 0.4)
        guard reach > 0.01 else { return pts }
        return pts.indices.map { i in
            var f: CGFloat = 1
            if start { f = min(f, along[i] / reach) }
            if end { f = min(f, (total - along[i]) / reach) }
            var p = pts[i]
            p.w = Float(p.width * (0.12 + 0.88 * max(0, min(1, f))))
            return p
        }
    }
}

/// What the page does with the Pencil right now.
enum InkTool: Equatable {
    case pen(InkPen)
    case eraser(precise: Bool, width: CGFloat)
    case lasso
    /// Text, tape, laser… (the ink layer ignores touches).
    case none
}

// MARK: - Drawing ink

enum InkRenderer {
    /// How see-through the highlighter is.
    static let highlighterAlpha: CGFloat = 0.38

    /// Draws strokes in page units. Highlighter goes under the pens, like a real highlighter.
    /// Highlights of the same colour are drawn together, so where they cross over each other
    /// (or themselves) they don't get darker, like one pass of a real highlighter.
    /// `dark` shows black ink light, for pages shown dark.
    static func draw(_ strokes: [InkStroke], in ctx: CGContext, rect: CGRect? = nil, hidden: Set<UUID> = [],
                     dark: Bool = false) {
        var groups: [(color: InkColor, strokes: [InkStroke])] = []
        for s in strokes where s.style == .highlighter && !hidden.contains(s.id) {
            if let rect, !rect.intersects(s.bounds) { continue }
            if let k = groups.firstIndex(where: { $0.color == s.color }) {
                groups[k].strokes.append(s)
            } else {
                groups.append((s.color, [s]))
            }
        }
        for g in groups { drawHighlighters(g.strokes, color: g.color.shown(dark: dark), in: ctx) }
        for s in strokes where s.style != .highlighter && !hidden.contains(s.id) {
            if let rect, !rect.intersects(s.bounds) { continue }
            drawPen(s, color: s.color.shown(dark: dark), in: ctx)
        }
    }

    static func draw(_ drawing: InkDrawing, in ctx: CGContext) {
        draw(drawing.strokes, in: ctx)
    }

    private static func drawPen(_ s: InkStroke, color: InkColor, in ctx: CGContext) {
        let path = cache.outline(for: s)
        ctx.saveGState()
        let translucent = color.a < 255
        if translucent {
            ctx.setAlpha(color.alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        ctx.setFillColor(color.opaqueCG)
        ctx.addPath(path)
        ctx.fillPath(using: .winding)
        if translucent { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    private static func drawHighlighters(_ group: [InkStroke], color: InkColor, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setAlpha(highlighterAlpha * color.alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setStrokeColor(color.opaqueCG)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for s in group {
            ctx.setLineWidth(s.averageWidth)
            ctx.addPath(centerline(s.points))
            ctx.strokePath()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// The middle of the line, smoothed.
    static func centerline(_ pts: [InkPoint]) -> CGPath {
        let path = CGMutablePath()
        let dense = densify(pts, spacing: 2)
        guard let first = dense.first else { return path }
        path.move(to: first.cg)
        if dense.count == 1 { path.addLine(to: CGPoint(x: first.cg.x + 0.01, y: first.cg.y)) }
        for p in dense.dropFirst() { path.addLine(to: p.cg) }
        return path
    }

    /// The filled shape of a stroke in its pen's style.
    static func shape(_ pts: [InkPoint], style: InkStyle, tip: InkTip? = nil) -> CGPath {
        if style == .oval { return ovalOutline(pts, tip: tip) }
        return style.isNib ? nibOutline(pts, thickness: style.nibThickness) : outline(pts)
    }

    static func shape(of s: InkStroke) -> CGPath { shape(s.points, style: s.style, tip: s.tip) }

    /// The oval tip leans a little: its right side is slightly higher.
    static let ovalAngle: CGFloat = -16 * .pi / 180
    private static let ovalSides = 28
    private static let ovalUnit: [CGPoint] = (0..<ovalSides).map { i in
        let a = CGFloat(i) / CGFloat(ovalSides) * 2 * .pi
        return CGPoint(x: cos(a), y: sin(a))
    }

    /// The oval tip dragged along the line: each step adds the area the tip sweeps (the
    /// convex hull of the tip at both ends), so the edges are smooth at any zoom.
    static func ovalOutline(_ pts: [InkPoint], tip: InkTip?) -> CGPath {
        let path = CGMutablePath()
        guard !pts.isEmpty else { return path }
        let avg = CGFloat(pts.reduce(Float(0)) { $0 + $1.w }) / CGFloat(pts.count)
        let dense = densify(pts, spacing: max(0.3, min(1.0, avg * 0.2)))
        let ca = cos(ovalAngle), sa = sin(ovalAngle)
        func oval(_ p: InkPoint) -> [CGPoint] {
            let a = max(p.width / 2, 0.15)
            let b = max((tip?.height(forWidth: p.width) ?? p.width) / 2, 0.12)
            let c = p.cg
            return ovalUnit.map { u in
                let x = u.x * a, y = u.y * b
                return CGPoint(x: c.x + x * ca - y * sa, y: c.y + x * sa + y * ca)
            }
        }
        func add(_ q: [CGPoint]) {
            guard q.count > 2 else { return }
            var q = q
            if signedArea(q) < 0 { q.reverse() }
            path.addLines(between: q)
            path.closeSubpath()
        }
        var prev = oval(dense[0])
        add(prev)
        for i in dense.indices.dropFirst() {
            let cur = oval(dense[i])
            add(convexHull(prev + cur))
            prev = cur
        }
        return path
    }

    /// The flat nib's angle: its edge rises to the right, so it's thin travelling up-right
    /// and thickest going straight down.
    static let nibAngle: CGFloat = -22 * .pi / 180

    /// A flat nib (a thin rectangle, `thickness` × its length) dragged along the line. Each step
    /// adds the exact area the nib sweeps (the convex hull of the nib at both ends), so the
    /// edges come out clean and smooth, with crisp angled ends.
    static func nibOutline(_ pts: [InkPoint], thickness: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard !pts.isEmpty else { return path }
        let avg = CGFloat(pts.reduce(Float(0)) { $0 + $1.w }) / CGFloat(pts.count)
        let dense = densify(pts, spacing: max(0.3, min(1.0, avg * 0.2)))
        let ux = cos(nibAngle), uy = sin(nibAngle)
        let nx = -uy, ny = ux
        func nib(_ p: InkPoint) -> [CGPoint] {
            let hl = max(p.width / 2, 0.3)
            let ht = max(hl * thickness, 0.18)
            let c = p.cg
            let hx = ux * hl, hy = uy * hl, kx = nx * ht, ky = ny * ht
            return [CGPoint(x: c.x - hx - kx, y: c.y - hy - ky), CGPoint(x: c.x + hx - kx, y: c.y + hy - ky),
                    CGPoint(x: c.x + hx + kx, y: c.y + hy + ky), CGPoint(x: c.x - hx + kx, y: c.y - hy + ky)]
        }
        func add(_ q: [CGPoint]) {
            guard q.count > 2 else { return }
            var q = q
            if signedArea(q) < 0 { q.reverse() }
            path.addLines(between: q)
            path.closeSubpath()
        }
        var prev = nib(dense[0])
        if dense.count == 1 { add(prev); return path }
        for i in 1..<dense.count {
            let cur = nib(dense[i])
            add(convexHull(prev + cur))
            prev = cur
        }
        return path
    }

    /// Smallest convex shape around the points (monotone chain).
    private static func convexHull(_ pts: [CGPoint]) -> [CGPoint] {
        let s = pts.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard s.count > 2 else { return s }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = []
        for p in s {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in s.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }

    /// The filled shape of a pen stroke whose width changes along the way: a disc at every
    /// point joined by bands, all wound the same way so they merge into one shape.
    static func outline(_ pts: [InkPoint]) -> CGPath {
        let path = CGMutablePath()
        let avg = pts.isEmpty ? 1 : CGFloat(pts.reduce(Float(0)) { $0 + $1.w }) / CGFloat(pts.count)
        let dense = densify(pts, spacing: max(0.35, min(1.2, avg * 0.35)))
        guard !dense.isEmpty else { return path }
        for i in dense.indices {
            let p = dense[i]
            let r = max(p.width / 2, 0.12)
            path.move(to: CGPoint(x: p.cg.x + r, y: p.cg.y))
            path.addArc(center: p.cg, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            path.closeSubpath()
            guard i > 0 else { continue }
            let a = dense[i - 1]
            let dx = p.cg.x - a.cg.x, dy = p.cg.y - a.cg.y
            let len = hypot(dx, dy)
            guard len > 0.0001 else { continue }
            let nx = -dy / len, ny = dx / len
            let ra = max(a.width / 2, 0.12)
            var quad = [CGPoint(x: a.cg.x + nx * ra, y: a.cg.y + ny * ra),
                        CGPoint(x: p.cg.x + nx * r, y: p.cg.y + ny * r),
                        CGPoint(x: p.cg.x - nx * r, y: p.cg.y - ny * r),
                        CGPoint(x: a.cg.x - nx * ra, y: a.cg.y - ny * ra)]
            // Same winding as the discs (positive area), or the overlap would cut holes.
            if signedArea(quad) < 0 { quad.reverse() }
            path.addLines(between: quad)
            path.closeSubpath()
        }
        return path
    }

    private static func signedArea(_ q: [CGPoint]) -> CGFloat {
        var s: CGFloat = 0
        for i in q.indices {
            let a = q[i], b = q[(i + 1) % q.count]
            s += a.x * b.y - b.x * a.y
        }
        return s
    }

    /// Fills in points along a smooth curve (Catmull-Rom) wherever samples are far apart.
    static func densify(_ pts: [InkPoint], spacing: CGFloat) -> [InkPoint] {
        guard pts.count > 1 else { return pts }
        var out: [InkPoint] = [pts[0]]
        out.reserveCapacity(pts.count * 2)
        for i in 1..<pts.count {
            let p0 = pts[max(i - 2, 0)], p1 = pts[i - 1], p2 = pts[i], p3 = pts[min(i + 1, pts.count - 1)]
            let d = hypot(p2.cg.x - p1.cg.x, p2.cg.y - p1.cg.y)
            let steps = Int(min(d / spacing, 60))
            if steps > 1 {
                for k in 1..<steps {
                    let t = Float(k) / Float(steps)
                    let t2 = t * t, t3 = t2 * t
                    func cr(_ a: Float, _ b: Float, _ c: Float, _ e: Float) -> Float {
                        0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - e) * t2 + (-a + 3 * b - 3 * c + e) * t3)
                    }
                    out.append(InkPoint(x: cr(p0.x, p1.x, p2.x, p3.x), y: cr(p0.y, p1.y, p2.y, p3.y),
                                        w: p1.w + (p2.w - p1.w) * t))
                }
            }
            out.append(p2)
        }
        return out
    }

    static let cache = OutlineCache()
}

/// Outlines are worked out once per stroke and shared by every tile that draws it.
final class OutlineCache {
    private let lock = NSLock()
    private var paths: [UUID: CGPath] = [:]

    func outline(for s: InkStroke) -> CGPath {
        lock.lock()
        if let p = paths[s.id] { lock.unlock(); return p }
        lock.unlock()
        let p = InkRenderer.shape(of: s)
        lock.lock()
        if paths.count > 6000 { paths.removeAll(keepingCapacity: true) }
        paths[s.id] = p
        lock.unlock()
        return p
    }
}
