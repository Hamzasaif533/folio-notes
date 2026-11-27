import UIKit

/// Tiles appear at once instead of fading in.
final class InkTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0 }
}

/// Folio's own writing surface. Its bounds are in page units and it is scaled on screen
/// with a transform; the ink is drawn in tiles at the detail the zoom needs, so it stays
/// sharp (and never disappears) however far you zoom in.
///
/// Handles the pens, both erasers, the lasso and moving / resizing / rotating a selection.
final class InkCanvasView: UIView {
    override class var layerClass: AnyClass { InkTiledLayer.self }

    private(set) var drawing = InkDrawing()

    /// What the background tile renderer reads (tiles draw on other threads).
    private let renderLock = NSLock()
    private var renderStrokes: [InkStroke] = []
    private var renderHidden: Set<UUID> = []

    var tool: InkTool = .none {
        didSet { if tool != oldValue { clearSelection(); eraserRing.isHidden = true; loopCandidate = nil } }
    }
    /// A circle drawn then tapped switched this page to the lasso (the editor should follow).
    var onSwitchToLasso: (() -> Void)?
    var fingerDraws = false

    var onBegan: (() -> Void)?
    var onEnded: (() -> Void)?
    /// A finished change (a stroke, an erase, a lasso edit): before and after, for undo and saving.
    var onCommit: ((InkCanvasView, InkDrawing, InkDrawing) -> Void)?
    /// The lasso selection appeared, moved or went away.
    var onSelectionChanged: ((InkCanvasView) -> Void)?
    /// The eraser passed over these points (ink coordinates) with this radius.
    var onErase: ((InkCanvasView, [CGPoint], CGFloat) -> Void)?
    /// The eraser was lifted.
    var onEraseEnded: (() -> Void)?
    /// A finger is dragging the selection, so the page shouldn't scroll.
    var onObjectTouch: ((Bool) -> Void)?
    /// Ruler: for a stroke starting here, a function that keeps it on the ruler's edge (or nil).
    var rulerSnap: ((InkCanvasView, CGPoint) -> ((CGPoint) -> CGPoint)?)?

    private let overlay = UIView()
    private let liveLayer = CAShapeLayer()
    private let lassoLayer = CAShapeLayer()
    private let eraserRing = CAShapeLayer()
    private let selectionContainer = CALayer()
    private let selectionSnapshot = CALayer()
    private let chromeLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()

    private static let selectionBlue = UIColor(red: 0.1, green: 0.55, blue: 0.95, alpha: 1)

