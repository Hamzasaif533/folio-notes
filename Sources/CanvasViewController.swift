import UIKit

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

/// An endless whiteboard (like GoodNotes' whiteboard): one sheet of Folio ink that scrolls
/// and zooms in every direction. The ink is drawn in tiles, only where you look, so the
/// board can be huge without using much memory.
final class CanvasViewController: DrawingSurfaceController, UIScrollViewDelegate {
    private let scroller = UIScrollView()
    private var extent = CGSize(width: 20000, height: 20000)
    private lazy var ink = InkCanvasView(size: extent)
    private let background = InfiniteBackgroundView()
    private var didPlace = false
    private var saveTask: Task<Void, Never>?
    private var isDirty = false
    private var pageId: UUID { notebook.pages.first ?? notebook.id }
    private lazy var model = ElementModel(items: [])
    private lazy var underLayer = ElementsLayer(model: model, overInk: false)
    private lazy var overLayer = ElementsLayer(model: model, overInk: true)

    override var scrollingView: UIScrollView? { scroller }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = notebook.paper.uiColor
        background.frame = view.bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        background.template = notebook.template
        background.paper = notebook.paper
        view.addSubview(background)

        scroller.frame = view.bounds
        scroller.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroller.backgroundColor = .clear
        scroller.contentInsetAdjustmentBehavior = .never
        scroller.showsVerticalScrollIndicator = false
        scroller.showsHorizontalScrollIndicator = false
        scroller.delaysContentTouches = false
        scroller.bouncesZoom = true
        scroller.minimumZoomScale = 0.2
        scroller.maximumZoomScale = 6
        scroller.delegate = self
        let drawing = store.loadDrawing(notebookId: notebook.id, pageId: pageId)
        let b = drawing.bounds
        if !b.isNull && !b.isEmpty {
            extent = CGSize(width: max(extent.width, b.maxX + 6000), height: max(extent.height, b.maxY + 6000))
        }
        ink.setSize(extent)
        ink.setDrawing(drawing)
        wireInk(ink)
        scroller.addSubview(ink)
        scroller.contentSize = extent
        view.addSubview(scroller)

        // Objects float above the board (photos, text, stickies, tape).
        let nbId = notebook.id
        let pid = pageId
        model.items = store.loadElements(notebookId: nbId, pageId: pid)
        let lib = self.store
        model.imageLoader = { [weak lib] name in lib?.loadImageAsset(name, notebookId: nbId) }
        model.onSave = { [weak self] items in
            self?.store.saveElements(items, notebookId: nbId, pageId: pid)
            self?.store.touch(nbId)
        }
        for l in [underLayer, overLayer] {
            l.frame = view.bounds
            l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            l.onTouchingObject = { [weak self] active in self?.objectTouch(active) }
            view.addSubview(l)
        }
        model.reloadLayers()
        installPalmRejection()
        installOverlays()
        refreshMode()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didPlace, view.bounds.width > 0 else { return }
        didPlace = true
        scroller.zoomScale = 1
        placeInk()
        // Start where the writing is, or in the middle of the board.
        let b = ink.drawing.bounds
        let focus: CGPoint
        if !b.isNull && !b.isEmpty {
            focus = CGPoint(x: b.midX, y: b.minY + min(b.height, view.bounds.height) / 2 - 60)
        } else {
            focus = CGPoint(x: extent.width / 2, y: extent.height / 2)
        }
        scroller.contentOffset = CGPoint(x: focus.x - view.bounds.width / 2, y: focus.y - view.bounds.height / 2)
        viewportChanged()
        onPageChanged?(0, 1)
    }

    /// Keeps the ink's top-left corner at the scroll view's origin at the current zoom.
    private func placeInk() {
        let z = scroller.zoomScale
        ink.setSize(extent)
        ink.transform = CGAffineTransform(scaleX: z, y: z)
        ink.center = CGPoint(x: extent.width * z / 2, y: extent.height * z / 2)
        scroller.contentSize = CGSize(width: extent.width * z, height: extent.height * z)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { ink }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { viewportChanged() }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { viewportChanged() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        ink.zoomChanged()
        positionSelectionMenu()
    }

    private func viewportChanged() {
        let z = scroller.zoomScale
        let o = scroller.contentOffset
        background.update(visible: CGRect(x: o.x / z, y: o.y / z,
                                          width: view.bounds.width / z, height: view.bounds.height / z),
                          zoom: z)
        onZoomChanged?(Int((z * 100).rounded()))
        for l in [underLayer, overLayer] {
            l.scale = z
            l.origin = CGPoint(x: o.x / z, y: o.y / z)
            l.relayout()
        }
        if !scroller.isZooming { growIfNeeded() }
        positionSelectionMenu()
    }

    /// Keeps adding room to the right and bottom as you move towards the edge.
    private func growIfNeeded() {
        let z = scroller.zoomScale
        let o = scroller.contentOffset
        let margin: CGFloat = 3000
        var grew = false
        if (o.x + view.bounds.width) / z > extent.width - margin { extent.width += 8000; grew = true }
        if (o.y + view.bounds.height) / z > extent.height - margin { extent.height += 8000; grew = true }
        if grew { placeInk() }
    }

    override func resetZoom() {
        let center = CGPoint(x: (scroller.contentOffset.x + view.bounds.width / 2) / scroller.zoomScale,
                             y: (scroller.contentOffset.y + view.bounds.height / 2) / scroller.zoomScale)
        UIView.animate(withDuration: 0.3) {
            self.scroller.zoomScale = 1
            self.scroller.contentOffset = CGPoint(x: center.x - self.view.bounds.width / 2,
                                                  y: center.y - self.view.bounds.height / 2)
        } completion: { _ in
            self.ink.zoomChanged()
            self.positionSelectionMenu()
        }
    }

    // MARK: Tools

    override func applyTool() { ink.tool = tool }
    override func applyDrawingPolicy(fingerDraws: Bool) { ink.fingerDraws = fingerDraws }

    override func applyCanvasEnabled(_ enabled: Bool) {
        // The board still scrolls and zooms; it just stops taking ink.
        ink.isUserInteractionEnabled = enabled
        if !enabled { ink.clearSelection() }
    }

    override func objectLayers(at point: CGPoint) -> (under: ElementsLayer, over: ElementsLayer)? {
        (underLayer, overLayer)
    }

    override var allObjectLayers: [ElementsLayer] { [underLayer, overLayer] }

    // MARK: Saving

    override func inkChanged(_ canvas: InkCanvasView, to drawing: InkDrawing) -> InkCanvasView {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveAll()
        }
        return canvas
    }

    override func saveAll() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty else { return }
        store.saveDrawing(ink.drawing, notebookId: notebook.id, pageId: pageId)
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
        ink.clearSelection()
        ink.setDrawing(InkDrawing())
        undo.removeAllActions()
        onUndoChanged?(false, false)
        model.items = []
        model.save()
        model.reloadLayers()
        isDirty = true
        saveAll()
    }

    /// The written area (ink and objects, plus a margin) for PDF export.
    func drawingForExport() -> (InkDrawing, [PageElement], CGRect) {
        saveAll()
        var b = ink.drawing.bounds
        for e in model.items { b = b.isNull ? e.frame : b.union(e.frame) }
        let rect = (b.isNull || b.isEmpty) ? CGRect(x: 0, y: 0, width: 800, height: 1131) : b.insetBy(dx: -40, dy: -40)
        return (ink.drawing, model.items, rect)
    }

    var imageLoader: (String) -> UIImage? {
        let nbId = notebook.id
        let store = self.store
        return { name in store.loadImageAsset(name, notebookId: nbId) }
    }
}
