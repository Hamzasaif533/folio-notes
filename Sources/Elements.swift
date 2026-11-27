import UIKit
import PencilKit

/// The objects on one page, shared by the layer under the ink and the layer
/// over it (tape), so both save into one list.
final class ElementModel {
    var items: [PageElement]
    var onSave: (([PageElement]) -> Void)?
    var imageLoader: (String) -> UIImage? = { _ in nil }
    weak var under: ElementsLayer?
    weak var over: ElementsLayer?

    init(items: [PageElement]) { self.items = items }

    func save() { onSave?(items) }

    func update(_ e: PageElement) {
        guard let i = items.firstIndex(where: { $0.id == e.id }) else { return }
        items[i] = e
        save()
    }

    func add(_ e: PageElement) {
        items.append(e)
        save()
        reloadLayers()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
        reloadLayers()
    }

    func bringToFront(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let e = items.remove(at: i)
        items.append(e)
        save()
        reloadLayers()
    }

    func reloadLayers() {
        under?.reload()
        over?.reload()
    }
}

/// Shows page objects as real views, positioned in page units times `scale`.
/// Lets touches through everywhere except on an object, so writing and
/// scrolling keep working around them.
final class ElementsLayer: UIView {
    let model: ElementModel
    let overInk: Bool
    /// View points per page unit, and the page unit shown at this layer's top-left.
    var scale: CGFloat = 1
    var origin: CGPoint = .zero
    /// Object editing (the Text Box tool): drag, resize, type.
    var editing = false { didSet { if !editing { select(nil) }; refreshInteraction() } }
    var onTouchingObject: ((Bool) -> Void)?

    private(set) var views: [UUID: ElementView] = [:]
    private(set) weak var selected: ElementView?

    init(model: ElementModel, overInk: Bool) {
        self.model = model
        self.overInk = overInk
        super.init(frame: .zero)
        backgroundColor = .clear
        if overInk { model.over = self } else { model.under = self }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var mine: [PageElement] { model.items.filter { $0.kind.isOverInk == overInk } }

    func reload() {
        let list = mine
        let ids = Set(list.map(\.id))
        for (id, v) in views where !ids.contains(id) {
            v.removeFromSuperview()
            views[id] = nil
        }
        for e in list {
            let v: ElementView
            if let existing = views[e.id] {
                v = existing
                v.element = e
            } else {
                v = ElementView(element: e, layer: self)
                views[e.id] = v
            }
            addSubview(v) // keeps z-order matching the list order
        }
        relayout()
        refreshInteraction()
    }

    func relayout() {
        for v in views.values { v.applyLayout() }
    }

    func viewRect(_ unit: CGRect) -> CGRect {
        CGRect(x: (unit.minX - origin.x) * scale, y: (unit.minY - origin.y) * scale,
               width: unit.width * scale, height: unit.height * scale)
    }

    func unitPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / scale + origin.x, y: p.y / scale + origin.y)
    }

    private func refreshInteraction() {
        // Tape can always be tapped to peek; other objects only while editing.
        isUserInteractionEnabled = editing || overInk
        for v in views.values { v.refreshChrome() }
    }

    func select(_ v: ElementView?) {
        if selected !== v { selected?.endTyping() }
        let old = selected
        selected = v
        old?.refreshChrome()
        v?.refreshChrome()
    }

    func objectView(at p: CGPoint) -> ElementView? {
        for v in subviews.reversed() {
            guard let ev = v as? ElementView else { continue }
            if ev.frame.insetBy(dx: -14, dy: -14).contains(p) { return ev }
        }
        return nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden else { return nil }
        for v in subviews.reversed() {
            guard let ev = v as? ElementView, ev.isUserInteractionEnabled else { continue }
            let p = convert(point, to: ev)
            if let hit = ev.hitTest(p, with: event) { return hit }
        }
        return nil
    }

    /// New text box (or sticky) at a page-unit point, ready to type.
    func addText(at unit: CGPoint, color: String, size: CGFloat) {
        let e = PageElement(kind: .text, x: unit.x, y: unit.y - size * 0.7, w: 300, h: size * 1.6,
                            text: "", colorHex: color, fontSize: size)
        model.add(e)
        if let v = views[e.id] {
            select(v)
            v.beginTyping()
        }
    }
}

/// One object on the page.
final class ElementView: UIView, UITextViewDelegate, UIContextMenuInteractionDelegate {
    var element: PageElement { didSet { applyContent() } }
    private unowned let layerOwner: ElementsLayer
    private let textView = UITextView()
    private let imageView = UIImageView()
    private let label = UILabel()
    private let tapeView = UIView()
    private let border = CAShapeLayer()
    private let handle = UIView()
    private var dragStart: CGRect = .zero