    init(size: CGSize) {
        super.init(frame: CGRect(origin: .zero, size: size))
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        if let tiled = layer as? CATiledLayer {
            tiled.levelsOfDetail = 8
            tiled.levelsOfDetailBias = 4
            tiled.tileSize = CGSize(width: 512, height: 512)
        }
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        overlay.frame = bounds
        addSubview(overlay)

        liveLayer.fillRule = .nonZero
        lassoLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.05).cgColor
        lassoLayer.strokeColor = Self.selectionBlue.cgColor
        eraserRing.fillColor = UIColor.white.withAlphaComponent(0.35).cgColor
        eraserRing.strokeColor = UIColor.gray.cgColor
        eraserRing.isHidden = true
        selectionContainer.anchorPoint = .zero
        selectionContainer.addSublayer(selectionSnapshot)
        chromeLayer.fillColor = nil
        chromeLayer.strokeColor = Self.selectionBlue.cgColor
        handleLayer.fillColor = UIColor.white.cgColor
        handleLayer.strokeColor = Self.selectionBlue.cgColor
        for l in [selectionContainer, liveLayer, lassoLayer, chromeLayer, handleLayer, eraserRing] {
            overlay.layer.addSublayer(l)
        }
        for l in [liveLayer, lassoLayer, eraserRing, chromeLayer, handleLayer, selectionContainer, selectionSnapshot] {
            l.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "contents": NSNull(),
                         "transform": NSNull(), "hidden": NSNull(), "opacity": NSNull()]
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlay.frame = bounds
        selectionContainer.bounds = bounds
        selectionContainer.position = .zero
    }

    /// The page grew (Add Space) or the endless canvas got bigger.
    func setSize(_ size: CGSize) {
        guard size != bounds.size else { return }
        bounds = CGRect(origin: .zero, size: size)
        setNeedsLayout()
        setNeedsDisplay()
    }

    // MARK: Drawing

    /// Replaces all the ink (loading a page, undo, the zoom box keeping in step).
    func setDrawing(_ d: InkDrawing) {
        guard d != drawing else { return }
        drawing = d
        if let sel = selection, !sel.ids.isSubset(of: Set(d.strokes.map { $0.id })) {
            selection = nil
            hideSelectionChrome()
        }
        publish()
        setNeedsDisplay()
    }

    private func publish() {
        renderLock.lock()
        renderStrokes = drawing.strokes
        renderHidden = selection?.ids ?? []
        renderLock.unlock()
    }

    private func invalidate(_ r: CGRect) {
        guard !r.isNull, !r.isEmpty else { return }
        setNeedsDisplay(r.insetBy(dx: -2, dy: -2))
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        renderLock.lock()
        let strokes = renderStrokes
        let hidden = renderHidden
        renderLock.unlock()
        InkRenderer.draw(strokes, in: ctx, rect: rect, hidden: hidden)
    }

    /// Screen points per page unit right now.
    private var displayScale: CGFloat {
        guard let w = window else { return 1 }
        let a = convert(CGPoint.zero, to: w), b = convert(CGPoint(x: 100, y: 0), to: w)
        return max(hypot(b.x - a.x, b.y - a.y) / 100, 0.01)
    }

    private var screenScale: CGFloat { window?.screen.scale ?? traitCollection.displayScale }

    /// Shape layers are drawn at this resolution so they stay crisp under the zoom.
    private func sharpness() -> CGFloat { min(screenScale * displayScale, 24) }

    /// Call after the zoom changes, so handles keep their on-screen size.
    func zoomChanged() {
        guard selection != nil, mode == .idle else { return }
        ds = displayScale
        updateChrome()
    }

    // MARK: Touches

    private enum Mode { case idle, drawing, erasing, lassoing, manipulating }
    private var mode = Mode.idle
    private var activeTouch: UITouch?
    private var ds: CGFloat = 1

    private func canWrite(_ t: UITouch) -> Bool { t.type == .pencil || (fingerDraws && t.type == .direct) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let active = activeTouch {
            // A second finger while writing with a finger means scrolling, zooming or an undo tap.
            if mode == .drawing, active.type == .direct, touches.contains(where: { $0.type == .direct }) {
                cancelActive()
            }
            return
        }
        guard let t = touches.first else { return }
        let p = t.preciseLocation(in: self)
        ds = displayScale

        if case .lasso = tool, selection != nil {
            if let m = manipulation(at: p) {
                activeTouch = t
                beginManipulation(m, at: p)
                if t.type == .direct { onObjectTouch?(true) }
                onBegan?()
                return
            }
            if canWrite(t) { clearSelection() } else { return }
        }
        guard canWrite(t) else { return }
        if t.type == .direct, (event?.allTouches?.filter { $0.type == .direct }.count ?? 0) > 1 { return }

        switch tool {
        case .pen(let pen):
            activeTouch = t
            // A tap inside a circle you just drew may turn it into a lasso.
            loopTap = nil
            if let c = loopCandidate, Date().timeIntervalSince(c.time) < 6, c.poly.contains(p) {
                loopTap = (t.timestamp, p)
            }
            beginStroke(t, pen: pen)
        case .eraser:
            activeTouch = t
            beginErase(at: p)
        case .lasso:
            activeTouch = t
            beginLasso(at: p)
        case .none:
            return
        }
        onBegan?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        let samples = event?.coalescedTouches(for: t) ?? [t]
        switch mode {
        case .drawing:
            guard case .pen(let pen) = tool else { return }
            for s in samples { addPoint(s, pen: pen) }
            updateLive(pen: pen, predicted: event?.predictedTouches(for: t) ?? [])
        case .erasing:
            for s in samples { erase(at: s.preciseLocation(in: self)) }
        case .lassoing:
            for s in samples { lassoPoints.append(s.preciseLocation(in: self)) }
            updateLasso()
        case .manipulating:
            manipulate(to: t.preciseLocation(in: self))
        case .idle:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        switch mode {
        case .drawing:
            if case .pen(let pen) = tool {
                if let tap = loopTap, let c = loopCandidate, t.timestamp - tap.time < 0.4,
                   points.allSatisfy({ hypot($0.cg.x - tap.at.x, $0.cg.y - tap.at.y) < 6 / ds }) {
                    // Just a tap, not writing: no dot, the circle becomes the lasso.
                    liveLayer.path = nil
                    points = []
                    snap = nil
                    loopTap = nil
                    lassoFromLoop(c, tapAt: tap.at)
                } else {
                    loopTap = nil
                    addPoint(t, pen: pen); catchUp(t, pen: pen); finishStroke(pen: pen)
                }
            }
        case .erasing:
            finishErase()
            onEraseEnded?()
        case .lassoing: finishLasso()
        case .manipulating:
            finishManipulation()
            if t.type == .direct { onObjectTouch?(false) }
        case .idle: break
        }
        activeTouch = nil
        mode = .idle
        onEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        cancelActive()
    }

    private func cancelActive() {
        switch mode {
        case .drawing:
            liveLayer.path = nil
            points = []
        case .erasing:
            finishErase() // keep what was already rubbed out, as an undoable step
        case .lassoing:
            lassoLayer.path = nil
            lassoPoints = []
        case .manipulating:
            finishManipulation()
            if activeTouch?.type == .direct { onObjectTouch?(false) }
        case .idle: break
        }
        activeTouch = nil
        mode = .idle
        onEnded?()
    }

    // MARK: Pens

    private var points: [InkPoint] = []
    private var smoothedWidth: CGFloat = 0
    private var direction: CGFloat = 0
    private var lastTime: TimeInterval = 0
    /// How fast the Pencil is moving (screen points a second, smoothed), for the pointed tail on a quick lift.
    private var moveSpeed: CGFloat = 0
    private var speedSample: (at: CGPoint, time: TimeInterval)?
    private var snap: ((CGPoint) -> CGPoint)?

    private func beginStroke(_ t: UITouch, pen: InkPen) {
        mode = .drawing
        points = []
        steady = nil
        smoothedWidth = 0
        direction = 0
        lastTime = t.timestamp
        moveSpeed = 0
        speedSample = nil
        snap = rulerSnap?(self, t.preciseLocation(in: self))
        configure(liveLayer, pen: pen)
        addPoint(t, pen: pen)
        updateLive(pen: pen, predicted: [])
    }

    /// Where the Pencil is, kept on the ruler's edge when drawing along it.
    private func location(_ t: UITouch) -> CGPoint {
        let p = t.preciseLocation(in: self)
        return snap?(p) ?? p
    }

    /// Steadiness (Pen Settings): the line follows the Pencil a little behind, smoothing shakes.
    private var steady: CGPoint?

    private func addPoint(_ t: UITouch, pen: InkPen) {
        var loc = location(t)
        trackSpeed(t)
        let s = CGFloat(pen.feel.stabilization)
        if s > 0.01, let prev = steady {
            let a = 1 - 0.85 * min(s, 1)
            loc = CGPoint(x: prev.x + (loc.x - prev.x) * a, y: prev.y + (loc.y - prev.y) * a)
        }
        steady = loc
        if let last = points.last, hypot(last.cg.x - loc.x, last.cg.y - loc.y) < 0.25 / ds { return }
        points.append(InkPoint(loc, w: width(for: t, at: loc, pen: pen)))
    }

    private func trackSpeed(_ t: UITouch) {
        // The lift itself often repeats the last spot, so it says nothing about speed, except
        // that a Pencil held still for a moment before lifting sends nothing at all.
        if t.phase == .ended {
            if let s = speedSample, t.timestamp - s.time > 0.06 { moveSpeed = 0 }
            return
        }
        let p = t.preciseLocation(in: self)
        if let s = speedSample {
            let dt = t.timestamp - s.time
            guard dt > 0.002 else { return }
            let v = hypot(p.x - s.at.x, p.y - s.at.y) * ds / CGFloat(dt)
            // Quick to notice a stop, so stopping before lifting leaves a round end.
            moveSpeed += (v - moveSpeed) * (v < moveSpeed ? 0.6 : 0.4)
        }
        speedSample = (p, t.timestamp)
    }

    /// With steadiness on, the line still ends where the Pencil lifted.
    private func catchUp(_ t: UITouch, pen: InkPen) {
        guard pen.feel.stabilization > 0.01, let last = points.last else { return }
        let end = location(t)
        if hypot(last.cg.x - end.x, last.cg.y - end.y) > 0.25 / ds { points.append(InkPoint(end, w: last.width)) }
    }

    /// Line width at this point, from pressure and (for a flat nib) the direction of travel.
    private func width(for t: UITouch, at loc: CGPoint, pen: InkPen) -> CGFloat {
        if pen.style == .highlighter || pen.shapes { return pen.width }
        var pressure: CGFloat = 0.5
        if t.type == .pencil, t.force > 0 {
            pressure = pow(min(max(t.force / 2.2, 0), 1), 0.6)
        }
        if let last = points.last {
            let dx = loc.x - last.cg.x, dy = loc.y - last.cg.y
            if hypot(dx, dy) > 0.6 / ds { direction = atan2(dy, dx) }
            if t.type != .pencil, pen.style == .fountain || pen.style == .oval {
                // Fingers have no pressure: a quick line is a thin line.
                let dt = max(t.timestamp - lastTime, 0.001)
                let speed = hypot(dx, dy) * ds / CGFloat(dt)
                pressure = min(max(1 - speed / 1800, 0.25), 0.85)
            }
        }
        if t.type == .pencil, pen.style == .fountain, let last = points.last {
            // Ink flows thinner on a quick stroke and pools a little on a slow one.
            let dt = max(t.timestamp - lastTime, 0.001)
            let speed = hypot(loc.x - last.cg.x, loc.y - last.cg.y) * ds / CGFloat(dt)
            pressure *= 1.08 - 0.4 * min(speed / 2600, 1)
        }
        var w = pen.width(pressure: pressure, direction: direction)
        if t.type == .pencil, pen.style == .fountain {
            // A tilted Pencil writes on more of the nib: a little wider.
            w *= 1 + 0.22 * (1 - min(t.altitudeAngle / (.pi / 2), 1))
        }
        lastTime = t.timestamp
        smoothedWidth = smoothedWidth == 0 ? w : smoothedWidth + (w - smoothedWidth) * 0.3
        return max(smoothedWidth, 0.25)
    }

    private func configure(_ l: CAShapeLayer, pen: InkPen) {
        let c = InkColor(hex: pen.colorHex, opacity: pen.opacity)
        l.contentsScale = sharpness()
        if pen.style == .highlighter {
            l.fillColor = nil
            l.strokeColor = c.opaqueCG
            l.lineWidth = pen.width
            l.lineCap = .round
            l.lineJoin = .round
            l.opacity = Float(InkRenderer.highlighterAlpha * c.alpha)
        } else {
            l.strokeColor = nil
            l.fillColor = c.opaqueCG
            l.opacity = Float(c.alpha)
        }
    }

    private func updateLive(pen: InkPen, predicted: [UITouch]) {
        var pts = points
        if let last = pts.last {
            for p in predicted { pts.append(InkPoint(location(p), w: last.width)) }
        }
        liveLayer.path = pen.style == .highlighter ? InkRenderer.centerline(pts)
                                                   : InkRenderer.shape(pen.tapered(pts, end: false), style: pen.style, tip: pen.tip)
    }

    private func finishStroke(pen: InkPen) {
        defer { points = []; snap = nil }
        guard !points.isEmpty else { liveLayer.path = nil; return }
        let raw = points.map(\.cg)
        loopCandidate = nil
        if !pen.shapes, pen.style != .highlighter, Self.scribbleEnabled, scribbleErase(raw, pen: pen) { return }
        let color = InkColor(hex: pen.colorHex, opacity: pen.opacity)
        var stroke = InkStroke(style: pen.style, color: color,
                               points: pen.liftTapered(pen.tapered(points), speed: moveSpeed), tip: pen.tip)
        if pen.shapes, let clean = StrokeShaper.recognizeShape(points.map { $0.cg }) {
            stroke = InkStroke(style: pen.style, color: color, points: clean.map { InkPoint($0, w: pen.width) })
        }
        let before = drawing
        drawing.strokes.append(stroke)
        publish()
        invalidate(stroke.bounds)
        // Keep showing the stroke until its tiles have redrawn, so it never blinks.
        let glow = CAShapeLayer()
        glow.actions = liveLayer.actions
        configure(glow, pen: pen)
        glow.path = pen.style == .highlighter ? InkRenderer.centerline(stroke.points) : InkRenderer.shape(of: stroke)
        overlay.layer.insertSublayer(glow, below: liveLayer)
        liveLayer.path = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { glow.removeFromSuperlayer() }
        onCommit?(self, before, drawing)
        // A loop drawn around some ink: tap inside it soon after to lasso what's in it.
        if !pen.shapes, Self.circleLassoEnabled, let poly = Self.loop(raw),
           !strokeIDs(inside: poly, excluding: stroke.id).isEmpty {
            loopCandidate = LoopCandidate(strokeID: stroke.id, poly: poly, time: Date())
        }
    }

    // MARK: Pen gestures: scribble to erase, circle then tap to lasso

    static var scribbleEnabled: Bool { UserDefaults.standard.object(forKey: "folio.scribbleErase") as? Bool ?? true }
    static var circleLassoEnabled: Bool { UserDefaults.standard.object(forKey: "folio.circleLasso") as? Bool ?? true }

    private struct LoopCandidate {
        let strokeID: UUID
        let poly: CGPath
        let time: Date
    }
    private var loopCandidate: LoopCandidate?
    private var loopTap: (time: TimeInterval, at: CGPoint)?

    private static func box(_ pts: [CGPoint]) -> CGRect {
        pts.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    private static func length(_ pts: [CGPoint]) -> CGFloat {
        zip(pts, pts.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// How many times a value turns back by more than `threshold` (back-and-forth strokes).
    private static func reversals(_ v: [CGFloat], threshold: CGFloat) -> Int {
        guard let first = v.first else { return 0 }
        var extreme = first
        var dir: CGFloat = 0
        var count = 0
        for x in v.dropFirst() {
            if dir == 0 {
                if abs(x - extreme) > threshold { dir = x > extreme ? 1 : -1; extreme = x }
                continue
            }
            if (dir > 0 && x > extreme) || (dir < 0 && x < extreme) {
                extreme = x
            } else if abs(x - extreme) > threshold {
                count += 1
                dir = -dir
                extreme = x
            }
        }
        return count
    }

    /// A closed, roundish loop (start and end close together), as a polygon.
    private static func loop(_ pts: [CGPoint]) -> CGPath? {
        guard pts.count >= 16, let f = pts.first, let l = pts.last else { return nil }
        let b = box(pts)
        let span = max(b.width, b.height)
        guard span > 30, min(b.width, b.height) > span * 0.3 else { return nil }
        let len = length(pts)
        guard hypot(f.x - l.x, f.y - l.y) < span * 0.3, len > span * 2.3, len < span * 5 else { return nil }
        let p = CGMutablePath()
        p.addLines(between: pts)
        p.closeSubpath()
        return p
    }

    /// Strokes that are mostly inside the loop.
    private func strokeIDs(inside poly: CGPath, excluding skip: UUID?) -> Set<UUID> {
        var ids: Set<UUID> = []
        for s in drawing.strokes where s.id != skip && poly.boundingBoxOfPath.intersects(s.bounds) {
            let step = max(1, s.points.count / 40)
            var inside = 0, total = 0
            var i = 0
            while i < s.points.count {
                total += 1
                if poly.contains(s.points[i].cg) { inside += 1 }
                i += step
            }
            if total > 0 && Double(inside) / Double(total) >= 0.5 { ids.insert(s.id) }
        }
        return ids
    }

    /// Scribbling back and forth over ink rubs it out. Returns true if it did (the scribble isn't kept).
    private func scribbleErase(_ pts: [CGPoint], pen: InkPen) -> Bool {
        guard pts.count >= 12 else { return false }
        let b = Self.box(pts)
        let span = max(b.width, b.height)
        guard span > 8, Self.length(pts) > span * 4 else { return false }
        let turns = max(Self.reversals(pts.map(\.x), threshold: max(b.width * 0.3, 3)),
                        Self.reversals(pts.map(\.y), threshold: max(b.height * 0.3, 3)))
        guard turns >= 5 else { return false }
        let r = max(pen.width / 2, 1.5)
        let dense = InkRenderer.densify(pts.map { InkPoint($0, w: pen.width) }, spacing: max(r * 0.8, 1)).map(\.cg)
        let area = b.insetBy(dx: -r, dy: -r)
        var hit: [InkStroke] = []
        for s in drawing.strokes where s.bounds.intersects(area) {
            // Only ink that the scribble mostly covers, so writing next to words never erases them.
            let inter = s.bounds.intersection(area)
            let cover = (inter.width * inter.height) / max(s.bounds.width * s.bounds.height, 0.01)
            guard cover >= 0.5 || (s.bounds.width < 6 && s.bounds.height < 6) else { continue }
            if Self.touches(s, samples: dense, radius: r) { hit.append(s) }
        }
        guard !hit.isEmpty else { return false }
        let before = drawing
        let ids = Set(hit.map(\.id))
        drawing.strokes.removeAll { ids.contains($0.id) }
        publish()
        invalidate(hit.reduce(b) { $0.union($1.bounds) })
        // No animation: the scribble and the ink under it just go.
        liveLayer.path = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCommit?(self, before, drawing)
        return true
    }

    private func fadeAndRemove(_ l: CALayer, duration: CFTimeInterval, delay: CFTimeInterval = 0) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = l.opacity
        a.toValue = 0
        a.beginTime = CACurrentMediaTime() + delay
        a.duration = duration
        a.fillMode = .both
        a.isRemovedOnCompletion = false
        l.add(a, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.05) { l.removeFromSuperlayer() }
    }

    /// The circle you drew turns into a lasso around everything inside it.
    private func lassoFromLoop(_ c: LoopCandidate, tapAt tap: CGPoint) {
        loopCandidate = nil
        guard let circle = drawing.strokes.first(where: { $0.id == c.strokeID }) else { return }
        let ids = strokeIDs(inside: c.poly, excluding: c.strokeID)
        guard !ids.isEmpty else { return }
        let before = drawing
        drawing.strokes.removeAll { $0.id == c.strokeID }
        publish()
        invalidate(circle.bounds)
        onCommit?(self, before, drawing)

        // The ink circle fades as a dashed selection loop runs around it.
        let ink = CAShapeLayer()
        ink.path = InkRenderer.shape(of: circle)
        ink.fillColor = circle.color.uiColor.cgColor
        ink.contentsScale = sharpness()
        overlay.layer.addSublayer(ink)
        fadeAndRemove(ink, duration: 0.3)

        let loopLayer = CAShapeLayer()
        loopLayer.path = c.poly
        loopLayer.fillColor = Self.selectionBlue.withAlphaComponent(0.08).cgColor
        loopLayer.strokeColor = Self.selectionBlue.cgColor
        loopLayer.lineWidth = 2 / ds
        loopLayer.lineDashPattern = [NSNumber(value: Double(7 / ds)), NSNumber(value: Double(5 / ds))]
        loopLayer.contentsScale = sharpness()
        overlay.layer.addSublayer(loopLayer)
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.32
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        loopLayer.add(draw, forKey: "draw")
        let march = CABasicAnimation(keyPath: "lineDashPhase")
        march.fromValue = 0
        march.toValue = -24 / ds
        march.duration = 0.5
        march.repeatCount = .infinity
        loopLayer.add(march, forKey: "march")
        fadeAndRemove(loopLayer, duration: 0.35, delay: 0.6)

        // A ripple where you tapped.
        let size = 56 / ds
        let ripple = CAShapeLayer()
        ripple.frame = CGRect(x: tap.x - size / 2, y: tap.y - size / 2, width: size, height: size)
        ripple.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
        ripple.fillColor = Self.selectionBlue.withAlphaComponent(0.15).cgColor
        ripple.strokeColor = Self.selectionBlue.cgColor
        ripple.lineWidth = 2 / ds
        ripple.contentsScale = sharpness()
        overlay.layer.addSublayer(ripple)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.15
        grow.toValue = 1
        grow.duration = 0.4
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(grow, forKey: "grow")
        fadeAndRemove(ripple, duration: 0.4)

        tool = .lasso
        onSwitchToLasso?()
        select(ids)
        // The picked ink lifts a little, then settles.
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 1.07
        pop.toValue = 1
        pop.damping = 11
        pop.initialVelocity = 2
        pop.duration = pop.settlingDuration
        selectionSnapshot.add(pop, forKey: "pop")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: Erasers

    private var beforeEdit: InkDrawing?
    private var lastEraserPoint: CGPoint?
    private var eraserRadius: CGFloat = 8

    private func beginErase(at p: CGPoint) {
        mode = .erasing
        beforeEdit = drawing
        lastEraserPoint = nil
        if case .eraser(let precise, let width) = tool {
            eraserRadius = precise ? max(width / 2, 1) : 9 / ds
        }
        eraserRing.lineWidth = 1 / ds
        eraserRing.contentsScale = sharpness()
        eraserRing.isHidden = false
        erase(at: p)
    }

    private func erase(at p: CGPoint) {
        let r = eraserRadius
        eraserRing.path = CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2), transform: nil)
        // Fill the gap between touch samples so a quick swipe still erases everything it crosses.
        var samples = [p]
        if let last = lastEraserPoint {
            let d = hypot(p.x - last.x, p.y - last.y)
            let n = Int(min(d / max(r * 0.5, 0.5), 80))
            if n > 1 {
                samples = (1...n).map { i in
                    let f = CGFloat(i) / CGFloat(n)
                    return CGPoint(x: last.x + (p.x - last.x) * f, y: last.y + (p.y - last.y) * f)
                }
            }
        }
        lastEraserPoint = p
        onErase?(self, samples, r)
        guard case .eraser(let precise, _) = tool else { return }
        let area = samples.reduce(CGRect.null) { $0.union(CGRect(x: $1.x - r, y: $1.y - r, width: r * 2, height: r * 2)) }
        var changed = CGRect.null
        var out: [InkStroke] = []
        out.reserveCapacity(drawing.strokes.count)
        for s in drawing.strokes {
            guard s.bounds.intersects(area) else { out.append(s); continue }
            if precise {
                let pieces = Self.cut(s, samples: samples, radius: r)
                if let pieces {
                    changed = changed.union(s.bounds)
                    out.append(contentsOf: pieces)
                } else {
                    out.append(s)
                }
            } else if Self.touches(s, samples: samples, radius: r) {
                changed = changed.union(s.bounds)
            } else {
                out.append(s)
            }
        }
        guard !changed.isNull else { return }
        drawing.strokes = out
        publish()
        invalidate(changed)
    }

    private func finishErase() {
        eraserRing.isHidden = true
        lastEraserPoint = nil
        if let before = beforeEdit, before != drawing { onCommit?(self, before, drawing) }
        beforeEdit = nil
    }

    /// Whole-stroke eraser: does the eraser touch this stroke anywhere?
    private static func touches(_ s: InkStroke, samples: [CGPoint], radius r: CGFloat) -> Bool {
        let pts = s.points
        for c in samples {
            if pts.count == 1 {
                if hypot(pts[0].cg.x - c.x, pts[0].cg.y - c.y) < r + pts[0].width / 2 { return true }
                continue
            }
            for i in 1..<pts.count {
                let reach = r + max(pts[i].width, pts[i - 1].width) / 2
                if distance(c, pts[i - 1].cg, pts[i].cg) < reach { return true }
            }
        }
        return false
    }

    /// Precise eraser: the stroke with the rubbed-out part removed (nil if untouched).
    private static func cut(_ s: InkStroke, samples: [CGPoint], radius r: CGFloat) -> [InkStroke]? {
        guard touches(s, samples: samples, radius: r) else { return nil }
        let dense = InkRenderer.densify(s.points, spacing: max(min(r * 0.3, 1), 0.3))
        var runs: [[InkPoint]] = [[]]
        for p in dense {
            let hit = samples.contains { hypot($0.x - p.cg.x, $0.y - p.cg.y) < r + p.width * 0.35 }
            if hit {
                if !(runs.last?.isEmpty ?? true) { runs.append([]) }
            } else {
                runs[runs.count - 1].append(p)
            }
        }
        return runs.filter { $0.count > 1 }.map { InkStroke(style: s.style, color: s.color, points: $0, tip: s.tip) }
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0.000001 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: Lasso

    private var lassoPoints: [CGPoint] = []

    private func beginLasso(at p: CGPoint) {
        mode = .lassoing
        lassoPoints = [p]
        lassoLayer.contentsScale = sharpness()
        lassoLayer.lineWidth = 1.5 / ds
        lassoLayer.lineDashPattern = [NSNumber(value: Double(6 / ds)), NSNumber(value: Double(4 / ds))]
        updateLasso()
    }

    private func updateLasso() {
        let path = CGMutablePath()
        if let f = lassoPoints.first {
            path.move(to: f)
            for p in lassoPoints.dropFirst() { path.addLine(to: p) }
        }
        lassoLayer.path = path
    }

    private func finishLasso() {
        defer { lassoLayer.path = nil; lassoPoints = [] }
        guard lassoPoints.count > 2 else { return }
        let poly = CGMutablePath()
        poly.addLines(between: lassoPoints)
        poly.closeSubpath()
        // A stroke is picked when most of it is inside the loop.
        var ids: Set<UUID> = []
        for s in drawing.strokes where poly.boundingBoxOfPath.intersects(s.bounds) {
            let step = max(1, s.points.count / 40)
            var inside = 0, total = 0
            var i = 0
            while i < s.points.count {
                total += 1
                if poly.contains(s.points[i].cg) { inside += 1 }
                i += step
            }
            if total > 0 && Double(inside) / Double(total) >= 0.5 { ids.insert(s.id) }
        }
        if !ids.isEmpty { select(ids) }
    }

    // MARK: Selection

    private struct Selection {
        var ids: Set<UUID>
        var rect: CGRect
    }
    private var selection: Selection?
    /// The move / resize / turn in progress, applied when you let go.
    private var manipT = CGAffineTransform.identity
    private enum Manip { case move, scale, rotate }
    private var manip: Manip = .move
    private var manipStart: CGPoint = .zero
    private var startT = CGAffineTransform.identity

    var hasSelection: Bool { selection != nil }

    /// Where the selection is now, in this view's coordinates.
    var selectionFrame: CGRect? {
        guard selection != nil else { return nil }
        return selectionCorners().reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    private func select(_ ids: Set<UUID>) {
        let strokes = drawing.strokes.filter { ids.contains($0.id) }
        guard !strokes.isEmpty else { clearSelection(); return }
        let rect = strokes.reduce(CGRect.null) { $0.union($1.bounds) }
        selection = Selection(ids: ids, rect: rect)
        manipT = .identity
        publish()
        invalidate(rect)
        // A picture of the picked strokes, which moves smoothly while you drag it.
        let wanted = screenScale * max(displayScale, 1)
        let scale = min(wanted, sqrt(14_000_000 / max(rect.width * rect.height, 1)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(scale, 0.5)
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: rect.size, format: format).image { r in
            r.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            InkRenderer.draw(strokes, in: r.cgContext)
        }
        selectionSnapshot.contents = img.cgImage
        selectionSnapshot.frame = rect
        selectionContainer.setAffineTransform(.identity)
        selectionContainer.isHidden = false
        ds = displayScale
        updateChrome()
        onSelectionChanged?(self)
    }

    func clearSelection() {
        guard let sel = selection else { return }
        selection = nil
        publish()
        invalidate(sel.rect.applying(manipT))
        manipT = .identity
        chromeLayer.path = nil
        handleLayer.path = nil
        // Give the tiles a moment to draw the strokes before the picture goes.
        let snapshot = selectionSnapshot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.selection == nil else { return }
            snapshot.contents = nil
            self.selectionContainer.setAffineTransform(.identity)
        }
        onSelectionChanged?(self)
    }

    private func hideSelectionChrome() {
        chromeLayer.path = nil
        handleLayer.path = nil
        selectionSnapshot.contents = nil
        manipT = .identity
        onSelectionChanged?(self)
    }

    private var paddedRect: CGRect {
        guard let sel = selection else { return .null }
        let pad = 10 / ds
        return sel.rect.insetBy(dx: -pad, dy: -pad)
    }

    /// Top-left, top-right, bottom-right, bottom-left, after the move / resize / turn.
    private func selectionCorners() -> [CGPoint] {
        let r = paddedRect
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)].map { $0.applying(manipT) }
    }

    private var rotateKnob: CGPoint {
        let c = selectionCorners()
        let top = CGPoint(x: (c[0].x + c[1].x) / 2, y: (c[0].y + c[1].y) / 2)
        let mid = CGPoint(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        let dx = top.x - mid.x, dy = top.y - mid.y
        let len = max(hypot(dx, dy), 0.001)
        let reach = 30 / ds
        return CGPoint(x: top.x + dx / len * reach, y: top.y + dy / len * reach)
    }

    private func updateChrome() {
        guard selection != nil else { return }
        let c = selectionCorners()
        let box = CGMutablePath()
        box.addLines(between: c)
        box.closeSubpath()
        let top = CGPoint(x: (c[0].x + c[1].x) / 2, y: (c[0].y + c[1].y) / 2)
        let knob = rotateKnob
        box.move(to: top)
        box.addLine(to: knob)
        chromeLayer.path = box
        chromeLayer.lineWidth = 1.5 / ds
        chromeLayer.lineDashPattern = [NSNumber(value: Double(6 / ds)), NSNumber(value: Double(4 / ds))]
        chromeLayer.contentsScale = sharpness()

        let r = 9 / ds
        let handles = CGMutablePath()
        handles.addEllipse(in: CGRect(x: c[2].x - r, y: c[2].y - r, width: r * 2, height: r * 2))
        handles.addEllipse(in: CGRect(x: knob.x - r, y: knob.y - r, width: r * 2, height: r * 2))
        handleLayer.path = handles
        handleLayer.lineWidth = 2 / ds
        handleLayer.contentsScale = sharpness()
        selectionContainer.setAffineTransform(manipT)
    }

    private func manipulation(at p: CGPoint) -> Manip? {
        guard selection != nil else { return nil }
        let tol = 26 / ds
        let knob = rotateKnob
        if hypot(p.x - knob.x, p.y - knob.y) < tol { return .rotate }
        let br = selectionCorners()[2]
        if hypot(p.x - br.x, p.y - br.y) < tol { return .scale }
        let local = p.applying(manipT.inverted())
        return paddedRect.contains(local) ? .move : nil
    }

    private func beginManipulation(_ m: Manip, at p: CGPoint) {
        mode = .manipulating
        manip = m
        manipStart = p
        startT = manipT
    }

    private func manipulate(to p: CGPoint) {
        guard let sel = selection else { return }
        let center = CGPoint(x: sel.rect.midX, y: sel.rect.midY).applying(startT)
        func about(_ t: CGAffineTransform) -> CGAffineTransform {
            CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(t)
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        }
        switch manip {
        case .move:
            manipT = startT.concatenating(CGAffineTransform(translationX: p.x - manipStart.x, y: p.y - manipStart.y))
        case .scale:
            let d0 = max(hypot(manipStart.x - center.x, manipStart.y - center.y), 0.001)
            let d1 = hypot(p.x - center.x, p.y - center.y)
            let currentScale = sqrt(abs(startT.a * startT.d - startT.b * startT.c))
            let s = min(max(d1 / d0, 0.08 / max(currentScale, 0.01)), 12 / max(currentScale, 0.01))
            manipT = startT.concatenating(about(CGAffineTransform(scaleX: s, y: s)))
        case .rotate:
            var angle = atan2(p.y - center.y, p.x - center.x) - atan2(manipStart.y - center.y, manipStart.x - center.x)
            // Snap to straight when close to it.
            let total = atan2(startT.b, startT.a) + angle
            let nearest = (total / (.pi / 2)).rounded() * (.pi / 2)
            if abs(total - nearest) < 3 * .pi / 180 { angle += nearest - total }
            manipT = startT.concatenating(about(CGAffineTransform(rotationAngle: angle)))
        }
        updateChrome()
        onSelectionChanged?(self)
    }

    private func finishManipulation() {
        guard let sel = selection, !manipT.isIdentity else { return }
        let before = drawing
        var newIds: Set<UUID> = []
        drawing.strokes = drawing.strokes.map { s in
            guard sel.ids.contains(s.id) else { return s }
            let moved = s.applying(manipT)
            newIds.insert(moved.id)
            return moved
        }
        manipT = .identity
        select(newIds)
        onCommit?(self, before, drawing)
    }

    // MARK: Selection actions

    func deleteSelection() {
        guard let sel = selection else { return }
        let before = drawing
        drawing.strokes.removeAll { sel.ids.contains($0.id) }
        selection = nil
        selectionSnapshot.contents = nil
        chromeLayer.path = nil
        handleLayer.path = nil
        publish()
        invalidate(sel.rect)
        onSelectionChanged?(self)
        onCommit?(self, before, drawing)
    }

    func duplicateSelection() {
        guard let sel = selection else { return }
        let before = drawing
        let shift = CGAffineTransform(translationX: 24, y: 24)
        let copies = drawing.strokes.filter { sel.ids.contains($0.id) }.map { $0.applying(shift) }
        drawing.strokes.append(contentsOf: copies)
        select(Set(copies.map { $0.id }))
        onCommit?(self, before, drawing)
    }

    func recolorSelection(_ hex: String) {
        guard let sel = selection else { return }
        let before = drawing
        let color = InkColor(hex: hex)
        var newIds: Set<UUID> = []
        drawing.strokes = drawing.strokes.map { s in
            guard sel.ids.contains(s.id) else { return s }
            let c = s.recolored(color)
            newIds.insert(c.id)
            return c
        }
        select(newIds)
        onCommit?(self, before, drawing)
    }
}
