import UIKit
import PencilKit

/// One page: paper colour + template lines (vector layers) or an imported
/// background, objects under the ink, a live PencilKit canvas, and tape on top.
final class PageView: UIView {
    let pageId: UUID
    let canvas = PKCanvasView()
    let backgroundView = UIImageView()
    let model: ElementModel
    let under: ElementsLayer
    let over: ElementsLayer
    private var templateLayers: [CAShapeLayer] = []
    private(set) var zoom: CGFloat = 1

    var template: PageTemplate { didSet { rebuildTemplate() } }
    var paper: PaperColor { didSet { rebuildTemplate() } }
    var background: UIImage? {
        didSet {
            backgroundView.image = background
            backgroundView.isHidden = background == nil
            rebuildTemplate()
        }
    }

    init(pageId: UUID, template: PageTemplate, paper: PaperColor, drawing: PKDrawing,
         elements: [PageElement], background: UIImage?) {
        self.pageId = pageId
        self.template = template
        self.paper = paper
        self.background = background
        model = ElementModel(items: elements)
        under = ElementsLayer(model: model, overInk: false)
        over = ElementsLayer(model: model, overInk: true)
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.13
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)

        backgroundView.contentMode = .scaleAspectFit
        backgroundView.image = background
        backgroundView.isHidden = background == nil
        addSubview(backgroundView)
        addSubview(under)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.bouncesZoom = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        // The page itself never pans or pinches on its own: the notebook's scroll
        // view does that. (A pinch landing on the page used to zoom only the ink,
        // which made the writing slide away from the lines.)
        canvas.panGestureRecognizer.isEnabled = false
        canvas.pinchGestureRecognizer?.isEnabled = false
        // Keep ink colours exactly as chosen, even when the iPad is in dark mode.
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawing = drawing
        addSubview(canvas)
        addSubview(over)
        rebuildTemplate()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Lays the page out at a real on-screen size so PencilKit and the template
    /// render natively at that size (no stretched bitmaps, so nothing goes blurry).
    func apply(zoom z: CGFloat) {
        zoom = z
        let size = CGSize(width: TemplateRenderer.pageSize.width * z,
                          height: TemplateRenderer.pageSize.height * z)
        let rect = CGRect(origin: .zero, size: size)
        canvas.frame = rect
        // Lock the page canvas to exactly this zoom. With the minimum equal to
        // the maximum, PencilKit can't pinch-zoom the ink on its own (that was
        // what made the writing grow while the lines stayed put); the pinch
        // goes to the notebook instead, which scales paper and ink together.
        canvas.minimumZoomScale = z
        canvas.maximumZoomScale = z
        canvas.zoomScale = z
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.panGestureRecognizer.isEnabled = false
        canvas.contentSize = size
        canvas.contentOffset = .zero
        backgroundView.frame = rect
        for l in [under, over] {
            l.frame = rect
            l.scale = z
            l.origin = .zero
            l.relayout()
        }
        layer.shadowPath = UIBezierPath(rect: rect).cgPath
        rebuildTemplate()
    }

    private func rebuildTemplate() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundColor = paper.uiColor
        templateLayers.forEach { $0.removeFromSuperlayer() }
        templateLayers = []
        // Imported pages (photos, scans, PDFs) show the page itself instead of lines.
        if background == nil {
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
                layer.insertSublayer(s, at: 0)
                return s
            }
        }
        CATransaction.commit()
    }

    var content: PageContent {
        PageContent(drawing: canvas.drawing, elements: model.items, background: background)
    }
}

