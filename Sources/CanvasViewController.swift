import UIKit
import PencilKit

/// Forwards only the PencilKit events we need. Kept separate from the view
/// controllers so PencilKit keeps full control of its own scrolling and zooming.
final class CanvasEvents: NSObject, PKCanvasViewDelegate {
    let changed: (PKCanvasView) -> Void
    let began: () -> Void
    let ended: () -> Void
    var scrolled: ((UIScrollView) -> Void)?
    var zoomed: ((UIScrollView) -> Void)?

    init(changed: @escaping (PKCanvasView) -> Void, began: @escaping () -> Void, ended: @escaping () -> Void) {
        self.changed = changed
        self.began = began
        self.ended = ended
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { changed(canvasView) }
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { began() }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { ended() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { scrolled?(scrollView) }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { zoomed?(scrollView) }
}

/// Background for the infinite canvas: only the lines/dots that are on screen
/// are drawn, as vectors, so they stay sharp at every zoom level.
final class InfiniteBackgroundView: UIView {
    var template: PageTemplate = .grid { didSet { setNeedsLayout() } }
    var paper: PaperColor = .white { didSet { backgroundColor = paper.uiColor; setNeedsLayout() } }
    /// Visible part of the canvas, in canvas units.
    var visible: CGRect = .zero
    var zoom: CGFloat = 1

    private let lines = CAShapeLayer()
    private let dots = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        lines.fillColor = nil
        layer.addSublayer(lines)
        layer.addSublayer(dots)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(visible: CGRect, zoom: CGFloat) {
        self.visible = visible
        self.zoom = zoom
        redraw()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        redraw()
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lines.frame = bounds
        dots.frame = bounds
        let linePath = CGMutablePath()
        let dotPath = CGMutablePath()
        let z = max(zoom, 0.0001)
        func sx(_ x: CGFloat) -> CGFloat { (x - visible.minX) * z }
        func sy(_ y: CGFloat) -> CGFloat { (y - visible.minY) * z }

        // Spacing in canvas units; doubled when zoomed far out so it never gets too dense.
        var step: CGFloat
        switch template {
        case .blank: step = 0
        case .grid, .dotted: step = 25
        case .ruled, .cornell: step = 32
        case .narrowRuled: step = 24
        }
        if step > 0 {
            while step * z < 9 { step *= 2 }
            let x0 = (visible.minX / step).rounded(.down) * step
            let y0 = (visible.minY / step).rounded(.down) * step
            switch template {
            case .grid:
                var x = x0
                while x <= visible.maxX { linePath.move(to: CGPoint(x: sx(x), y: 0)); linePath.addLine(to: CGPoint(x: sx(x), y: bounds.height)); x += step }
                var y = y0
                while y <= visible.maxY { linePath.move(to: CGPoint(x: 0, y: sy(y))); linePath.addLine(to: CGPoint(x: bounds.width, y: sy(y))); y += step }
            case .dotted:
                let r = max(0.9, min(1.5 * z, 2.2))
                var y = y0
                while y <= visible.maxY {
                    var x = x0
                    while x <= visible.maxX {
                        dotPath.addEllipse(in: CGRect(x: sx(x) - r, y: sy(y) - r, width: r * 2, height: r * 2))
                        x += step
                    }
                    y += step
                }
            default:
                var y = y0
                while y <= visible.maxY { linePath.move(to: CGPoint(x: 0, y: sy(y))); linePath.addLine(to: CGPoint(x: bounds.width, y: sy(y))); y += step }
            }
        }
        lines.path = linePath
        lines.strokeColor = paper.lineColor.withAlphaComponent(template == .grid ? 0.75 : 1).cgColor
        lines.lineWidth = template == .grid ? 0.7 : 1
        dots.path = dotPath
        dots.fillColor = paper.lineColor.cgColor
        CATransaction.commit()
    }
}

/// An endless whiteboard (like GoodNotes' whiteboard): one PencilKit canvas
/// that scrolls and zooms in every direction. PencilKit only renders what is
/// on screen, so the canvas can be huge without using much memory.
final class CanvasViewController: DrawingSurfaceController {
    private let canvas = PKCanvasView()
    private let background = InfiniteBackgroundView()
    private var extent = CGSize(width: 20000, height: 20000)
    private var didPlace = false
    private var saveTask: Task<Void, Never>?
    private var isDirty = false
    private var pageId: UUID { notebook.pages.first ?? notebook.id }

    private lazy var events: CanvasEvents = {
        let e = CanvasEvents(changed: { [weak self] _ in self?.drawingChanged() },
                             began: { [weak self] in self?.toolUseBegan() },
                             ended: { [weak self] in self?.toolUseEnded() })
        e.scrolled = { [weak self] _ in self?.viewportChanged() }
        e.zoomed = { [weak self] _ in self?.viewportChanged() }
        return e
    }()

    override var scrollingView: UIScrollView? { canvas }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = notebook.paper.uiColor
        background.frame = view.bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        background.template = notebook.template
        background.paper = notebook.paper
        view.addSubview(background)

        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.bouncesZoom = true
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = events
        let drawing = store.loadDrawing(notebookId: notebook.id, pageId: pageId)
        let b = drawing.bounds
        if !b.isNull && !b.isEmpty {
            extent = CGSize(width: max(extent.width, b.maxX + 6000), height: max(extent.height, b.maxY + 6000))
        }
        canvas.drawing = drawing
        canvas.tool = tool
        canvas.isRulerActive = rulerOn
        view.addSubview(canvas)
        installPalmRejection()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didPlace, view.bounds.width > 0 else { return }
        didPlace = true
        canvas.zoomScale = 1
        canvas.contentSize = CGSize(width: extent.width * canvas.zoomScale, height: extent.height * canvas.zoomScale)
        // Start where the writing is, or in the middle of the board.
        let b = canvas.drawing.bounds
        let focus: CGPoint
        if !b.isNull && !b.isEmpty {
            focus = CGPoint(x: b.midX, y: b.minY + min(b.height, view.bounds.height) / 2 - 60)
        } else {
            focus = CGPoint(x: extent.width / 2, y: extent.height / 2)
        }
        canvas.contentOffset = CGPoint(x: focus.x - view.bounds.width / 2, y: focus.y - view.bounds.height / 2)
        viewportChanged()
        onPageChanged?(0, 1)
    }

    private func viewportChanged() {
        let z = canvas.zoomScale
        let o = canvas.contentOffset
        background.update(visible: CGRect(x: o.x / z, y: o.y / z,
                                          width: view.bounds.width / z, height: view.bounds.height / z),
                          zoom: z)
        onZoomChanged?(Int((z * 100).rounded()))
        if !canvas.isZooming {
            let wanted = CGSize(width: extent.width * z, height: extent.height * z)
            if abs(canvas.contentSize.width - wanted.width) > 1 || abs(canvas.contentSize.height - wanted.height) > 1 {
                canvas.contentSize = wanted
            }
        }
        growIfNeeded()
    }

    /// Keeps adding room to the right and bottom as you move towards the edge.
    private func growIfNeeded() {
        let z = canvas.zoomScale
        let o = canvas.contentOffset
        let margin: CGFloat = 3000
        var grew = false
        if (o.x + view.bounds.width) / z > extent.width - margin { extent.width += 8000; grew = true }
        if (o.y + view.bounds.height) / z > extent.height - margin { extent.height += 8000; grew = true }
        if grew { canvas.contentSize = CGSize(width: extent.width * z, height: extent.height * z) }
    }

    override func resetZoom() {
        let center = CGPoint(x: (canvas.contentOffset.x + view.bounds.width / 2) / canvas.zoomScale,
                             y: (canvas.contentOffset.y + view.bounds.height / 2) / canvas.zoomScale)
        UIView.animate(withDuration: 0.3) {
            self.canvas.zoomScale = 1
            self.canvas.contentOffset = CGPoint(x: center.x - self.view.bounds.width / 2,
                                                y: center.y - self.view.bounds.height / 2)
        }
    }

    // MARK: Tools

    override func applyTool() { canvas.tool = tool }
    override func applyRuler() { canvas.isRulerActive = rulerOn }
    override func applyDrawingPolicy(fingerDraws: Bool) {
        canvas.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
    }

    // MARK: Saving

    private func drawingChanged() {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveAll()
        }
    }

    override func saveAll() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty else { return }
        store.saveDrawing(canvas.drawing, notebookId: notebook.id, pageId: pageId)
        store.touch(notebook.id)
        isDirty = false
    }

    func applyPaper(template: PageTemplate, paper: PaperColor) {
        notebook.template = template
        notebook.paper = paper
        if var fresh = store.notebook(notebook.id) {
            fresh.template = template
            fresh.paper = paper
            store.updateNotebook(fresh)
        }
        view.backgroundColor = paper.uiColor
        background.template = template
        background.paper = paper
    }

    func clearAll() {
        canvas.drawing = PKDrawing()
        isDirty = true
        saveAll()
    }

    /// The written area (plus a margin) for PDF export.
    func drawingForExport() -> (PKDrawing, CGRect) {
        saveAll()
        let b = canvas.drawing.bounds
        let rect = (b.isNull || b.isEmpty) ? CGRect(x: 0, y: 0, width: 800, height: 1131) : b.insetBy(dx: -40, dy: -40)
        return (canvas.drawing, rect)
    }
}