    init(element: PageElement, layer: ElementsLayer) {
        self.element = element
        self.layerOwner = layer
        super.init(frame: .zero)
        backgroundColor = .clear

        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        textView.delegate = self
        textView.overrideUserInterfaceStyle = .light
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 6
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.2
        tapeView.layer.cornerRadius = 2
        [tapeView, imageView, textView, label].forEach { addSubview($0) }

        border.fillColor = nil
        border.strokeColor = UIColor(red: 0.1, green: 0.62, blue: 0.86, alpha: 1).cgColor
        border.lineWidth = 1.5
        border.lineDashPattern = [6, 4]
        self.layer.addSublayer(border)

        handle.backgroundColor = UIColor(red: 0.1, green: 0.62, blue: 0.86, alpha: 1)
        handle.layer.cornerRadius = 11
        handle.layer.borderColor = UIColor.white.cgColor
        handle.layer.borderWidth = 2
        addSubview(handle)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
        addGestureRecognizer(pan)
        let resize = UIPanGestureRecognizer(target: self, action: #selector(resized(_:)))
        handle.addGestureRecognizer(resize)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        addInteraction(UIContextMenuInteraction(delegate: self))
        applyContent()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var isSelected: Bool { layerOwner.selected === self }

    func applyLayout() {
        frame = layerOwner.viewRect(element.frame)
        let b = bounds
        let s = layerOwner.scale
        switch element.kind {
        case .text, .sticky:
            textView.frame = element.kind == .sticky ? b.insetBy(dx: 10 * s, dy: 10 * s) : b
            textView.font = font(scale: s)
        case .image:
            imageView.frame = b
        case .emoji:
            label.frame = b
            imageView.frame = b
            label.font = .systemFont(ofSize: max(b.height * 0.82, 4))
        case .tape:
            tapeView.frame = b
        }
        if element.kind == .sticky {
            layer.shadowPath = UIBezierPath(rect: b).cgPath
        }
        border.frame = b
        border.path = UIBezierPath(roundedRect: b.insetBy(dx: -3, dy: -3), cornerRadius: 4).cgPath
        handle.frame = CGRect(x: b.maxX - 11, y: b.maxY - 11, width: 22, height: 22)
    }

    private func font(scale s: CGFloat) -> UIFont {
        let size = max((element.fontSize ?? 22) * s, 2)
        if element.kind == .sticky {
            return UIFont(name: "Noteworthy-Bold", size: size) ?? .systemFont(ofSize: size, weight: .medium)
        }
        return .systemFont(ofSize: size)
    }

    private func applyContent() {
        let color = UIColor(hex: element.colorHex ?? "#1C1C1E")
        textView.isHidden = !(element.kind == .text || element.kind == .sticky)
        imageView.isHidden = element.kind != .image
        label.isHidden = element.kind != .emoji
        tapeView.isHidden = element.kind != .tape
        layer.shadowOpacity = 0
        backgroundColor = .clear
        switch element.kind {
        case .text:
            if !textView.isFirstResponder { textView.text = element.text }
            textView.textColor = color
        case .sticky:
            if !textView.isFirstResponder { textView.text = element.text }
            textView.textColor = UIColor(hex: "#3A3A3C")
            backgroundColor = color
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.18
            layer.shadowRadius = 5
            layer.shadowOffset = CGSize(width: 0, height: 3)
        case .image:
            if imageView.image == nil, let file = element.imageFile {
                imageView.image = layerOwner.model.imageLoader(file)
            }
        case .emoji:
            if let symbol = element.symbol,
               let img = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 120, weight: .semibold)) {
                // Stickers are drawn symbols; emojis are text.
                label.isHidden = true
                imageView.isHidden = false
                imageView.contentMode = .scaleAspectFit
                imageView.layer.cornerRadius = 0
                imageView.clipsToBounds = false
                imageView.image = img.withTintColor(color, renderingMode: .alwaysOriginal)
            } else {
                label.text = element.text
            }
        case .tape:
            tapeView.backgroundColor = UIColor(patternImage: Self.tapePattern(color))
            tapeView.alpha = (element.revealed ?? false) ? 0.22 : 1
        }
        applyLayout()
        refreshChrome()
    }

    func refreshChrome() {
        let editing = layerOwner.editing
        isUserInteractionEnabled = editing || element.kind == .tape
        border.isHidden = !(editing && isSelected)
        handle.isHidden = !(editing && isSelected)
    }

