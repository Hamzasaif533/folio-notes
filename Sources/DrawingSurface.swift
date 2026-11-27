import UIKit
import UIKit.UIGestureRecognizerSubclass
import PencilKit

/// Shared behaviour for the paged notebook and the infinite canvas:
/// Apple Pencil Pro double-tap and squeeze, palm rejection, undo, tool state,
/// the laser pointer, tape, text boxes and the pen-feel/shape post-processing.
class DrawingSurfaceController: UIViewController, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
    let store: LibraryStore
    var notebook: Notebook

    let undo = UndoManager()
    override var undoManager: UndoManager? { undo }

    var tool: PKTool = PKInkingTool(.pen, color: .black, width: 3)
    var inputMode: DrawingInput = .pencilOnly
    var rulerOn = false

    /// The editor tool behind `tool` (PencilKit doesn't know about shapes, text, laser or tape).
    private(set) var editorTool: EditorTool = .pen
    private(set) var feel: InkFeel = .standard
    private(set) var readOnly = false
    var textColorHex = "#1C1C1E"
    var textSize: CGFloat = 22

    var onPageChanged: ((Int, Int) -> Void)?
    var onUndoChanged: ((Bool, Bool) -> Void)?
    var onZoomChanged: ((Int) -> Void)?
    var onPencilDoubleTap: (() -> Void)?
    var onPencilSqueeze: ((CGPoint) -> Void)?
    var onDrawingStarted: (() -> Void)?
    var onMessage: ((String) -> Void)?

    private let palmBlocker = PalmGestureRecognizer()
    private var pencilNearby = false
    private var hoverEndWork: DispatchWorkItem?
    private var toolInUse = false
    private var touchingObject = false

    let laser = LaserOverlay()
    private let tapePreview = CAShapeLayer()
    private lazy var laserPress = UILongPressGestureRecognizer(target: self, action: #selector(laserMoved(_:)))
    private lazy var tapePress = UILongPressGestureRecognizer(target: self, action: #selector(tapeMoved(_:)))
    private lazy var textTap = UITapGestureRecognizer(target: self, action: #selector(textTapped(_:)))
    private var tapeStart: CGPoint = .zero
    private var tapeLayer: ElementsLayer?

    private var strokeCounts: [ObjectIdentifier: Int] = [:]
    private var reshaping = false

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
        tapePreview.fillColor = UIColor(hex: "#F2B8C6").withAlphaComponent(0.6).cgColor
        tapePreview.strokeColor = nil
        laser.layer.addSublayer(tapePreview)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveAll()
    }

    // MARK: Overridden by subclasses

    /// The scroll view whose finger scrolling should be blocked while writing.
    var scrollingView: UIScrollView? { nil }
    func applyTool() {}
    func applyRuler() {}
    func applyDrawingPolicy(fingerDraws: Bool) {}
    /// Turn the PencilKit canvases on or off for the current tool / read-only state.
    func applyCanvasEnabled(_ enabled: Bool) {}
    func saveAll() {}
    func resetZoom() {}
    /// The object layers (under the ink, over the ink) at a point in `view`.
    func objectLayers(at point: CGPoint) -> (under: ElementsLayer, over: ElementsLayer)? { nil }
    var allObjectLayers: [ElementsLayer] { [] }

    // MARK: Tools

    func setTool(_ newTool: PKTool) {
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
        laserPress.isEnabled = t == .laser
        tapePress.isEnabled = t == .tape && !readOnly
        textTap.isEnabled = t == .text && !readOnly
        for l in allObjectLayers { l.editing = t == .text && !readOnly }
        updateTouchTypes()
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
        // When the finger draws, scroll with two fingers instead.
        sv.panGestureRecognizer.minimumNumberOfTouches = finger ? 2 : 1
        // The Pencil only ever writes; only fingers (or a trackpad) scroll.
        sv.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
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
        sv.panGestureRecognizer.require(toFail: palmBlocker)
        sv.pinchGestureRecognizer?.require(toFail: palmBlocker)
        applyInputMode()
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
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
        let block = ((toolInUse || pencilNearby) && !fingerDraws) || touchingObject
        sv.panGestureRecognizer.isEnabled = !block
        sv.pinchGestureRecognizer?.isEnabled = !block
    }

    // MARK: Pen feel & shapes

    /// Subclasses call this from every drawing change. A brand-new pen stroke is
    /// reshaped (GoodNotes-style feel, or snapped to a shape with the Shapes tool).
    func strokeAdded(in canvas: PKCanvasView) {
        let key = ObjectIdentifier(canvas)
        let count = canvas.drawing.strokes.count
        let before = strokeCounts[key] ?? count
        strokeCounts[key] = count
        guard !reshaping, count == before + 1 else { return }
        guard editorTool == .shapes || (editorTool == .pen && !feel.isStandard) else { return }
        var drawing = canvas.drawing
        guard let last = drawing.strokes.last else { return }
        let replacement = editorTool == .shapes
            ? StrokeShaper.recognizeShape(last)
            : StrokeShaper.apply(feel, to: last)
        guard let new = replacement else { return }
        let original = drawing
        drawing.strokes[drawing.strokes.count - 1] = new
        replaceDrawing(canvas, with: drawing, undoTo: original)
    }

    /// Swaps the drawing and registers an undo step that swaps it back. It lands in
    /// the same undo group as PencilKit's own step, so one Undo removes the stroke.
    private func replaceDrawing(_ canvas: PKCanvasView, with d: PKDrawing, undoTo old: PKDrawing) {
        reshaping = true
        canvas.drawing = d
        reshaping = false
        strokeCounts[ObjectIdentifier(canvas)] = d.strokes.count
        undo.registerUndo(withTarget: self) { target in
            target.replaceDrawing(canvas, with: old, undoTo: d)
        }
    }

    func resetStrokeCount(_ canvas: PKCanvasView) {
        strokeCounts[ObjectIdentifier(canvas)] = canvas.drawing.strokes.count
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

    @objc private func tapeMoved(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: view)
        switch g.state {
        case .began:
            onDrawingStarted?()
            tapeStart = p
            tapeLayer = objectLayers(at: p)?.over
            tapePreview.path = nil
        case .changed:
            guard let r = tapeRect(from: tapeStart, to: p, scale: tapeLayer?.scale ?? 1) else { tapePreview.path = nil; return }
            tapePreview.path = UIBezierPath(roundedRect: r, cornerRadius: 2).cgPath
        default:
            tapePreview.path = nil
            guard g.state == .ended, let layer = tapeLayer,
                  let r = tapeRect(from: tapeStart, to: p, scale: layer.scale) else { return }
            let a = layer.unitPoint(view.convert(r.origin, to: layer))
            let b = layer.unitPoint(view.convert(CGPoint(x: r.maxX, y: r.maxY), to: layer))
            let e = PageElement(kind: .tape, x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y,
                                colorHex: ElementView.softColors[Int.random(in: 0..<ElementView.softColors.count)])
            layer.model.add(e)
            tapeLayer = nil
        }
    }

    /// A strip of tape along the drag (horizontal or vertical), 30 page units thick.
    private func tapeRect(from a: CGPoint, to b: CGPoint, scale: CGFloat) -> CGRect? {
        let dx = b.x - a.x, dy = b.y - a.y
        let thick = 30 * scale
        guard max(abs(dx), abs(dy)) > 12 * scale else { return nil }
        if abs(dx) >= abs(dy) {
            return CGRect(x: min(a.x, b.x), y: a.y - thick / 2, width: abs(dx), height: thick)
        }
        return CGRect(x: a.x - thick / 2, y: min(a.y, b.y), width: thick, height: abs(dy))
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
    static let palmRadius: CGFloat = 32

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
