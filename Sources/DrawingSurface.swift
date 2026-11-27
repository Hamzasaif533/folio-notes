import UIKit
import UIKit.UIGestureRecognizerSubclass
import PencilKit

/// Shared behaviour for the paged notebook and the infinite canvas:
/// Apple Pencil Pro double-tap and squeeze, palm rejection, undo and tool state.
class DrawingSurfaceController: UIViewController, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
    let store: LibraryStore
    var notebook: Notebook

    let undo = UndoManager()
    override var undoManager: UndoManager? { undo }

    var tool: PKTool = PKInkingTool(.pen, color: .black, width: 3)
    var inputMode: DrawingInput = .pencilOnly
    var rulerOn = false

    var onPageChanged: ((Int, Int) -> Void)?
    var onUndoChanged: ((Bool, Bool) -> Void)?
    var onZoomChanged: ((Int) -> Void)?
    var onPencilDoubleTap: (() -> Void)?
    var onPencilSqueeze: ((CGPoint) -> Void)?
    var onDrawingStarted: (() -> Void)?

    private let palmBlocker = PalmGestureRecognizer()
    private var pencilNearby = false
    private var hoverEndWork: DispatchWorkItem?
    private var toolInUse = false

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

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(undoStateChanged), name: .NSUndoManagerDidCloseUndoGroup, object: undo)
        nc.addObserver(self, selector: #selector(undoStateChanged), name: .NSUndoManagerDidUndoChange, object: undo)
        nc.addObserver(self, selector: #selector(undoStateChanged), name: .NSUndoManagerDidRedoChange, object: undo)
        nc.addObserver(self, selector: #selector(appWillResign), name: UIApplication.willResignActiveNotification, object: nil)
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
    func saveAll() {}
    func resetZoom() {}

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

    private func updateFingerScrolling() {
        guard let sv = scrollingView else { return }
        let block = (toolInUse || pencilNearby) && !fingerDraws
        sv.panGestureRecognizer.isEnabled = !block
        sv.pinchGestureRecognizer?.isEnabled = !block
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