    /// Washi-tape look: the colour with fine diagonal stripes.
    private static func tapePattern(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 12, height: 12)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            color.withAlphaComponent(0.92).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.22).setStroke()
            let p = UIBezierPath()
            p.lineWidth = 3
            p.move(to: CGPoint(x: -2, y: 14)); p.addLine(to: CGPoint(x: 14, y: -2))
            p.stroke()
        }
    }

    // MARK: Gestures

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if layerOwner.editing { layerOwner.onTouchingObject?(true) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        layerOwner.onTouchingObject?(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        layerOwner.onTouchingObject?(false)
    }

    @objc private func tapped() {
        if element.kind == .tape && !layerOwner.editing {
            element.revealed = !(element.revealed ?? false)
            layerOwner.model.update(element)
            UIView.animate(withDuration: 0.2) { self.tapeView.alpha = (self.element.revealed ?? false) ? 0.22 : 1 }
            return
        }
        guard layerOwner.editing else { return }
        if isSelected, element.kind == .text || element.kind == .sticky {
            beginTyping()
        } else {
            layerOwner.select(self)
        }
    }

    @objc private func moved(_ g: UIPanGestureRecognizer) {
        guard layerOwner.editing, !textView.isFirstResponder else { return }
        let s = layerOwner.scale
        switch g.state {
        case .began:
            dragStart = element.frame
            layerOwner.select(self)
            layerOwner.onTouchingObject?(true)
        case .changed:
            let t = g.translation(in: superview)
            element.x = dragStart.minX + t.x / s
            element.y = dragStart.minY + t.y / s
        case .ended, .cancelled:
            layerOwner.model.update(element)
            layerOwner.onTouchingObject?(false)
        default: break
        }
    }

    @objc private func resized(_ g: UIPanGestureRecognizer) {
        guard layerOwner.editing else { return }
        let s = layerOwner.scale
        switch g.state {
        case .began:
            dragStart = element.frame
            layerOwner.onTouchingObject?(true)
        case .changed:
            let t = g.translation(in: superview)
            var w = max(dragStart.width + t.x / s, 30)
            var h = max(dragStart.height + t.y / s, 20)
            if element.kind == .image || element.kind == .emoji {
                // Keep the shape of photos and stickers.
                let ratio = dragStart.width / max(dragStart.height, 1)
                h = w / ratio
            }
            if element.kind == .text {
                h = max(h, fittedTextHeight(width: w))
            }
            if element.kind == .sticky { w = max(w, 80); h = max(h, 80) }
            element.w = w
            element.h = h
        case .ended, .cancelled:
            layerOwner.model.update(element)
            layerOwner.onTouchingObject?(false)
        default: break
        }
    }

    // MARK: Typing

    func beginTyping() {
        guard element.kind == .text || element.kind == .sticky else { return }
        textView.isEditable = true
        textView.isSelectable = true
        textView.becomeFirstResponder()
    }

    func endTyping() {
        guard textView.isFirstResponder || textView.isEditable else { return }
        textView.resignFirstResponder()
        textView.isEditable = false
        textView.isSelectable = false
    }

    private func fittedTextHeight(width: CGFloat) -> CGFloat {
        let s = layerOwner.scale
        let fit = textView.sizeThatFits(CGSize(width: width * s, height: .greatestFiniteMagnitude))
        return fit.height / max(s, 0.01)
    }

    func textViewDidChange(_ tv: UITextView) {
        element.text = tv.text
        if element.kind == .text {
            element.h = max(fittedTextHeight(width: element.w), (element.fontSize ?? 22) * 1.4)
        }
    }

    func textViewDidEndEditing(_ tv: UITextView) {
        textView.isEditable = false
        textView.isSelectable = false
        element.text = tv.text
        if element.kind == .text && (tv.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            layerOwner.model.remove(element.id)
        } else {
            layerOwner.model.update(element)
        }
    }

    // MARK: Menu

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let model = layerOwner.model
        let id = element.id
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIMenuElement] = []
            if self.element.kind == .text || self.element.kind == .sticky {
                actions.append(UIAction(title: "Edit Text", image: UIImage(systemName: "character.cursor.ibeam")) { [weak self] _ in
                    guard let self else { return }
                    self.layerOwner.select(self)
                    self.beginTyping()
                })
            }
            if self.element.kind == .sticky || self.element.kind == .tape || self.element.kind == .text {
                let colors = self.element.kind == .text ? Theme.penColors.prefix(8).map { $0 } : Self.softColors
                let items = colors.map { hex in
                    UIAction(title: hex, image: UIImage(systemName: "circle.fill")?
                        .withTintColor(UIColor(hex: hex), renderingMode: .alwaysOriginal)) { [weak self] _ in
                        guard let self else { return }
                        self.element.colorHex = hex
                        model.update(self.element)
                    }
                }
                actions.append(UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"), children: items))
            }
            actions.append(UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                guard let self else { return }
                var copy = self.element
                copy.id = UUID()
                copy.x += 24
                copy.y += 24
                model.add(copy)
            })
            actions.append(UIAction(title: "Bring to Front", image: UIImage(systemName: "square.3.layers.3d.top.filled")) { _ in
                model.bringToFront(id)
            })
            actions.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                model.remove(id)
            })
            return UIMenu(children: actions)
        }
    }

    static let softColors = ["#FFE680", "#FFB8D1", "#B8E6FF", "#C8F0B0", "#FFD0A8", "#D9C8FF"]
}

