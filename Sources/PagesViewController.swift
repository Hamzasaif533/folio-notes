import UIKit

/// One page: paper colour + template lines (vector layers) or an imported
/// background, objects under the ink, Folio's own ink, and tape on top.
final class PageView: UIView {
    let pageId: UUID
    let ink: InkCanvasView
    let backgroundView = UIImageView()
    let model: ElementModel
    let under: ElementsLayer
    let over: ElementsLayer
    private var templateLayers: [CAShapeLayer] = []
    private(set) var zoom: CGFloat = 1
    /// Space added around this page (Add Space to Page).
    var extent: PageExtent = .zero
    /// The page's size in page units, including added space.
    var unitSize: CGSize { extent.size }

    var template: PageTemplate { didSet { rebuildTemplate() } }
    var paper: PaperColor { didSet { rebuildTemplate() } }
    var background: UIImage? {
        didSet {
            backgroundView.image = background
            backgroundView.isHidden = background == nil
            rebuildTemplate()
        }
    }

    init(pageId: UUID, template: PageTemplate, paper: PaperColor, drawing: InkDrawing,
         elements: [PageElement], background: UIImage?) {
        self.pageId = pageId
        ink = InkCanvasView(size: TemplateRenderer.pageSize)
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

        ink.setDrawing(drawing)
        addSubview(ink)
        addSubview(over)
        rebuildTemplate()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Lays the page out at a real on-screen size so the template renders natively at that
    /// size. The ink keeps page units and is scaled; its tiles redraw at the detail needed.
    func apply(zoom z: CGFloat) {
        zoom = z
        let size = CGSize(width: unitSize.width * z, height: unitSize.height * z)
        let rect = CGRect(origin: .zero, size: size)
        ink.setSize(unitSize)
        ink.transform = CGAffineTransform(scaleX: z, y: z)
        ink.center = CGPoint(x: size.width / 2, y: size.height / 2)
        ink.zoomChanged()
        let o = extent.originalRect
        backgroundView.frame = CGRect(x: o.minX * z, y: o.minY * z, width: o.width * z, height: o.height * z)
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
            templateLayers = TemplateRenderer.layers(template: template, paper: paper, scale: zoom, size: unitSize).map { l in
                let s = CAShapeLayer()
                s.frame = CGRect(x: 0, y: 0, width: unitSize.width * zoom, height: unitSize.height * zoom)
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

    /// Its size changed while it was off screen; it lays itself out again when it comes near.
    func markStale() { zoom = -1 }

    var content: PageContent {
        PageContent(drawing: ink.drawing, elements: model.items, background: background, extent: extent)
    }
}

/// The scrolling stack of pages inside a notebook (down, or across in horizontal view).
final class PagesViewController: DrawingSurfaceController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
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
    // 20% to 600% of the page fitting the screen.
    private var minZoom: CGFloat { fitZoom * 0.2 }
    private var maxZoom: CGFloat { fitZoom * 6 }

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
        scrollView.minimumZoomScale = 0.2
        scrollView.maximumZoomScale = 6
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
        pv.extent = notebook.extent(id)
        pv.ink.setSize(pv.unitSize)
        wireInk(pv.ink)
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
        pv.ink.isUserInteractionEnabled = canvasEnabled
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

    /// Where each page starts along the scrolling direction, in page units.
    /// Pages can differ in size once space has been added to them.
    private var pageOffsets: [CGFloat] = []

    private func layoutPages() {
        let z = docZoom
        let ps = TemplateRenderer.pageSize
        let g = Self.gapUnits
        var offsets: [CGFloat] = []
        var along: CGFloat = 0
        var across: CGFloat = horizontal ? ps.height : ps.width
        for pv in pageViews {
            let s = pv.unitSize
            offsets.append(along)
            along += (horizontal ? s.width : s.height) + g
            across = max(across, horizontal ? s.height : s.width)
        }
        along = max(horizontal ? ps.width : ps.height, along - g)
        pageOffsets = offsets
        let size = horizontal
            ? CGSize(width: along * z, height: across * z)
            : CGSize(width: across * z, height: along * z)

        contentView.transform = .identity
        contentView.frame = CGRect(origin: .zero, size: size)
        for (i, pv) in pageViews.enumerated() {
            let s = pv.unitSize
            pv.frame = horizontal
                ? CGRect(x: offsets[i] * z, y: (across - s.height) / 2 * z, width: s.width * z, height: s.height * z)
                : CGRect(x: (across - s.width) / 2 * z, y: offsets[i] * z, width: s.width * z, height: s.height * z)
        }
        scrollView.contentSize = size
        scrollView.minimumZoomScale = minZoom / z
        scrollView.maximumZoomScale = maxZoom / z
        updateInsets()
        // Re-render only the pages near the screen now; the rest catch up as you scroll to them.
        // Redrawing every page after each pinch blocked the next pinch in long notebooks.
        applyZoomToNearbyPages(force: true)
        zoomBox?.refreshFrame()
    }

    /// Pages within about a screen of what's visible get laid out at the current zoom.
    private func applyZoomToNearbyPages(force: Bool = false) {
        let z = docZoom
        let visible = scrollView.convert(scrollView.bounds, to: contentView)
        let margin = horizontal ? visible.width : visible.height
        let near = visible.insetBy(dx: horizontal ? -margin : 0, dy: horizontal ? 0 : -margin)
        for pv in pageViews {
            if pv.frame.intersects(near) {
                if force || abs(pv.zoom - z) > 0.0001 { pv.apply(zoom: z) }
            } else if force {
                pv.markStale()
            }
        }
    }

    private func updateInsets() {
        let cs = scrollView.contentSize
        let side = max(0, (scrollView.bounds.width - cs.width) / 2)
        let extra: CGFloat = zoomBox == nil ? 0 : ZoomBox.panelHeight + 40
        if horizontal {
            // Room on both sides so any page can sit in the middle of the screen.
            let unitW = pageViews.indices.contains(currentPage) ? pageViews[currentPage].unitSize.width
                                                                 : TemplateRenderer.pageSize.width
            let pageW = unitW * docZoom * scrollView.zoomScale
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
        positionSelectionMenu()
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
        positionSelectionMenu()
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
        guard sv === scrollView else { return }
        applyZoomToNearbyPages()
        positionSelectionMenu()
        guard !isBaking else { return }
        reportPage(force: false)
    }

    /// In horizontal view at normal zoom, a swipe lands on a whole page.
    func scrollViewWillEndDragging(_ sv: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset target: UnsafeMutablePointer<CGPoint>) {
        guard sv === scrollView, horizontal, abs(docZoom * sv.zoomScale - fitZoom) < 0.01 else { return }
        guard !pageOffsets.isEmpty else { return }
        let x = (target.pointee.x + sv.contentInset.left) / docZoom
        var index = pageOffsets.indices.min { abs(pageOffsets[$0] - x) < abs(pageOffsets[$1] - x) } ?? currentPage
        if velocity.x > 0.2 { index = min(index, currentPage + 1) } else if velocity.x < -0.2 { index = max(index, currentPage - 1) }
        index = min(max(index, 0), pageOffsets.count - 1)
        target.pointee.x = clamped(CGPoint(x: pageOffsets[index] * docZoom - sv.contentInset.left, y: 0)).x
    }

    private func reportPage(force: Bool) {
        guard !pageViews.isEmpty else { return }
        let z = docZoom * scrollView.zoomScale
        let center = horizontal
            ? (scrollView.contentOffset.x + scrollView.bounds.width / 2) / z
            : (scrollView.contentOffset.y + scrollView.bounds.height / 2) / z
        var idx = 0
        for (i, o) in pageOffsets.enumerated() where o <= center { idx = i }
        idx = min(max(idx, 0), pageViews.count - 1)
        if force || idx != currentPage {
            currentPage = idx
            onPageChanged?(idx, pageViews.count)
        }
    }

    func scrollTo(page: Int, animated: Bool) {
        guard pageViews.indices.contains(page) else { return }
        let start = pageOffsets.indices.contains(page) ? pageOffsets[page] : CGFloat(page) * pageStep
        let d = start * docZoom * scrollView.zoomScale
        let p = horizontal
            ? CGPoint(x: d - scrollView.contentInset.left, y: scrollView.contentOffset.y)
            : CGPoint(x: scrollView.contentOffset.x, y: d)
        scrollView.setContentOffset(clamped(p), animated: animated)
    }

    // MARK: Tools

    private var canvasEnabled = true

    private var allInk: [InkCanvasView] { pageViews.map(\.ink) + (zoomBox.map { [$0.ink] } ?? []) }

    override func applyTool() {
        for ink in allInk { ink.tool = tool }
    }

    override func applyDrawingPolicy(fingerDraws: Bool) {
        for ink in allInk { ink.fingerDraws = fingerDraws }
    }

    override func applyCanvasEnabled(_ enabled: Bool) {
        canvasEnabled = enabled
        // Switching the ink off lets taps reach the objects under it.
        for ink in allInk {
            ink.isUserInteractionEnabled = enabled
            if !enabled { ink.clearSelection() }
        }
    }

    override func objectLayers(at point: CGPoint) -> (under: ElementsLayer, over: ElementsLayer)? {
        let p = view.convert(point, to: contentView)
        let pv = pageViews.first { $0.frame.contains(p) } ?? (pageViews.indices.contains(currentPage) ? pageViews[currentPage] : nil)
        guard let pv else { return nil }
        return (pv.under, pv.over)
    }

    override var allObjectLayers: [ElementsLayer] { pageViews.flatMap { [$0.under, $0.over] } }

    // MARK: Saving

    override func inkChanged(_ canvas: InkCanvasView, to drawing: InkDrawing) -> InkCanvasView {
        // Written in the zoom box: it lands on the page, and the page is what undo restores.
        if let box = zoomBox, canvas === box.ink {
            guard let pv = pageViews.first(where: { $0 === box.page }) else { return canvas }
            pv.ink.setDrawing(drawing)
            scheduleSave(pv)
            box.wrote(drawing)
            return pv.ink
        }
        guard let pv = pageViews.first(where: { $0.ink === canvas }) else { return canvas }
        scheduleSave(pv)
        zoomBox?.pageChanged(pv)
        return canvas
    }

    private func scheduleSave(_ pv: PageView) {
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
        store.saveDrawing(pv.ink.drawing, notebookId: notebook.id, pageId: pageId)
        dirty.remove(pageId)
        saveTasks[pageId] = nil
        store.touch(notebook.id)
    }

    override func saveAll() {
        for (_, t) in saveTasks { t.cancel() }
        saveTasks.removeAll()
        for pid in dirty {
            if let pv = pageViews.first(where: { $0.pageId == pid }) {
                store.saveDrawing(pv.ink.drawing, notebookId: notebook.id, pageId: pid)
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
    func insertPages(count: Int, backgrounds: [UIImage], at index: Int? = nil) {
        saveAll()
        let n = max(count, backgrounds.count)
        guard n > 0 else { return }
        var at = max(0, min(index ?? currentPage + 1, pageViews.count))
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

    func duplicateCurrentPage() { duplicatePage(at: currentPage) }

    func duplicatePage(at index: Int) {
        saveAll()
        guard pageViews.indices.contains(index),
              let copy = store.duplicatePage(notebookId: notebook.id, pageId: pageViews[index].pageId) else { return }
        if let fresh = store.notebook(notebook.id) { notebook = fresh }
        let at = index + 1
        pageViews.insert(makePage(copy), at: min(at, pageViews.count))
        layoutPages()
        scrollTo(page: at, animated: true)
        reportPage(force: true)
        onPageChanged?(currentPage, pageViews.count)
    }

    func deleteCurrentPage() { deletePage(at: currentPage) }

    func deletePage(at index: Int) {
        let i = index
        guard pageViews.indices.contains(i) else { return }
        closeZoomBox()
        if pageViews.count == 1 {
            // Last page: just clear it.
            let pv = pageViews[0]
            pv.ink.clearSelection()
            pv.ink.setDrawing(InkDrawing())
            pv.model.items = []
            pv.model.save()
            pv.model.reloadLayers()
            dirty.insert(pv.pageId)
            saveAll()
            return
        }
        dropPage(at: i)
        finishRemoving(currentAfter: i)
    }

    private func dropPage(at i: Int) {
        let pv = pageViews.remove(at: i)
        saveTasks[pv.pageId]?.cancel()
        dirty.remove(pv.pageId)
        pv.removeFromSuperview()
        store.deletePage(notebookId: notebook.id, pageId: pv.pageId)
    }

    private func finishRemoving(currentAfter i: Int) {
        if let fresh = store.notebook(notebook.id) { notebook = fresh }
        undo.removeAllActions()
        onUndoChanged?(false, false)
        layoutPages()
        currentPage = max(0, min(i, pageViews.count - 1))
        scrollTo(page: currentPage, animated: false)
        reportPage(force: true)
        onPageChanged?(currentPage, pageViews.count)
    }

    /// Deletes several pages at once (all of them leaves one empty page).
    func deletePages(_ indices: [Int]) {
        let set = Set(indices.filter { pageViews.indices.contains($0) })
        guard !set.isEmpty else { return }
        closeZoomBox()
        if set.count >= pageViews.count {
            for i in stride(from: pageViews.count - 1, through: 1, by: -1) { dropPage(at: i) }
            finishRemoving(currentAfter: 0)
            deletePage(at: 0) // clears the one that's left
            return
        }
        for i in set.sorted(by: >) { dropPage(at: i) }
        finishRemoving(currentAfter: set.min() ?? 0)
    }

    /// Moves pages (kept in their order) so the first of them ends up at `position`,
    /// counted among the pages that aren't moving.
    func movePages(_ indices: [Int], to position: Int) {
        let set = Set(indices.filter { pageViews.indices.contains($0) })
        guard !set.isEmpty, set.count < pageViews.count || position == 0 else { return }
        closeZoomBox()
        saveAll()
        let keep = pageViews.indices.contains(currentPage) ? pageViews[currentPage].pageId : nil
        let moving = pageViews.indices.filter { set.contains($0) }.map { pageViews[$0] }
        var rest = pageViews.indices.filter { !set.contains($0) }.map { pageViews[$0] }
        rest.insert(contentsOf: moving, at: max(0, min(position, rest.count)))
        guard rest.map(\.pageId) != pageViews.map(\.pageId) else { return }
        pageViews = rest
        store.setPageOrder(notebookId: notebook.id, pages: pageViews.map(\.pageId))
        if let fresh = store.notebook(notebook.id) { notebook = fresh }
        layoutPages()
        if let keep, let idx = pageViews.firstIndex(where: { $0.pageId == keep }) { currentPage = idx }
        scrollTo(page: currentPage, animated: false)
        reportPage(force: true)
        onPageChanged?(currentPage, pageViews.count)
    }

    /// Pastes a copied page (possibly from another notebook) at `index`.
    func pastePage(from srcNb: UUID, pageId: UUID, at index: Int) {
        saveAll()
        let at = max(0, min(index, pageViews.count))
        guard let pid = store.copyPage(from: srcNb, pageId: pageId, into: notebook.id, at: at) else { return }
        if let fresh = store.notebook(notebook.id) { notebook = fresh }
        pageViews.insert(makePage(pid), at: at)
        layoutPages()
        scrollTo(page: at, animated: true)
        reportPage(force: true)
        onPageChanged?(currentPage, pageViews.count)
    }

    func pageId(at index: Int) -> UUID? { pageViews.indices.contains(index) ? pageViews[index].pageId : nil }

    /// Size of the current page in page units (including space already added).
    var currentPageSize: CGSize {
        pageViews.indices.contains(currentPage) ? pageViews[currentPage].unitSize : TemplateRenderer.pageSize
    }

    /// Add Space to Page: grows the current page (or every page) by `add`.
    func addSpace(_ add: PageExtent, allPages: Bool) {
        guard add != .zero else { return }
        closeZoomBox()
        saveAll()
        let ids = allPages ? pageViews.map { $0.pageId } : (currentPageId.map { [$0] } ?? [])
        store.addSpace(notebookId: notebook.id, pageIds: ids, add: add)
        if let fresh = store.notebook(notebook.id) { notebook = fresh }
        let page = currentPage
        for (i, pv) in pageViews.enumerated() where ids.contains(pv.pageId) {
            saveTasks[pv.pageId]?.cancel()
            dirty.remove(pv.pageId)
            pv.removeFromSuperview()
            pageViews[i] = makePage(pv.pageId)
        }
        undo.removeAllActions()
        onUndoChanged?(false, false)
        layoutPages()
        scrollTo(page: page, animated: false)
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

    /// Just these pages, in page order (exporting a selection or a range).
    func pageContents(_ indices: [Int]) -> [PageContent] {
        saveAll()
        return Set(indices).sorted().filter { pageViews.indices.contains($0) }.map { pageViews[$0].content }
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
        wireInk(box.ink)
        box.ink.isUserInteractionEnabled = canvasEnabled
        zoomBox = box
        view.insertSubview(box.panel, belowSubview: laser)
        box.layout(in: view.bounds)
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
        box.ink.clearSelection()
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

}

/// Noteshelf-style Zoom Box: write large in a magnified strip at the bottom of the
/// screen; the ink lands at normal size inside the blue box on the page.
final class ZoomBox: NSObject {
    static let panelHeight: CGFloat = 250

    unowned let owner: PagesViewController
    let page: PageView
    let panel = UIView()
    let ink: InkCanvasView
    /// The page's lines (or imported background), shown behind the magnified ink.
    /// It also clips the ink to the writing area.
    private let paperClip = UIView()
    private let paperImage = UIImageView()
    let frameView = UIView()
    /// Finger handle for moving the box (the box itself lets the pencil write through).
    let grip = UIView()
    /// The part of the page being written in, in page units.
    private(set) var region: CGRect
    private var zoom: CGFloat = 2.4
    private var strokeCount = 0

    init(owner: PagesViewController, page: PageView) {
        self.owner = owner
        self.page = page
        ink = InkCanvasView(size: page.unitSize)
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
        paperImage.image = page.backgroundView.image ?? Self.templateImage(page)
        paperImage.contentMode = page.backgroundView.image == nil ? .scaleToFill : .scaleAspectFit
        paperClip.addSubview(paperImage)
        ink.setDrawing(page.ink.drawing)
        strokeCount = page.ink.drawing.strokes.count
        paperClip.addSubview(ink)
        panel.addSubview(paperClip)

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
        let ps = page.unitSize
        ink.setSize(ps)
        ink.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        ink.center = CGPoint(x: (ps.width / 2 - region.minX) * zoom, y: (ps.height / 2 - region.minY) * zoom)
        ink.zoomChanged()
        owner.positionSelectionMenu()
        paperImage.frame = CGRect(x: -region.minX * zoom, y: -region.minY * zoom, width: ps.width * zoom, height: ps.height * zoom)
    }

    private static func templateImage(_ page: PageView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.5
        format.opaque = true
        return UIGraphicsImageRenderer(size: page.unitSize, format: format).image { ctx in
            TemplateRenderer.draw(template: page.template, paper: page.paper, in: ctx.cgContext, size: page.unitSize)
        }
    }

    private func clampRegion() {
        let ps = page.unitSize
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
        if region.maxX >= page.unitSize.width - 1 { newLine() } else {
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

    /// Something was written in the box (it is already on the page). A new stroke near
    /// the right edge moves the box on, like Noteshelf.
    func wrote(_ d: InkDrawing) {
        defer { strokeCount = d.strokes.count }
        guard d.strokes.count > strokeCount, let last = d.strokes.last else { return }
        if last.bounds.maxX > region.maxX - region.width * 0.16, last.bounds.minX > region.minX {
            ink.clearSelection()
            right()
        }
    }

    /// Writing straight on the page (or erasing there, or undo) shows up in the box too.
    func pageChanged(_ pv: PageView) {
        guard pv === page else { return }
        ink.setDrawing(page.ink.drawing)
        strokeCount = page.ink.drawing.strokes.count
    }
}
