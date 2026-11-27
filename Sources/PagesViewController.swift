import UIKit
import PencilKit

/// One page: paper colour + template lines (vector layers) + a live PencilKit canvas.
final class PageView: UIView {
    let pageId: UUID
    let canvas = PKCanvasView()
    private var templateLayers: [CAShapeLayer] = []
    private(set) var zoom: CGFloat = 1

    var template: PageTemplate { didSet { rebuildTemplate() } }
    var paper: PaperColor { didSet { rebuildTemplate() } }

    init(pageId: UUID, template: PageTemplate, paper: PaperColor, drawing: PKDrawing) {
        self.pageId = pageId
        self.template = template
        self.paper = paper
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.13
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.bouncesZoom = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.minimumZoomScale = 0.05
        canvas.maximumZoomScale = 20
        // Keep ink colours exactly as chosen, even when the iPad is in dark mode.
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawing = drawing
        addSubview(canvas)
        rebuildTemplate()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Lays the page out at a real on-screen size so PencilKit and the template
    /// render natively at that size (no stretched bitmaps, so nothing goes blurry).
    func apply(zoom z: CGFloat) {
        zoom = z
        let size = CGSize(width: TemplateRenderer.pageSize.width * z,
                          height: TemplateRenderer.pageSize.height * z)
        canvas.frame = CGRect(origin: .zero, size: size)
        canvas.zoomScale = z
        canvas.contentSize = size
        canvas.contentOffset = .zero
        layer.shadowPath = UIBezierPath(rect: CGRect(origin: .zero, size: size)).cgPath
        rebuildTemplate()
    }

    private func rebuildTemplate() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundColor = paper.uiColor
        templateLayers.forEach { $0.removeFromSuperlayer() }
        let scale = window?.screen.scale ?? UIScreen.main.scale
        templateLayers = TemplateRenderer.layers(template: template, paper: paper, scale: zoom).map { l in
            let s = CAShapeLayer()
            s.frame = CGRect(x: 0, y: 0,
                             width: TemplateRenderer.pageSize.width * zoom,
                             height: TemplateRenderer.pageSize.height * zoom)
            s.contentsScale = scale
            s.path = l.path
            if l.filled {
                s.fillColor = l.color.cgColor
                s.strokeColor = nil
            } else {
                s.fillColor = nil
                s.strokeColor = l.color.cgColor
                s.lineWidth = l.lineWidth
            }
            layer.insertSublayer(s, below: canvas.layer)
            return s
        }
        CATransaction.commit()
    }
}

/// The scrolling stack of pages inside a notebook.
final class PagesViewController: UIViewController, UIScrollViewDelegate, PKCanvasViewDelegate {
    private let store: LibraryStore
    private(set) var notebook: Notebook

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private(set) var pageViews: [PageView] = []

    private var docZoom: CGFloat = 1
    private var fitZoom: CGFloat = 1
    private var lastWidth: CGFloat = 0
    private var isBaking = false
    private(set) var currentPage = 0

    private let undo = UndoManager()
    override var undoManager: UndoManager? { undo }

    private var saveTasks: [UUID: Task<Void, Never>] = [:]
    private var dirty: Set<UUID> = []

    private var tool: PKTool = PKInkingTool(.pen, color: .black, width: 3)
    private var inputMode: DrawingInput = .auto

    var onPageChanged: ((Int, Int) -> Void)?
    var onUndoChanged: ((Bool, Bool) -> Void)?

    /// Pages fill the screen width edge to edge, with a small gap between them.
    static let marginUnits: CGFloat = 0
    static let gapUnits: CGFloat = 14
    private var rulerOn = false
    private var minZoom: CGFloat { fitZoom * 0.5 }
    private var maxZoom: CGFloat { fitZoom * 4 }

