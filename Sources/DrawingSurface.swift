import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Shared behaviour for the paged notebook and the infinite canvas:
/// Apple Pencil Pro double-tap and squeeze, palm rejection, undo, tool state,
/// the laser pointer, tape, text boxes and the pen-feel/shape post-processing.
class DrawingSurfaceController: UIViewController, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
    let store: LibraryStore
    var notebook: Notebook

    let undo = UndoManager()
    override var undoManager: UndoManager? { undo }

    var tool: InkTool = .none
    var inputMode: DrawingInput = .pencilOnly
    var rulerOn = false

    /// The editor tool behind `tool` (the ink layer only knows pens, erasers and the lasso).
    private(set) var editorTool: EditorTool = .pen
    private(set) var feel: InkFeel = .standard
    private(set) var readOnly = false
    var textColorHex = "#1C1C1E"
    var textSize: CGFloat = 22
    var tapeColorHex = "#F2B8C6" { didSet { tapePreview.strokeColor = UIColor(hex: tapeColorHex).cgColor } }
    /// Tape thickness in page units.
    var tapeWidth: CGFloat = 30

    var onPageChanged: ((Int, Int) -> Void)?
    var onUndoChanged: ((Bool, Bool) -> Void)?
    var onZoomChanged: ((Int) -> Void)?
    var onPencilDoubleTap: (() -> Void)?
    var onPencilSqueeze: ((CGPoint) -> Void)?
    var onDrawingStarted: (() -> Void)?
    var onMessage: ((String) -> Void)?

    private let palmBlocker = PalmGestureRecognizer()
    private lazy var undoTap = UITapGestureRecognizer(target: self, action: #selector(fingerUndo))
    private lazy var redoTap = UITapGestureRecognizer(target: self, action: #selector(fingerRedo))
    private lazy var splitTap = UITapGestureRecognizer(target: self, action: #selector(fiveFingerTap))
    var onFiveFingerTap: (() -> Void)?
    /// Pinch-zoom switched off from the zoom menu.
    var zoomLocked = false { didSet { updateFingerScrolling() } }
    private var pencilNearby = false
    private var hoverEndWork: DispatchWorkItem?
    private var toolInUse = false
    private var touchingObject = false

    let laser = LaserOverlay()
    private let tapePreview = CAShapeLayer()
    private lazy var laserPress = UILongPressGestureRecognizer(target: self, action: #selector(laserMoved(_:)))
    private lazy var tapePress = UILongPressGestureRecognizer(target: self, action: #selector(tapeMoved(_:)))
    private lazy var textTap = UITapGestureRecognizer(target: self, action: #selector(textTapped(_:)))
    private var tapePoints: [CGPoint] = []
    private var tapeLayer: ElementsLayer?

    init(store: LibraryStore, notebook: Notebook) {
        self.store = store
        self.notebook = notebook
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        view.addInteraction(pencil)

        // Pencil hover (iPad Pro / Air with Apple Pencil Pro or 2): while the pencil
        // is near the glass, a resting palm can't scroll the page.
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
        hover.delegate = self
        view.addGestureRecognizer(hover)

        for g in [laserPress, tapePress] {
            g.minimumPressDuration = 0
            g.allowableMovement = .greatestFiniteMagnitude
            g.delegate = self
            g.isEnabled = false
            view.addGestureRecognizer(g)
        }
        textTap.delegate = self
        textTap.isEnabled = false
        view.addGestureRecognizer(textTap)

        // Two-finger tap undoes, three-finger tap redoes (fingers only).
        for (g, n) in [(undoTap, 2), (redoTap, 3), (splitTap, 5)] {
            g.numberOfTouchesRequired = n
            g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            g.cancelsTouchesInView = false
            g.delegate = self
            view.addGestureRecognizer(g)
        }
        undoTap.require(toFail: redoTap)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(undoStateChanged), name: .NSUndoManagerDidCloseUndoGroup, object: undo)
        nc.addObserver(self, selector: #selector(undoStateChanged), name: .NSUndoManagerDidUndoChange, object: undo)
        nc.addObserver(self, selector: #selector(undoStateChanged), name: .NSUndoManagerDidRedoChange, object: undo)
        nc.addObserver(self, selector: #selector(appWillResign), name: UIApplication.willResignActiveNotification, object: nil)
    }

    /// Subclasses call this after adding their own views, so the laser trail is on top.
    func installOverlays() {
        laser.frame = view.bounds
        laser.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(laser)
        tapePreview.fillColor = nil
        tapePreview.strokeColor = UIColor(hex: tapeColorHex).cgColor
        tapePreview.lineCap = .butt
        tapePreview.lineJoin = .round
        laser.layer.addSublayer(tapePreview)
        installRuler()
        installSelectionMenu()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveAll()
    }

    // MARK: Overridden by subclasses

    /// The scroll view whose finger scrolling should be blocked while writing.
    var scrollingView: UIScrollView? { nil }
    func applyTool() {}
    func applyDrawingPolicy(fingerDraws: Bool) {}
    /// Turn the ink layers on or off for the current tool / read-only state.
    func applyCanvasEnabled(_ enabled: Bool) {}
    func saveAll() {}
    func resetZoom() {}
    /// The object layers (under the ink, over the ink) at a point in `view`.
    func objectLayers(at point: CGPoint) -> (under: ElementsLayer, over: ElementsLayer)? { nil }
    var allObjectLayers: [ElementsLayer] { [] }

    // MARK: Tools

    func setTool(_ newTool: InkTool) {
        // SwiftUI calls this on every redraw; handing the same tool to every page again is wasted work.
        guard newTool != tool else { return }
        tool = newTool
        applyTool()
    }

    func setRuler(_ on: Bool) {
        guard on != rulerOn else { return }
        rulerOn = on
        applyRuler()
    }

    func setInputMode(_ mode: DrawingInput) {
        guard mode != inputMode else { return }
        inputMode = mode
        applyInputMode()
    }

    func setMode(tool t: EditorTool, feel f: InkFeel, readOnly r: Bool) {
        feel = f
        guard t != editorTool || r != readOnly else { return }
        let leavingText = editorTool == .text && t != .text
        editorTool = t
        readOnly = r
        if leavingText { view.endEditing(true) }
        refreshMode()
    }

    func refreshMode() {
        let t = editorTool
        let canvasTool = t == .pen || t == .highlighter || t == .eraser || t == .lasso || t == .shapes
        applyCanvasEnabled(canvasTool && !readOnly)
        laserPress.isEnabled = t == .laser && !readOnly
        tapePress.isEnabled = t == .tape && !readOnly
        textTap.isEnabled = t == .text && !readOnly
        for l in allObjectLayers { l.editing = t == .text && !readOnly }
        updateTouchTypes()
        updateScrollTouches()
    }

    var fingerDraws: Bool {
        switch inputMode {
        case .anyInput: return true
        case .pencilOnly: return false
        case .auto: return !UIPencilInteraction.prefersPencilOnlyDrawing
        }
    }

    func applyInputMode() {
        let finger = fingerDraws
        applyDrawingPolicy(fingerDraws: finger)
        updateTouchTypes()
        guard let sv = scrollingView else { return }
        updateScrollTouches()
    }

    /// Normally the Pencil only writes and fingers scroll. In reading mode the Pencil scrolls too.
    func updateScrollTouches() {
        guard let sv = scrollingView else { return }
        // When the finger draws, scroll with two fingers instead.
        sv.panGestureRecognizer.minimumNumberOfTouches = (fingerDraws && !readOnly) ? 2 : 1
        var types = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                     NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        if readOnly { types.append(NSNumber(value: UITouch.TouchType.pencil.rawValue)) }
        sv.panGestureRecognizer.allowedTouchTypes = types
        updateFingerScrolling()
    }

    private func updateTouchTypes() {
        var types = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        if fingerDraws { types.append(NSNumber(value: UITouch.TouchType.direct.rawValue)) }
        laserPress.allowedTouchTypes = types
        tapePress.allowedTouchTypes = types
    }

    // MARK: Palm rejection

    /// Call once the scroll view exists.
    func installPalmRejection() {
        guard let sv = scrollingView else { return }
        palmBlocker.delegate = self
        palmBlocker.cancelsTouchesInView = false
        palmBlocker.delaysTouchesEnded = false
        sv.addGestureRecognizer(palmBlocker)
        // Only scrolling waits for the palm check. A thumb pressed flat in a pinch can look as
        // big as a palm, and making the pinch wait for it is what made zoom ignore you at times.
        sv.panGestureRecognizer.require(toFail: palmBlocker)
        // Pinch with fingers (or a trackpad) only, never the Pencil plus a resting hand.
        sv.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                                         NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        applyInputMode()
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if g === rulerPan || g === rulerTurn { return touchIsOnRuler(touch) }
        guard g === textTap || g === tapePress else { return true }
        // Taps on an object belong to the object (select, type, peek under tape).
        var v = touch.view
        while let cur = v {
            if cur is ElementView { return false }
            v = cur.superview
        }
        return true
    }

    @objc private func hovered(_ g: UIHoverGestureRecognizer) {
        // zOffset is only above zero for a hovering Apple Pencil, not a trackpad pointer.
        switch g.state {
        case .began, .changed:
            guard g.zOffset > 0 else { return }
            hoverEndWork?.cancel()
            if !pencilNearby {
                pencilNearby = true
                updateFingerScrolling()
            }
        default:
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pencilNearby = false
                self.updateFingerScrolling()
            }
            hoverEndWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    func toolUseBegan() {
        onDrawingStarted?()
        toolInUse = true
        updateFingerScrolling()
    }

    func toolUseEnded() {
        toolInUse = false
        updateFingerScrolling()
    }

    /// Dragging an object with a finger shouldn't scroll the page too.
    func objectTouch(_ active: Bool) {
        guard touchingObject != active else { return }
        touchingObject = active
        updateFingerScrolling()
    }

    func updateFingerScrolling() {
        guard let sv = scrollingView else { return }
        // A hovering or writing Pencil stops a resting palm from scrolling (not in reading mode).
        let block = ((toolInUse || pencilNearby) && !fingerDraws && !readOnly) || touchingObject
        sv.panGestureRecognizer.isEnabled = !block
        // Pinch stays available while the Pencil hovers: turning it off then made zoom feel unresponsive.
        // (Only off while the Pencil is actually drawing, so a palm plus a stray finger can't zoom mid-stroke.)
        sv.pinchGestureRecognizer?.isEnabled = !touchingObject && !zoomLocked && !(toolInUse && !fingerDraws)
    }

    // MARK: Ink: undo, saving, the lasso menu and the ruler

    /// Subclasses connect every ink view they make through this.
    func wireInk(_ ink: InkCanvasView) {
        ink.onBegan = { [weak self] in self?.toolUseBegan() }
        ink.onEnded = { [weak self] in self?.toolUseEnded() }
        ink.onCommit = { [weak self] canvas, before, after in
            guard let self else { return }
            let target = self.inkChanged(canvas, to: after)
            self.registerInkUndo(target, before: before, after: after)
        }
        ink.onObjectTouch = { [weak self] active in self?.objectTouch(active) }
        ink.onSelectionChanged = { [weak self] canvas in self?.selectionChanged(canvas) }
        ink.rulerSnap = { [weak self] canvas, p in self?.rulerProjection(canvas, start: p) }
        ink.tool = tool
        ink.fingerDraws = fingerDraws
    }

    /// The ink on `canvas` changed to `drawing`. Subclasses save it (and keep a zoom box and its
    /// page in step), and return the view that owns the ink, for undo.
    func inkChanged(_ canvas: InkCanvasView, to drawing: InkDrawing) -> InkCanvasView { canvas }

    private func registerInkUndo(_ canvas: InkCanvasView, before: InkDrawing, after: InkDrawing) {
        undo.registerUndo(withTarget: self) { target in
            target.restoreInk(canvas, to: before, redo: after)
        }
    }

    private func restoreInk(_ canvas: InkCanvasView, to d: InkDrawing, redo r: InkDrawing) {
        canvas.clearSelection()
        canvas.setDrawing(d)
        _ = inkChanged(canvas, to: d)
        undo.registerUndo(withTarget: self) { target in
            target.restoreInk(canvas, to: r, redo: d)
        }
    }

    // Lasso menu: colour, duplicate, delete.

    private let selectionMenu = SelectionMenuView()
    private weak var selectionCanvas: InkCanvasView?

    private func selectionChanged(_ canvas: InkCanvasView) {
        if canvas.hasSelection {
            if let other = selectionCanvas, other !== canvas { other.clearSelection() }
            selectionCanvas = canvas
        } else if selectionCanvas === canvas {
            selectionCanvas = nil
        }
        positionSelectionMenu()
    }

    /// Keeps the lasso menu just above the selection (call after scrolling or zooming).
    func positionSelectionMenu() {
        guard let c = selectionCanvas, let f = c.selectionFrame, c.window != nil else {
            selectionMenu.isHidden = true
            return
        }
        let r = c.convert(f, to: view)
        let size = selectionMenu.intrinsicContentSize
        var y = r.minY - size.height - 52
        if y < 64 { y = r.maxY + 16 }
        y = min(max(y, 64), view.bounds.height - size.height - 20)
        let x = min(max(r.midX - size.width / 2, 12), view.bounds.width - size.width - 12)
        selectionMenu.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        selectionMenu.isHidden = false
        view.bringSubviewToFront(selectionMenu)
    }

    private func installSelectionMenu() {
        selectionMenu.isHidden = true
        selectionMenu.onColor = { [weak self] hex in self?.selectionCanvas?.recolorSelection(hex) }
        selectionMenu.onDuplicate = { [weak self] in self?.selectionCanvas?.duplicateSelection() }
        selectionMenu.onDelete = { [weak self] in self?.selectionCanvas?.deleteSelection() }
        view.addSubview(selectionMenu)
    }

    // Ruler: drag it with one finger, turn it with two; lines started at its edge run along it.

    private let ruler = RulerView()
    private lazy var rulerPan = UIPanGestureRecognizer(target: self, action: #selector(rulerPanned(_:)))
    private lazy var rulerTurn = UIRotationGestureRecognizer(target: self, action: #selector(rulerTurned(_:)))
    private var rulerPlaced = false

    private func installRuler() {
        ruler.isHidden = true
        ruler.isUserInteractionEnabled = false
        view.insertSubview(ruler, belowSubview: laser)
        for g in [rulerPan, rulerTurn] as [UIGestureRecognizer] {
            g.delegate = self
            g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            view.addGestureRecognizer(g)
        }
    }

    func applyRuler() {
        if rulerOn && !rulerPlaced {
            rulerPlaced = true
            ruler.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
        UIView.animate(withDuration: 0.2) { self.ruler.alpha = self.rulerOn ? 1 : 0 } completion: { _ in
            self.ruler.isHidden = !self.rulerOn
        }
        if rulerOn { ruler.isHidden = false }
    }

    private func touchIsOnRuler(_ touch: UITouch) -> Bool {
        guard rulerOn, !ruler.isHidden else { return false }
        return ruler.bounds.insetBy(dx: -6, dy: -6).contains(touch.location(in: ruler))
    }

    @objc private func rulerPanned(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began: objectTouch(true)
        case .changed:
            let t = g.translation(in: view)
            ruler.center = CGPoint(x: ruler.center.x + t.x, y: ruler.center.y + t.y)
            g.setTranslation(.zero, in: view)
        default: objectTouch(false)
        }
    }

    @objc private func rulerTurned(_ g: UIRotationGestureRecognizer) {
        switch g.state {
        case .began: objectTouch(true)
        case .changed:
            ruler.angle += g.rotation
            g.rotation = 0
        default:
            // Settle on 0°, 45° or 90° when close.
            let step = CGFloat.pi / 4
            let nearest = (ruler.angle / step).rounded() * step
            if abs(ruler.angle - nearest) < 3 * .pi / 180 {
                UIView.animate(withDuration: 0.15) { self.ruler.angle = nearest }
            }
            objectTouch(false)
        }
    }

    /// A stroke starting within reach of the ruler's edge follows the edge exactly.
    private func rulerProjection(_ canvas: InkCanvasView, start: CGPoint) -> ((CGPoint) -> CGPoint)? {
        guard rulerOn, !ruler.isHidden else { return nil }
        let local = canvas.convert(start, to: ruler)
        let h = ruler.bounds.height
        let edge: CGFloat
        if abs(local.y) < 40 { edge = -2 } else if abs(local.y - h) < 40 { edge = h + 2 } else { return nil }
        guard local.x > -40, local.x < ruler.bounds.width + 40 else { return nil }
        let r = ruler
        return { [weak canvas] p in
            guard let canvas else { return p }
            var q = canvas.convert(p, to: r)
            q.y = edge
            return r.convert(q, to: canvas)
        }
    }

    // MARK: Laser pointer

    @objc private func laserMoved(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: view)
        switch g.state {
        case .began:
            onDrawingStarted?()
            laser.begin(at: p)
        case .changed: laser.move(to: p)
        default: laser.end()
        }
    }

    // MARK: Tape

    /// Tape follows your finger or Pencil freely, as a solid band `tapeWidth` page units wide.
    @objc private func tapeMoved(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: view)
        let scale = tapeLayer?.scale ?? 1
        switch g.state {
        case .began:
            onDrawingStarted?()
            tapeLayer = objectLayers(at: p)?.over
            tapePoints = [p]
            tapePreview.path = nil
            tapePreview.lineWidth = tapeWidth * (tapeLayer?.scale ?? 1)
        case .changed:
            // Skip tiny moves so the band stays smooth.
            if let last = tapePoints.last, hypot(p.x - last.x, p.y - last.y) < 3 { return }
            tapePoints.append(p)
            tapePreview.lineWidth = tapeWidth * scale
            tapePreview.path = tapeLength > 12 * scale ? Self.smoothPath(tapePoints) : nil
        default:
            tapePreview.path = nil
            defer { tapeLayer = nil; tapePoints = [] }
            guard g.state == .ended, let layer = tapeLayer, tapeLength > 12 * layer.scale else { return }
            if let last = tapePoints.last, last != p { tapePoints.append(p) }
            // Into page units, smoothed a little, then stored relative to the band's box.
            let units = Self.smoothed(tapePoints).map { layer.unitPoint(view.convert($0, to: layer)) }
            let half = tapeWidth / 2
            let xs = units.map(\.x), ys = units.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
            let w = maxX - minX, h = maxY - minY
            var flat: [CGFloat] = []
            for u in units {
                flat.append(w > 0.01 ? (u.x - minX) / w : 0.5)
                flat.append(h > 0.01 ? (u.y - minY) / h : 0.5)
            }
            var e = PageElement(kind: .tape, x: minX - half, y: minY - half, w: w + half * 2, h: h + half * 2,
                                colorHex: tapeColorHex)
            e.points = flat
            e.lineWidth = tapeWidth
            layer.model.add(e)
        }
    }

    private var tapeLength: CGFloat {
        zip(tapePoints, tapePoints.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Averages each point with its neighbours to take the shake out of a hand-drawn line.
    private static func smoothed(_ pts: [CGPoint]) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var out = [pts[0]]
        for i in 1..<(pts.count - 1) {
            let a = pts[i - 1], b = pts[i], c = pts[i + 1]
            out.append(CGPoint(x: (a.x + b.x * 2 + c.x) / 4, y: (a.y + b.y * 2 + c.y) / 4))
        }
        out.append(pts[pts.count - 1])
        return out
    }

    private static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let s = smoothed(pts)
        guard let first = s.first else { return path }
        path.move(to: first)
        for q in s.dropFirst() { path.addLine(to: q) }
        return path
    }

    // MARK: Text boxes

    @objc private func textTapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: view)
        // A tap away from the box being edited just finishes editing.
        if allObjectLayers.contains(where: { $0.selected != nil }) {
            view.endEditing(true)
            for l in allObjectLayers { l.select(nil) }
            return
        }
        guard let layers = objectLayers(at: p) else { return }
        let unit = layers.under.unitPoint(view.convert(p, to: layers.under))
        layers.under.addText(at: unit, color: textColorHex, size: textSize)
    }

    /// Places a new object in the middle of what's on screen and selects it.
    func placeObject(_ make: (CGPoint) -> PageElement) {
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY * 0.9)
        guard let layers = objectLayers(at: center) else { return }
        let unit = layers.under.unitPoint(view.convert(center, to: layers.under))
        let e = make(unit)
        let layer = e.kind.isOverInk ? layers.over : layers.under
        layer.model.add(e)
        if let v = layer.views[e.id] {
            layer.select(v)
            if e.kind == .sticky { v.beginTyping() }
        }
    }

    // MARK: Apple Pencil double-tap & squeeze

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        onPencilDoubleTap?()
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        onPencilDoubleTap?()
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        let point = squeeze.hoverPose?.location ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY * 0.9)
        let feedback = UICanvasFeedbackGenerator(view: view)
        feedback.alignmentOccurred(at: point)
        onPencilSqueeze?(point)
    }

    // MARK: Undo

    @objc func undoStateChanged() {
        onUndoChanged?(undo.canUndo, undo.canRedo)
    }

    func performUndo() { if undo.canUndo { undo.undo() } }
    func performRedo() { if undo.canRedo { undo.redo() } }

    @objc private func fiveFingerTap() { onFiveFingerTap?() }

    @objc private func fingerUndo() {
        guard !readOnly, undo.canUndo else { return }
        undo.undo()
        onMessage?("Undo")
    }

    @objc private func fingerRedo() {
        guard !readOnly, undo.canRedo else { return }
        undo.redo()
        onMessage?("Redo")
    }

    @objc private func appWillResign() { saveAll() }
}

/// The laser pointer's glowing trail; fades away shortly after the pencil lifts.
final class LaserOverlay: UIView {
    private let glow = CAShapeLayer()
    private let core = CAShapeLayer()
    private let path = UIBezierPath()
    private var fadeWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for l in [glow, core] {
            l.fillColor = nil
            l.lineCap = .round
            l.lineJoin = .round
            layer.addSublayer(l)
        }
        glow.strokeColor = UIColor(red: 1, green: 0.18, blue: 0.25, alpha: 0.45).cgColor
        glow.lineWidth = 13
        glow.shadowColor = UIColor.red.cgColor
        glow.shadowRadius = 8
        glow.shadowOpacity = 0.9
        glow.shadowOffset = .zero
        core.strokeColor = UIColor(red: 1, green: 0.86, blue: 0.86, alpha: 1).cgColor
        core.lineWidth = 3.5
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func begin(at p: CGPoint) {
        fadeWork?.cancel()
        layer.removeAllAnimations()
        alpha = 1
        path.move(to: p)
        path.addLine(to: p)
        update()
    }

    func move(to p: CGPoint) {
        path.addLine(to: p)
        update()
    }

    func end() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.45, animations: { self.alpha = 0 }) { done in
                guard done else { return }
                self.path.removeAllPoints()
                self.update()
                self.alpha = 1
            }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func update() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.path = path.cgPath
        core.path = path.cgPath
        CATransaction.commit()
    }
}

/// Recognises a resting palm (a very large touch) so the page doesn't scroll
/// under the hand while writing. Normal finger touches fail it immediately.
final class PalmGestureRecognizer: UIGestureRecognizer {
    static let palmRadius: CGFloat = 42

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touches.contains(where: Self.isPalm) {
            state = state == .possible ? .began : .changed
        } else if state == .possible {
            state = .failed
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(event)
    }

    private func finish(_ event: UIEvent) {
        let active = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? []
        if active.isEmpty {
            state = (state == .began || state == .changed) ? .ended : .failed
        }
    }

    static func isPalm(_ t: UITouch) -> Bool {
        t.type == .direct && t.majorRadius > palmRadius
    }
}