/// The scrolling stack of pages inside a notebook (down, or across in horizontal view).
final class PagesViewController: DrawingSurfaceController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private lazy var canvasDelegate = CanvasEvents(
        changed: { [weak self] c in self?.drawingChanged(c) },
        began: { [weak self] in self?.toolUseBegan() },
        ended: { [weak self] in self?.toolUseEnded() })
    private let contentView = UIView()
    private(set) var pageViews: [PageView] = []

    private var docZoom: CGFloat = 1
    private var fitZoom: CGFloat = 1
    private var lastSize: CGSize = .zero
    private var isBaking = false
    private(set) var currentPage = 0
    private(set) var horizontal = false

    private var saveTasks: [UUID: Task<Void, Never>] = [:]
    private var dirty: Set<UUID> = []

    private var zoomBox: ZoomBox?
    var onZoomBox: ((Bool) -> Void)?

    /// Pages fill the screen width edge to edge, with a small gap between them.
    static let gapUnits: CGFloat = 14
    private var minZoom: CGFloat { fitZoom * 0.5 }
    private var maxZoom: CGFloat { fitZoom * 4 }

    override var scrollingView: UIScrollView? { scrollView }
    var currentPageId: UUID? { pageViews.indices.contains(currentPage) ? pageViews[currentPage].pageId : nil }

    init(store: LibraryStore, notebook: Notebook, horizontal: Bool) {
        self.horizontal = horizontal
        super.init(store: store, notebook: notebook)
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
        scrollView.alwaysBounceVertical = !horizontal
        scrollView.alwaysBounceHorizontal = horizontal
        // Real values are set in layoutPages; set early so the pinch recogniser exists for palm rejection.
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 4
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        for pid in notebook.pages {
            pageViews.append(makePage(pid))
        }
        installPalmRejection()
        installOverlays()
        refreshMode()
    }

    private func makePage(_ id: UUID) -> PageView {
        let nbId = notebook.id
        let pv = PageView(pageId: id, template: notebook.template, paper: notebook.paper,
                          drawing: store.loadDrawing(notebookId: nbId, pageId: id),
                          elements: store.loadElements(notebookId: nbId, pageId: id),
                          background: store.loadBackground(notebookId: nbId, pageId: id))
        pv.canvas.delegate = canvasDelegate
        pv.canvas.tool = tool
        pv.canvas.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
        pv.canvas.isRulerActive = rulerOn
        let lib = self.store
        pv.model.imageLoader = { [weak lib] name in lib?.loadImageAsset(name, notebookId: nbId) }
        pv.model.onSave = { [weak self] items in
            self?.store.saveElements(items, notebookId: nbId, pageId: id)
            self?.store.touch(nbId)
        }
        pv.model.reloadLayers()
        for l in [pv.under, pv.over] {
            l.onTouchingObject = { [weak self] active in self?.objectTouch(active) }
            l.editing = editorTool == .text && !readOnly
        }
        pv.canvas.isUserInteractionEnabled = canvasEnabled
        resetStrokeCount(pv.canvas)
        contentView.addSubview(pv)
        return pv
    }

    // MARK: Layout & zoom

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 0, !isBaking,
              abs(size.width - lastSize.width) > 0.5 || (horizontal && abs(size.height - lastSize.height) > 0.5) else { return }
        let wasFit = lastSize == .zero || abs(docZoom - fitZoom) < 0.001
        let anchor = currentPage
        lastSize = size
        fitZoom = computeFit()
        docZoom = wasFit ? fitZoom : min(max(docZoom, minZoom), maxZoom)
        isBaking = true
        scrollView.zoomScale = 1
        isBaking = false
        layoutPages()
        scrollTo(page: anchor, animated: false)
        reportPage(force: true)
        reportZoom()
        zoomBox?.layout(in: view.bounds)
    }

    private func computeFit() -> CGFloat {
        let ps = TemplateRenderer.pageSize
        let w = view.bounds.width
        if horizontal {
            // Whole page on screen, side by side like a book.
            return max(min(w / ps.width, (view.bounds.height - 24) / ps.height), 0.1)
        }
        return w / ps.width
    }

    /// Down (default) or across, like Noteshelf's View Mode.
    func setHorizontal(_ on: Bool) {
        guard on != horizontal else { return }
        let page = currentPage
        horizontal = on
        scrollView.alwaysBounceVertical = !on
        scrollView.alwaysBounceHorizontal = on
        isBaking = true
        scrollView.zoomScale = 1
        fitZoom = computeFit()
        docZoom = fitZoom
        layoutPages()
        isBaking = false
        scrollTo(page: page, animated: false)
        reportPage(force: true)
        reportZoom()
    }

    private var pageStep: CGFloat {
        let ps = TemplateRenderer.pageSize
        return (horizontal ? ps.width : ps.height) + Self.gapUnits
    }

    private func layoutPages() {
        let z = docZoom
        let ps = TemplateRenderer.pageSize
        let g = Self.gapUnits * z
        let pw = ps.width * z
        let ph = ps.height * z
        let n = CGFloat(pageViews.count)
        let size = horizontal
            ? CGSize(width: max(pw, n * (pw + g) - g), height: ph)
            : CGSize(width: pw, height: max(ph, n * (ph + g) - g))

        contentView.transform = .identity
        contentView.frame = CGRect(origin: .zero, size: size)
        for (i, pv) in pageViews.enumerated() {
            let o = CGFloat(i)
            pv.frame = horizontal
                ? CGRect(x: o * (pw + g), y: 0, width: pw, height: ph)
                : CGRect(x: 0, y: o * (ph + g), width: pw, height: ph)
            pv.apply(zoom: z)
        }
        scrollView.contentSize = size
        scrollView.minimumZoomScale = minZoom / z
        scrollView.maximumZoomScale = maxZoom / z
        updateInsets()
        zoomBox?.refreshFrame()
    }

    private func updateInsets() {
        let cs = scrollView.contentSize
        let side = max(0, (scrollView.bounds.width - cs.width) / 2)
        let extra: CGFloat = zoomBox == nil ? 0 : ZoomBox.panelHeight + 40
        if horizontal {
            // Room on both sides so any page can sit in the middle of the screen.
            let pageW = TemplateRenderer.pageSize.width * docZoom * scrollView.zoomScale
            let h = max(0, (scrollView.bounds.width - pageW) / 2)
            let vertical = max(0, (scrollView.bounds.height - cs.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: vertical, left: h, bottom: vertical + extra, right: h)
        } else {
            let bottom = view.safeAreaInsets.bottom + 60 + extra
            scrollView.contentInset = UIEdgeInsets(top: 0, left: side, bottom: bottom, right: side)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    func scrollViewDidZoom(_ sv: UIScrollView) {
        guard sv === scrollView else { return }
        updateInsets()
        reportZoom()
    }

    func scrollViewDidEndZooming(_ sv: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        guard sv === scrollView, !isBaking, abs(scale - 1) > 0.001 else { return }
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
        reportZoom()
    }

    override func resetZoom() {
        guard abs(docZoom - fitZoom) > 0.001 || abs(scrollView.zoomScale - 1) > 0.001 else { return }
        let page = currentPage
        isBaking = true
        scrollView.zoomScale = 1
        docZoom = fitZoom
        layoutPages()
        isBaking = false
        scrollTo(page: page, animated: false)
        reportPage(force: true)
        reportZoom()
    }

    private func reportZoom() {
        let z = docZoom * scrollView.zoomScale / max(fitZoom, 0.001)
        onZoomChanged?(Int((z * 100).rounded()))
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        let maxX = max(-inset.left, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
        let maxY = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        return CGPoint(x: min(max(p.x, -inset.left), maxX), y: min(max(p.y, -inset.top), maxY))
    }

    func scrollViewDidScroll(_ sv: UIScrollView) {
        guard sv === scrollView, !isBaking else { return }
        reportPage(force: false)
    }

    /// In horizontal view at normal zoom, a swipe lands on a whole page.
    func scrollViewWillEndDragging(_ sv: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset target: UnsafeMutablePointer<CGPoint>) {
        guard sv === scrollView, horizontal, abs(docZoom * sv.zoomScale - fitZoom) < 0.01 else { return }
        let step = pageStep * docZoom
        var index = ((target.pointee.x + sv.contentInset.left) / step).rounded()
        let current = CGFloat(currentPage)
        if velocity.x > 0.2 { index = min(index, current + 1) } else if velocity.x < -0.2 { index = max(index, current - 1) }
        index = min(max(index, 0), CGFloat(pageViews.count - 1))
        target.pointee.x = clamped(CGPoint(x: index * step - sv.contentInset.left, y: 0)).x
    }

    private func reportPage(force: Bool) {
        guard !pageViews.isEmpty else { return }
        let z = docZoom * scrollView.zoomScale
        let center = horizontal
            ? (scrollView.contentOffset.x + scrollView.bounds.width / 2) / z
            : (scrollView.contentOffset.y + scrollView.bounds.height / 2) / z
        let idx = min(max(Int(center / pageStep), 0), pageViews.count - 1)
        if force || idx != currentPage {
            currentPage = idx
            onPageChanged?(idx, pageViews.count)
        }
    }

    func scrollTo(page: Int, animated: Bool) {
        guard pageViews.indices.contains(page) else { return }
        let d = CGFloat(page) * pageStep * docZoom * scrollView.zoomScale
        let p = horizontal
            ? CGPoint(x: d - scrollView.contentInset.left, y: scrollView.contentOffset.y)
            : CGPoint(x: scrollView.contentOffset.x, y: d)
        scrollView.setContentOffset(clamped(p), animated: animated)
    }

    // MARK: Tools

    private var canvasEnabled = true

    override func applyTool() {
        for pv in pageViews { pv.canvas.tool = tool }
        zoomBox?.canvas.tool = tool
    }

    override func applyRuler() {
        for pv in pageViews { pv.canvas.isRulerActive = rulerOn }
    }

    override func applyDrawingPolicy(fingerDraws: Bool) {
        for pv in pageViews { pv.canvas.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly }
        zoomBox?.canvas.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
    }

    override func applyCanvasEnabled(_ enabled: Bool) {
        canvasEnabled = enabled
        // Switching the canvas off lets taps reach the objects under the ink.
        for pv in pageViews { pv.canvas.isUserInteractionEnabled = enabled }
        zoomBox?.canvas.isUserInteractionEnabled = enabled
    }

    override func objectLayers(at point: CGPoint) -> (under: ElementsLayer, over: ElementsLayer)? {
        let p = view.convert(point, to: contentView)
        let pv = pageViews.first { $0.frame.contains(p) } ?? (pageViews.indices.contains(currentPage) ? pageViews[currentPage] : nil)
        guard let pv else { return nil }
        return (pv.under, pv.over)
    }

    override var allObjectLayers: [ElementsLayer] { pageViews.flatMap { [$0.under, $0.over] } }

    // MARK: Saving

    private func drawingChanged(_ canvasView: PKCanvasView) {
        if let box = zoomBox, canvasView === box.canvas {
            strokeAdded(in: canvasView)
            box.copyToPage()
            return
        }
        guard let pv = pageViews.first(where: { $0.canvas === canvasView }) else { return }
        strokeAdded(in: canvasView)
        zoomBox?.pageChanged(pv)
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

    override func saveAll() {
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

    // MARK: Pages

    func addPage(background: UIImage? = nil) {
        insertPages(count: 1, backgrounds: background.map { [$0] } ?? [])
    }

    /// Adds pages after the current one (imported pages get their image as the background).
    func insertPages(count: Int, backgrounds: [UIImage]) {
        saveAll()
        let n = max(count, backgrounds.count)
        guard n > 0 else { return }
        var at = currentPage + 1
        let first = at
        for i in 0..<n {
            guard let pid = store.insertPage(notebookId: notebook.id, at: at) else { break }
            if i < backgrounds.count {
                store.saveBackground(backgrounds[i].scaledDown(maxSide: 2400), notebookId: notebook.id, pageId: pid)
            }
            let pv = makePage(pid)
            pageViews.insert(pv, at: min(at, pageViews.count))
            at += 1
        }
        if let fresh = store.notebook(notebook.id) { notebook = fresh }
        layoutPages()
        if let pv = pageViews.indices.contains(first) ? pageViews[first] : nil {
            // Slide the new page in.
            pv.alpha = 0
            pv.transform = CGAffineTransform(translationX: horizontal ? 40 : 0, y: horizontal ? 0 : 40)
            UIView.animate(withDuration: 0.4, delay: 0.05, options: [.curveEaseOut]) {
                pv.alpha = 1
                pv.transform = .identity
            }
        }
        scrollTo(page: first, animated: true)
        reportPage(force: true)
        onPageChanged?(currentPage, pageViews.count)
    }

    func duplicateCurrentPage() {
        saveAll()
        guard let pid = currentPageId,
              let copy = store.duplicatePage(notebookId: notebook.id, pageId: pid) else { return }
        if let fresh = store.notebook(notebook.id) { notebook = fresh }
        let at = currentPage + 1
        pageViews.insert(makePage(copy), at: min(at, pageViews.count))
        layoutPages()
        scrollTo(page: at, animated: true)
        reportPage(force: true)
        onPageChanged?(currentPage, pageViews.count)
    }

    func deleteCurrentPage() {
        let i = currentPage
        guard pageViews.indices.contains(i) else { return }
        closeZoomBox()
        if pageViews.count == 1 {
            // Last page: just clear it.
            let pv = pageViews[0]
            pv.canvas.drawing = PKDrawing()
            resetStrokeCount(pv.canvas)
            pv.model.items = []
            pv.model.save()
            pv.model.reloadLayers()
            dirty.insert(pv.pageId)
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
        scrollTo(page: page, animated: true)
        currentPage = page
        onPageChanged?(page, pageViews.count)
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

    // MARK: Export & thumbnails

    func pageContents() -> [PageContent] {
        saveAll()
        return pageViews.map(\.content)
    }

    private var imageLoader: (String) -> UIImage? {
        let nbId = notebook.id
        let store = self.store
        return { name in store.loadImageAsset(name, notebookId: nbId) }
    }

    /// The whole page (paper, objects and ink) as an image.
    func pageImage(_ index: Int, width: CGFloat) -> UIImage? {
        guard pageViews.indices.contains(index) else { return nil }
        return PageRenderer.image(pageViews[index].content, template: notebook.template, paper: notebook.paper,
                                  width: width, imageLoader: imageLoader)
    }

    func thumbnail(of index: Int, width: CGFloat) -> UIImage? {
        pageImage(index, width: width * 2)
    }

    /// Text typed on each page (text boxes and stickies), for search.
    func pageText(_ index: Int) -> String {
        guard pageViews.indices.contains(index) else { return "" }
        return pageViews[index].model.items.compactMap(\.text).joined(separator: " ")
    }

    func pageHasPhotos(_ index: Int) -> Bool {
        guard pageViews.indices.contains(index) else { return false }
        let pv = pageViews[index]
        return pv.background != nil || pv.model.items.contains { $0.kind == .image }
    }

    // MARK: Zoom box

    var isZoomBoxOpen: Bool { zoomBox != nil }

    func toggleZoomBox() {
        if zoomBox != nil { closeZoomBox(); return }
        guard pageViews.indices.contains(currentPage) else { return }
        let box = ZoomBox(owner: self, page: pageViews[currentPage])
        box.canvas.delegate = canvasDelegate
        box.canvas.tool = tool
        box.canvas.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
        box.canvas.isUserInteractionEnabled = canvasEnabled
        zoomBox = box
        view.insertSubview(box.panel, belowSubview: laser)
        box.layout(in: view.bounds)
        resetStrokeCount(box.canvas)
        updateInsets()
        box.panel.transform = CGAffineTransform(translationX: 0, y: ZoomBox.panelHeight)
        box.panel.alpha = 0
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            box.panel.transform = .identity
            box.panel.alpha = 1
        }
        revealZoomRect()
        onZoomBox?(true)
    }

    func closeZoomBox() {
        guard let box = zoomBox else { return }
        zoomBox = nil
        onZoomBox?(false)
        box.frameView.removeFromSuperview()
        box.grip.removeFromSuperview()
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn], animations: {
            box.panel.transform = CGAffineTransform(translationX: 0, y: ZoomBox.panelHeight)
            box.panel.alpha = 0
        }) { _ in box.panel.removeFromSuperview() }
        updateInsets()
    }

    /// Scrolls so the zoom box's rectangle on the page is visible above the panel.
    func revealZoomRect() {
        guard let box = zoomBox else { return }
        let r = box.frameView.convert(box.frameView.bounds, to: scrollView)
        scrollView.scrollRectToVisible(r.insetBy(dx: -30, dy: -60), animated: true)
    }

    fileprivate func copyToPage(_ drawing: PKDrawing, page: PageView) {
        page.canvas.drawing = drawing
        resetStrokeCount(page.canvas)
        dirty.insert(page.pageId)
        saveTasks[page.pageId]?.cancel()
        let pid = page.pageId
        saveTasks[pid] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            self.save(pageId: pid)
        }
    }

    fileprivate func resetCount(_ c: PKCanvasView) { resetStrokeCount(c) }
}

/// Noteshelf-style Zoom Box: write large in a magnified strip at the bottom of the
/// screen; the ink lands at normal size inside the blue box on the page.
final class ZoomBox: NSObject {
    static let panelHeight: CGFloat = 250

    unowned let owner: PagesViewController
    let page: PageView
    let panel = UIView()
    let canvas = PKCanvasView()
    /// The page's lines (or imported background), shown behind the magnified ink.
    private let paperClip = UIView()
    private let paperImage = UIImageView()
    let frameView = UIView()
    /// Finger handle for moving the box (the box itself lets the pencil write through).
    let grip = UIView()
    /// The part of the page being written in, in page units.
    private(set) var region: CGRect
    private var zoom: CGFloat = 2.4
    private var syncing = false

    init(owner: PagesViewController, page: PageView) {
        self.owner = owner
        self.page = page
        region = CGRect(x: 60, y: 120, width: 340, height: 100)
        super.init()

        panel.backgroundColor = UIColor(hex: "#2C2C2E").withAlphaComponent(0.96)
        panel.layer.cornerRadius = 22
        panel.layer.cornerCurve = .continuous
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.25
        panel.layer.shadowRadius = 16

        paperClip.backgroundColor = page.paper.uiColor
        paperClip.layer.cornerRadius = 14
        paperClip.clipsToBounds = true
        paperClip.isUserInteractionEnabled = false
        paperImage.image = page.backgroundView.image ?? Self.templateImage(page)
        paperImage.contentMode = page.backgroundView.image == nil ? .scaleToFill : .scaleAspectFit
        paperClip.addSubview(paperImage)
        panel.addSubview(paperClip)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.layer.cornerRadius = 14
        canvas.clipsToBounds = true
        canvas.panGestureRecognizer.isEnabled = false
        canvas.drawing = page.canvas.drawing
        panel.addSubview(canvas)

        let buttons: [(String, Selector)] = [("chevron.left", #selector(left)), ("chevron.right", #selector(right)),
                                            ("return", #selector(newLine)), ("xmark", #selector(close))]
        for (i, b) in buttons.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: b.0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            button.layer.cornerRadius = 22
            button.tag = 100 + i
            button.addTarget(self, action: b.1, for: .touchUpInside)
            panel.addSubview(button)
        }

        frameView.layer.borderColor = UIColor(red: 0.1, green: 0.62, blue: 0.86, alpha: 1).cgColor
        frameView.layer.borderWidth = 2
        frameView.layer.cornerRadius = 4
        frameView.backgroundColor = UIColor(red: 0.1, green: 0.62, blue: 0.86, alpha: 0.06)
        frameView.isUserInteractionEnabled = false
        page.addSubview(frameView)
        grip.backgroundColor = UIColor(red: 0.1, green: 0.62, blue: 0.86, alpha: 1)
        grip.layer.cornerRadius = 14
        grip.layer.borderColor = UIColor.white.cgColor
        grip.layer.borderWidth = 2
        let arrows = UIImageView(image: UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right",
                                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)))
        arrows.tintColor = .white
        arrows.frame = CGRect(x: 6, y: 6, width: 16, height: 16)
        arrows.contentMode = .center
        grip.addSubview(arrows)
        grip.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragFrame(_:))))
        page.addSubview(grip)
    }

    func layout(in bounds: CGRect) {
        let w = min(bounds.width - 24, 1000)
        panel.frame = CGRect(x: (bounds.width - w) / 2, y: bounds.height - Self.panelHeight - 78,
                             width: w, height: Self.panelHeight)
        let canvasFrame = CGRect(x: 14, y: 14, width: w - 14 * 3 - 46, height: Self.panelHeight - 28)
        canvas.frame = canvasFrame
        paperClip.frame = canvasFrame
        for i in 0..<4 {
            panel.viewWithTag(100 + i)?.frame = CGRect(x: w - 14 - 46, y: 14 + CGFloat(i) * 56, width: 46, height: 46)
        }
        // The box on the page has the same shape as the writing area.
        zoom = max(canvasFrame.width / 360, 1.2)
        region.size = CGSize(width: canvasFrame.width / zoom, height: canvasFrame.height / zoom)
        clampRegion()
        refreshFrame()
    }

    func refreshFrame() {
        let z = page.zoom
        frameView.frame = CGRect(x: region.minX * z, y: region.minY * z, width: region.width * z, height: region.height * z)
        grip.frame = CGRect(x: frameView.frame.minX - 14, y: frameView.frame.minY - 14, width: 28, height: 28)
        page.bringSubviewToFront(frameView)
        page.bringSubviewToFront(grip)
        canvas.minimumZoomScale = zoom
        canvas.maximumZoomScale = zoom
        canvas.zoomScale = zoom
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.contentSize = CGSize(width: TemplateRenderer.pageSize.width * zoom, height: TemplateRenderer.pageSize.height * zoom)
        canvas.contentOffset = CGPoint(x: region.minX * zoom, y: region.minY * zoom)
        let ps = TemplateRenderer.pageSize
        paperImage.frame = CGRect(x: -region.minX * zoom, y: -region.minY * zoom, width: ps.width * zoom, height: ps.height * zoom)
    }

    private static func templateImage(_ page: PageView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.5
        format.opaque = true
        return UIGraphicsImageRenderer(size: TemplateRenderer.pageSize, format: format).image { ctx in
            TemplateRenderer.draw(template: page.template, paper: page.paper, in: ctx.cgContext)
        }
    }

    private func clampRegion() {
        let ps = TemplateRenderer.pageSize
        region.origin.x = min(max(region.minX, 0), ps.width - region.width)
        region.origin.y = min(max(region.minY, 0), ps.height - region.height)
    }

    private func move(to origin: CGPoint) {
        region.origin = origin
        clampRegion()
        UIView.animate(withDuration: 0.22) { self.refreshFrame() }
        owner.revealZoomRect()
    }

    @objc private func left() { move(to: CGPoint(x: region.minX - region.width * 0.8, y: region.minY)) }
    @objc private func right() {
        if region.maxX >= TemplateRenderer.pageSize.width - 1 { newLine() } else {
            move(to: CGPoint(x: region.minX + region.width * 0.8, y: region.minY))
        }
    }
    @objc private func newLine() { move(to: CGPoint(x: 40, y: region.maxY + 4)) }
    @objc private func close() { owner.closeZoomBox() }

    @objc private func dragFrame(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: page)
        g.setTranslation(.zero, in: page)
        region.origin.x += t.x / page.zoom
        region.origin.y += t.y / page.zoom
        clampRegion()
        refreshFrame()
    }

    /// Writing in the box goes onto the page; near the right edge the box moves on.
    func copyToPage() {
        guard !syncing else { return }
        let d = canvas.drawing
        guard d.strokes.count != page.canvas.drawing.strokes.count || d.bounds != page.canvas.drawing.bounds else { return }
        syncing = true
        owner.copyToPage(d, page: page)
        syncing = false
        if let last = d.strokes.last, last.renderBounds.maxX > region.maxX - region.width * 0.16,
           last.renderBounds.minX > region.minX {
            right()
        }
    }

    /// Writing straight on the page (or erasing there) shows up in the box too.
    func pageChanged(_ pv: PageView) {
        guard pv === page, !syncing else { return }
        let d = page.canvas.drawing
        guard d.strokes.count != canvas.drawing.strokes.count || d.bounds != canvas.drawing.bounds else { return }
        syncing = true
        canvas.drawing = d
        owner.resetCount(canvas)
        syncing = false
    }
}