// MARK: - Drawing objects into images and PDFs

enum ElementRenderer {
    /// Draws objects in page units into the current context.
    static func draw(_ elements: [PageElement], overInk: Bool, in ctx: CGContext,
                     imageLoader: (String) -> UIImage?) {
        for e in elements where e.kind.isOverInk == overInk {
            let r = e.frame
            let color = UIColor(hex: e.colorHex ?? "#1C1C1E")
            switch e.kind {
            case .text:
                drawText(e.text ?? "", in: r.insetBy(dx: 4, dy: 4), font: .systemFont(ofSize: e.fontSize ?? 22), color: color)
            case .sticky:
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 5, color: UIColor.black.withAlphaComponent(0.18).cgColor)
                color.setFill()
                ctx.fill(r)
                ctx.restoreGState()
                let f = UIFont(name: "Noteworthy-Bold", size: e.fontSize ?? 22) ?? .systemFont(ofSize: e.fontSize ?? 22)
                drawText(e.text ?? "", in: r.insetBy(dx: 14, dy: 14), font: f, color: UIColor(hex: "#3A3A3C"))
            case .image:
                if let file = e.imageFile, let img = imageLoader(file) {
                    ctx.saveGState()
                    UIBezierPath(roundedRect: r, cornerRadius: 6).addClip()
                    let s = max(r.width / img.size.width, r.height / img.size.height)
                    let size = CGSize(width: img.size.width * s, height: img.size.height * s)
                    img.draw(in: CGRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height))
                    ctx.restoreGState()
                }
            case .emoji:
                if let symbol = e.symbol,
                   let img = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 120, weight: .semibold))?
                    .withTintColor(color, renderingMode: .alwaysOriginal) {
                    let s = min(r.width / img.size.width, r.height / img.size.height)
                    let size = CGSize(width: img.size.width * s, height: img.size.height * s)
                    img.draw(in: CGRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height))
                } else {
                    let text = (e.text ?? "") as NSString
                    let font = UIFont.systemFont(ofSize: r.height * 0.82)
                    let size = text.size(withAttributes: [.font: font])
                    text.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: [.font: font])
                }
            case .tape:
                if !(e.revealed ?? false) {
                    color.withAlphaComponent(0.92).setFill()
                    ctx.fill(r)
                }
            }
        }
    }

    private static func drawText(_ s: String, in r: CGRect, font: UIFont, color: UIColor) {
        (s as NSString).draw(with: r, options: [.usesLineFragmentOrigin],
                             attributes: [.font: font, .foregroundColor: color], context: nil)
    }
}

/// Everything on a page, for thumbnails, sharing and PDF export.
struct PageContent {
    var drawing: PKDrawing
    var elements: [PageElement]
    var background: UIImage?
}

enum PageRenderer {
    static func draw(_ page: PageContent, template: PageTemplate, paper: PaperColor, in ctx: CGContext,
                     imageLoader: (String) -> UIImage?, inkScale: CGFloat = 3) {
        let rect = CGRect(origin: .zero, size: TemplateRenderer.pageSize)
        if let bg = page.background {
            paper.uiColor.setFill()
            ctx.fill(rect)
            let s = min(rect.width / bg.size.width, rect.height / bg.size.height)
            let size = CGSize(width: bg.size.width * s, height: bg.size.height * s)
            bg.draw(in: CGRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2,
                               width: size.width, height: size.height))
        } else {
            TemplateRenderer.draw(template: template, paper: paper, in: ctx)
        }
        ElementRenderer.draw(page.elements, overInk: false, in: ctx, imageLoader: imageLoader)
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = page.drawing.image(from: rect, scale: inkScale)
        }
        ink.draw(in: rect)
        ElementRenderer.draw(page.elements, overInk: true, in: ctx, imageLoader: imageLoader)
    }

    static func image(_ page: PageContent, template: PageTemplate, paper: PaperColor, width: CGFloat,
                      imageLoader: (String) -> UIImage?) -> UIImage {
        let size = TemplateRenderer.pageSize
        let s = width / size.width
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let out = CGSize(width: width, height: (size.height * s).rounded())
        return UIGraphicsImageRenderer(size: out, format: format).image { r in
            r.cgContext.scaleBy(x: s, y: s)
            draw(page, template: template, paper: paper, in: r.cgContext, imageLoader: imageLoader, inkScale: max(s, 0.3))
        }
    }
}