    init(store: LibraryStore, notebook: Notebook) {
        self.store = store
        self.notebook = notebook
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.deskBackground

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        for pid in notebook.pages {
            pageViews.append(makePage(pid))
        }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(undoStateChanged), name: .NSUndoManagerDidCloseUndoGroup, object: undo)
        nc.addObserver(self, selector: #selector(undoStateChanged), name: .NSUndoManagerDidUndoChange, object: undo)
        nc.addObserver(self, selector: #selector(undoStateChanged), name: .NSUndoManagerDidRedoChange, object: undo)
        nc.addObserver(self, selector: #selector(appWillResign), name: UIApplication.willResignActiveNotification, object: nil)
        applyInputMode()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveAll()
    }

    private func makePage(_ id: UUID) -> PageView {
        let pv = PageView(pageId: id, template: notebook.template, paper: notebook.paper,
                          drawing: store.loadDrawing(notebookId: notebook.id, pageId: id))
        pv.canvas.delegate = self
        pv.canvas.tool = tool
        pv.canvas.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
        pv.canvas.isRulerActive = rulerOn
        contentView.addSubview(pv)
        return pv
    }

    // MARK: Layout & zoom

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        guard w > 0, abs(w - lastWidth) > 0.5, !isBaking else { return }
        let wasFit = lastWidth == 0 || abs(docZoom - fitZoom) < 0.001
        let anchor = currentPage
        lastWidth = w
        fitZoom = w / (TemplateRenderer.pageSize.width + 2 * Self.marginUnits)
        docZoom = wasFit ? fitZoom : min(max(docZoom, minZoom), maxZoom)
        isBaking = true
        scrollView.zoomScale = 1
        isBaking = false
        layoutPages()
        scrollTo(page: anchor, animated: false)
        reportPage(force: true)
    }

    private func layoutPages() {
        let z = docZoom
        let ps = TemplateRenderer.pageSize
        let m = Self.marginUnits * z
        let g = Self.gapUnits * z
        let pw = ps.width * z
        let ph = ps.height * z
        let size = CGSize(width: pw + 2 * m, height: max(ph, CGFloat(pageViews.count) * (ph + g) - g))

        contentView.transform = .identity
        contentView.frame = CGRect(origin: .zero, size: size)
        for (i, pv) in pageViews.enumerated() {
            pv.frame = CGRect(x: m, y: CGFloat(i) * (ph + g), width: pw, height: ph)
            pv.apply(zoom: z)
        }
        scrollView.contentSize = size
        scrollView.minimumZoomScale = minZoom / z
        scrollView.maximumZoomScale = maxZoom / z
        updateInsets()
    }

    private func updateInsets() {
        let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let bottom = view.safeAreaInsets.bottom + 60
        scrollView.contentInset = UIEdgeInsets(top: 0, left: horizontal, bottom: bottom, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateInsets()
    }

    func scrollViewDidEndZooming(_ sv: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        guard !isBaking, abs(scale - 1) > 0.001 else { return }
        isBaking = true
        let offset = sv.contentOffset
        var newZoom = min(max(docZoom * scale, minZoom), maxZoom)
        if abs(newZoom - fitZoom) / fitZoom < 0.06 { newZoom = fitZoom }
        let ratio = newZoom / (docZoom * scale)
        sv.zoomScale = 1
        docZoom = newZoom
        layoutPages()
        sv.contentOffset = clamped(CGPoint(x: offset.x * ratio, y: offset.y * ratio))
        isBaking = false
        reportPage(force: true)
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        let maxX = max(-inset.left, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
        let maxY = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        return CGPoint(x: min(max(p.x, -inset.left), maxX), y: min(max(p.y, -inset.top), maxY))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isBaking else { return }
        reportPage(force: false)
    }

    private func reportPage(force: Bool) {
        guard !pageViews.isEmpty else { return }
        let z = docZoom * scrollView.zoomScale
        let unitH = TemplateRenderer.pageSize.height + Self.gapUnits
        let centerY = (scrollView.contentOffset.y + scrollView.bounds.height / 2) / z
        let idx = min(max(Int(centerY / unitH), 0), pageViews.count - 1)
        if force || idx != currentPage {
            currentPage = idx
            onPageChanged?(idx, pageViews.count)
        }
    }

    func scrollTo(page: Int, animated: Bool) {
        guard pageViews.indices.contains(page) else { return }
        let y = CGFloat(page) * (TemplateRenderer.pageSize.height + Self.gapUnits) * docZoom
        scrollView.setContentOffset(clamped(CGPoint(x: scrollView.contentOffset.x, y: y)), animated: animated)
    }

    // MARK: Tools

    func setTool(_ newTool: PKTool) {
        tool = newTool
        for pv in pageViews { pv.canvas.tool = newTool }
    }

    func setRuler(_ on: Bool) {
        guard on != rulerOn else { return }
        rulerOn = on
        for pv in pageViews { pv.canvas.isRulerActive = on }
    }

    func setInputMode(_ mode: DrawingInput) {
        guard mode != inputMode else { return }
        inputMode = mode
        applyInputMode()
    }

    private var fingerDraws: Bool {
        switch inputMode {
        case .anyInput: return true
        case .pencilOnly: return false
        case .auto: return !UIPencilInteraction.prefersPencilOnlyDrawing
        }
    }

    private func applyInputMode() {
        let finger = fingerDraws
        for pv in pageViews { pv.canvas.drawingPolicy = finger ? .anyInput : .pencilOnly }
        // When the finger draws, scroll with two fingers instead.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = finger ? 2 : 1
    }

    // MARK: Undo

    @objc private func undoStateChanged() {
        onUndoChanged?(undo.canUndo, undo.canRedo)
    }

    func performUndo() { if undo.canUndo { undo.undo() } }
    func performRedo() { if undo.canRedo { undo.redo() } }

    // MARK: Saving

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let pv = pageViews.first(where: { $0.canvas === canvasView }) else { return }
        dirty.insert(pv.pageId)
        saveTasks[pv.pageId]?.cancel()
        let pid = pv.pageId
        saveTasks[pid] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            self.save(pageId: pid)
        }
    }

    private func save(pageId: UUID) {
        guard dirty.contains(pageId), let pv = pageViews.first(where: { $0.pageId == pageId }) else { return }
        store.saveDrawing(pv.canvas.drawing, notebookId: notebook.id, pageId: pageId)
        dirty.remove(pageId)
        saveTasks[pageId] = nil
        store.touch(notebook.id)
    }

    func saveAll() {
        for (_, t) in saveTasks { t.cancel() }
        saveTasks.removeAll()
        for pid in dirty {
            if let pv = pageViews.first(where: { $0.pageId == pid }) {
                store.saveDrawing(pv.canvas.drawing, notebookId: notebook.id, pageId: pid)
            }
        }
        if !dirty.isEmpty { store.touch(notebook.id) }
        dirty.removeAll()
    }

    @objc private func appWillResign() { saveAll() }

    // MARK: Pages

    func addPage() {
        saveAll()
        let at = currentPage + 1
        guard let pid = store.insertPage(notebookId: notebook.id, at: at) else { return }
        if let fresh = store.notebook(notebook.id) { notebook = fresh }
        let pv = makePage(pid)
        pageViews.insert(pv, at: min(at, pageViews.count))
        layoutPages()
        scrollTo(page: at, animated: true)
        reportPage(force: true)
    }

    func deleteCurrentPage() {
        let i = currentPage
        guard pageViews.indices.contains(i) else { return }
        if pageViews.count == 1 {
            // Last page: just clear it.
            pageViews[0].canvas.drawing = PKDrawing()
            dirty.insert(pageViews[0].pageId)
            saveAll()
            return
        }
        let pv = pageViews.remove(at: i)
        saveTasks[pv.pageId]?.cancel()
        dirty.remove(pv.pageId)
        pv.removeFromSuperview()
        store.deletePage(notebookId: notebook.id, pageId: pv.pageId)
        if let fresh = store.notebook(notebook.id) { notebook = fresh }
        undo.removeAllActions()
        onUndoChanged?(false, false)
        layoutPages()
        currentPage = min(i, pageViews.count - 1)
        scrollTo(page: currentPage, animated: false)
        reportPage(force: true)
    }

    func jump(to page: Int) {
        scrollTo(page: page, animated: false)
        reportPage(force: true)
    }

    func applyPaper(template: PageTemplate, paper: PaperColor) {
        notebook.template = template
        notebook.paper = paper
        if var fresh = store.notebook(notebook.id) {
            fresh.template = template
            fresh.paper = paper
            store.updateNotebook(fresh)
        }
        for pv in pageViews {
            pv.template = template
            pv.paper = paper
        }
    }

    func drawingsForExport() -> [PKDrawing] {
        saveAll()
        return pageViews.map { $0.canvas.drawing }
    }
}
