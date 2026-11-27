import UIKit
import ImageIO
import UniformTypeIdentifiers

// MARK: Imported PDFs kept as PDFs

/// Which page of which PDF a notebook page shows behind the ink
/// (stored next to the page as `<page>.pdfpage`).
struct PDFPageRef: Codable, Equatable {
    /// The PDF's file name inside the notebook's folder.
    var file: String
    /// 0-based page number.
    var index: Int
}

/// An open page of an imported PDF. It's drawn from the PDF itself, so it stays sharp
/// at any zoom and costs no memory while it's off screen.
final class PDFBackground {
    let ref: PDFPageRef
    let document: CGPDFDocument
    let page: CGPDFPage?

    init(ref: PDFPageRef, document: CGPDFDocument) {
        self.ref = ref
        self.document = document
        page = document.page(at: ref.index + 1)
    }

    private var box: CGRect { page?.getBoxRect(.cropBox) ?? .zero }
    private var rotation: Int32 { ((page?.rotationAngle ?? 0) % 360 + 360) % 360 }

    /// The page's size as it's shown (rotation applied), in points.
    var size: CGSize {
        let b = box
        return rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
    }

    /// Draws the page fitted inside `rect` on white paper. `ctx` uses UIKit coordinates (y down).
    func draw(in rect: CGRect, ctx: CGContext) {
        guard let page else { return }
        let b = box
        let shown = size
        guard shown.width > 0, shown.height > 0, rect.width > 0, rect.height > 0 else { return }
        let s = min(rect.width / shown.width, rect.height / shown.height)
        let fitted = CGRect(x: rect.midX - shown.width * s / 2, y: rect.midY - shown.height * s / 2,
                            width: shown.width * s, height: shown.height * s)
        ctx.saveGState()
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(fitted)
        ctx.clip(to: fitted)
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.rotate(by: -CGFloat(rotation) * .pi / 180)
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -b.midX, y: -b.midY)
        ctx.clip(to: b)
        ctx.interpolationQuality = .high
        ctx.setRenderingIntent(.defaultIntent)
        ctx.drawPDFPage(page)
        ctx.restoreGState()
    }
}

/// Open PDFs, shared by every page that shows one of their pages.
enum PDFDocuments {
    private final class Box { let doc: CGPDFDocument; init(_ d: CGPDFDocument) { doc = d } }
    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 6
        return c
    }()

    static func open(_ url: URL) -> CGPDFDocument? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit.doc }
        guard let doc = CGPDFDocument(url as CFURL), doc.isUnlocked, doc.numberOfPages > 0 else { return nil }
        cache.setObject(Box(doc), forKey: key)
        return doc
    }

    static func forget(_ url: URL) { cache.removeObject(forKey: url.path as NSString) }
}

private final class PDFTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0.08 }
}

/// Shows a PDF page in tiles (like the ink): only the visible part is drawn, at the detail
/// the zoom needs. It is sized in page units and scaled with a transform.
final class PDFTileView: UIView {
    override class var layerClass: AnyClass { PDFTiledLayer.self }

    private let lock = NSLock()
    private var current: PDFBackground?
    private var drawSize: CGSize = .zero

    var pdf: PDFBackground? {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set {
            lock.lock()
            current = newValue
            lock.unlock()
            layer.contents = nil
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        if let tiled = layer as? CATiledLayer {
            tiled.levelsOfDetail = 8
            tiled.levelsOfDetailBias = 4
            tiled.tileSize = CGSize(width: 512, height: 512)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setSize(_ size: CGSize) {
        guard size != bounds.size else { return }
        bounds = CGRect(origin: .zero, size: size)
        lock.lock()
        drawSize = size
        lock.unlock()
        setNeedsDisplay()
    }

    // Called for each tile, on background threads.
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        lock.lock()
        let pdf = current, size = drawSize
        lock.unlock()
        pdf?.draw(in: CGRect(origin: .zero, size: size), ctx: ctx)
    }
}

// MARK: Smaller pictures on disk

extension UIImage {
    /// The picture as HEIC (about half the size of JPEG for the same look), or JPEG where
    /// HEIC can't be written. Returns the data and the file extension to use.
    func compactData(quality: CGFloat) -> (data: Data, ext: String)? {
        if let cg = cgImage {
            let out = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(out, UTType.heic.identifier as CFString, 1, nil) {
                let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality,
                                              kCGImagePropertyOrientation: cgOrientation.rawValue]
                CGImageDestinationAddImage(dest, cg, props as CFDictionary)
                if CGImageDestinationFinalize(dest), out.length > 0 { return (data: out as Data, ext: "heic") }
            }
        }
        return jpegData(compressionQuality: min(quality + 0.06, 1)).map { (data: $0, ext: "jpg") }
    }

    private var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
