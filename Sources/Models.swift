import Foundation
import UIKit

struct Folder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorIndex: Int = 0
    var icon: String = "folder.fill"
    var createdAt: Date = Date()
    // Added in 1.3: the folder this one sits inside (nil = top level).
    var parentId: UUID? = nil
}

/// A named page in the notebook outline (table of contents).
struct OutlineEntry: Codable, Hashable {
    var pageId: UUID
    var title: String
}

enum ElementKind: String, Codable {
    case text, sticky, image, emoji, tape

    /// Tape covers the ink, so it sits above the writing; everything else sits under it.
    var isOverInk: Bool { self == .tape }
}

/// Something placed on a page that isn't ink: a text box, sticky note, photo,
/// emoji/sticker or a strip of tape. Positions are in page units (800 x 1131).
struct PageElement: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: ElementKind
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var text: String? = nil
    var colorHex: String? = nil
    var fontSize: CGFloat? = nil
    var imageFile: String? = nil
    var symbol: String? = nil
    var revealed: Bool? = nil
    // Added in 1.5: freehand tape. The path's points as x,y pairs, each 0…1 across the
    // frame (minus half the band on every side), so moving or resizing the tape keeps its shape.
    var points: [CGFloat]? = nil
    /// Width of the tape band in page units.
    var lineWidth: CGFloat? = nil
    // Added in 1.12: the part of a picture that shows, as x, y, width, height, each 0…1 of the picture.
    var crop: [CGFloat]? = nil

    /// The shown part of the picture (0…1), the whole picture when it isn't cropped.
    var cropRect: CGRect {
        guard let c = crop, c.count == 4, c[2] > 0, c[3] > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: c[0], y: c[1], width: c[2], height: c[3])
    }

    /// Crops the picture to `rect` (0…1) and reshapes the frame to match, keeping its width and centre.
    mutating func setCrop(_ rect: CGRect, imageSize: CGSize) {
        let whole = rect.width > 0.999 && rect.height > 0.999
        crop = whole ? nil : [rect.minX, rect.minY, rect.width, rect.height]
        let pw = imageSize.width * rect.width, ph = imageSize.height * rect.height
        guard pw > 0, ph > 0 else { return }
        let c = CGPoint(x: x + w / 2, y: y + h / 2)
        // Keep about the same area on the page.
        let area = w * h
        let newW = sqrt(area * pw / ph)
        let newH = newW * ph / pw
        frame = CGRect(x: c.x - newW / 2, y: c.y - newH / 2, width: newW, height: newH)
    }

    /// The picture with this object's crop applied.
    func cropped(_ img: UIImage) -> UIImage {
        let r = cropRect
        guard crop != nil else { return img }
        let px = CGRect(x: r.minX * img.size.width, y: r.minY * img.size.height,
                        width: r.width * img.size.width, height: r.height * img.size.height)
        guard px.width >= 1, px.height >= 1 else { return img }
        let format = UIGraphicsImageRendererFormat()
        format.scale = img.scale
        return UIGraphicsImageRenderer(size: px.size, format: format).image { _ in
            img.draw(at: CGPoint(x: -px.minX, y: -px.minY))
        }
    }

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: w, height: h) }
        set { x = newValue.minX; y = newValue.minY; w = newValue.width; h = newValue.height }
    }

    /// The freehand tape's centre line inside `rect` (the element's frame in some coordinate space,
    /// `scale` = points per page unit). Nil for old, rectangular tape.
    func tapePath(in rect: CGRect, scale: CGFloat) -> CGPath? {
        guard kind == .tape, let pts = points, pts.count >= 4 else { return nil }
        let half = (lineWidth ?? 30) * scale / 2
        let inner = rect.insetBy(dx: min(half, rect.width / 2), dy: min(half, rect.height / 2))
        let path = CGMutablePath()
        var i = 0
        while i + 1 < pts.count {
            let p = CGPoint(x: inner.minX + pts[i] * inner.width, y: inner.minY + pts[i + 1] * inner.height)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            i += 2
        }
        return path
    }
}

enum CoverPattern: String, Codable, CaseIterable, Identifiable {
    case plain, stripes, dots, grid, waves, linen
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct CoverStyle: Codable, Hashable {
    var paletteIndex: Int
    var pattern: CoverPattern
    // Added in 1.12: a colour picked with the colour wheel (instead of a palette), and a photo
    // from the gallery, already cropped to the cover (a file in the Covers folder).
    var customHex: String? = nil
    var photo: String? = nil
}

enum PageTemplate: String, Codable, CaseIterable, Identifiable {
    case blank, ruled, narrowRuled, grid, dotted, cornell
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blank: return "Blank"
        case .ruled: return "Ruled"
        case .narrowRuled: return "Narrow Ruled"
        case .grid: return "Grid"
        case .dotted: return "Dotted"
        case .cornell: return "Cornell"
        }
    }
}

enum PaperColor: String, Codable, CaseIterable, Identifiable {
    case white, cream, yellow, gray, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var uiColor: UIColor {
        switch self {
        case .white: return UIColor(hex: "#FFFFFF")
        case .cream: return UIColor(hex: "#FBF6E9")
        case .yellow: return UIColor(hex: "#FFF8C9")
        case .gray: return UIColor(hex: "#F0F0F0")
        case .dark: return UIColor(hex: "#2A2A2E")
        }
    }

    var lineColor: UIColor {
        switch self {
        case .white: return UIColor(hex: "#BCCADB")
        case .cream: return UIColor(hex: "#D9C9A8")
        case .yellow: return UIColor(hex: "#9CC1DF")
        case .gray: return UIColor(hex: "#C6C6C6")
        case .dark: return UIColor(hex: "#4C4C54")
        }
    }

    /// The paper behind imported pages shown dark.
    static let darkImport = UIColor(hex: "#1F1F22")

    var marginColor: UIColor {
        self == .dark ? UIColor(hex: "#7A4A4A") : UIColor(hex: "#E9A3A3")
    }
}

struct Notebook: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var folderId: UUID?
    var cover: CoverStyle
    var template: PageTemplate
    var paper: PaperColor
    var pages: [UUID]
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    // Optional so libraries saved by version 1.0 still load.
    var starred: Bool? = nil
    var trashedAt: Date? = nil
    // Added in 1.2: nil means a normal paged notebook.
    var kind: NotebookKind? = nil
    // Added in 1.3.
    var bookmarks: [UUID]? = nil
    var outline: [OutlineEntry]? = nil
    // Added in 1.4: extra space added around pages (keyed by page id).
    var pageExtents: [String: PageExtent]? = nil
    // Added in 1.12: size and orientation of new pages, line spacing (1 = normal),
    // and showing imported pages (PDFs, photos) dark.
    var pageFormat: PageFormat? = nil
    var lineSpacing: Double? = nil
    var darkPages: Bool? = nil

    var isStarred: Bool { starred ?? false }
    var spacing: CGFloat { CGFloat(lineSpacing ?? 1) }
    var isDarkPages: Bool { darkPages ?? false }
    /// What a new page starts as: the notebook's page size, or nothing for the standard A4 page.
    var newPageExtent: PageExtent? {
        guard let f = pageFormat, f.unitSize != TemplateRenderer.pageSize else { return nil }
        return PageExtent(base: f.unitSize)
    }
    func isBookmarked(_ page: UUID) -> Bool { bookmarks?.contains(page) ?? false }
    func outlineTitle(_ page: UUID) -> String? { outline?.first { $0.pageId == page }?.title }
    func extent(_ page: UUID) -> PageExtent { pageExtents?[page.uuidString] ?? .zero }
    var isTrashed: Bool { trashedAt != nil }
    var isCanvas: Bool { kind == .canvas }
}

enum NotebookKind: String, Codable {
    /// Pages stacked vertically, like a paper notebook.
    case paged
    /// One endless whiteboard you can scroll and zoom in every direction.
    case canvas
}

enum SortOrder: String, CaseIterable, Identifiable {
    case modified, title, created
    var id: String { rawValue }
    var title: String {
        switch self {
        case .modified: return "Last Edited"
        case .title: return "Title"
        case .created: return "Date Created"
        }
    }
}

/// Space added around a page with "Add Space to Page", in page units.
/// The original page keeps its size and sits `left`/`top` in from the corner.
struct PageExtent: Codable, Hashable {
    var top: CGFloat = 0
    var left: CGFloat = 0
    var bottom: CGFloat = 0
    var right: CGFloat = 0
    // Added in 1.12: the page's own size before any added space (nil = standard A4, 800 x 1131).
    var baseWidth: CGFloat? = nil
    var baseHeight: CGFloat? = nil

    static let zero = PageExtent()

    init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }

    init(base: CGSize) {
        baseWidth = base.width
        baseHeight = base.height
    }

    /// The page before any added space.
    var base: CGSize {
        guard let w = baseWidth, let h = baseHeight, w > 0, h > 0 else { return TemplateRenderer.pageSize }
        return CGSize(width: w, height: h)
    }

    var size: CGSize {
        let b = base
        return CGSize(width: b.width + left + right, height: b.height + top + bottom)
    }

    /// Where the original page (and an imported page background) sits.
    var originalRect: CGRect {
        CGRect(origin: CGPoint(x: left, y: top), size: base)
    }

    /// Adds `b`'s space; the page keeps `a`'s size.
    static func + (a: PageExtent, b: PageExtent) -> PageExtent {
        var r = PageExtent(top: a.top + b.top, left: a.left + b.left, bottom: a.bottom + b.bottom, right: a.right + b.right)
        r.baseWidth = a.baseWidth
        r.baseHeight = a.baseHeight
        return r
    }

    /// Only the added space (for comparing with `.zero`).
    var addedSpace: PageExtent { PageExtent(top: top, left: left, bottom: bottom, right: right) }
}

/// Paper sizes for new pages. Sizes are in page units, where 800 is the width of A4.
enum PageSize: String, Codable, CaseIterable, Identifiable {
    case a4, a5, letter, b5, widescreen, ipad
    var id: String { rawValue }

    var title: String {
        switch self {
        case .a4: return "A4"
        case .a5: return "A5"
        case .letter: return "Letter"
        case .b5: return "B5"
        case .widescreen: return "16:9"
        case .ipad: return "iPad Screen"
        }
    }

    var detail: String {
        switch self {
        case .a4: return "210 × 297 mm"
        case .a5: return "148 × 210 mm"
        case .letter: return "8.5 × 11 in"
        case .b5: return "176 × 250 mm"
        case .widescreen: return "Slides"
        case .ipad: return "iPad Air 11\""
        }
    }

    /// Upright size.
    var portrait: CGSize {
        switch self {
        case .a4: return CGSize(width: 800, height: 1131)
        case .a5: return CGSize(width: 564, height: 800)
        case .letter: return CGSize(width: 822, height: 1064)
        case .b5: return CGSize(width: 670, height: 952)
        case .widescreen: return CGSize(width: 636, height: 1131)
        // The iPad Air 11" screen is 1640 x 2360.
        case .ipad: return CGSize(width: 800, height: 1151)
        }
    }

    /// 16:9 is a slide, so it starts sideways.
    var prefersLandscape: Bool { self == .widescreen }
}

struct PageFormat: Codable, Hashable {
    var size: PageSize = .a4
    var landscape: Bool = false

    var unitSize: CGSize {
        let p = size.portrait
        return landscape ? CGSize(width: p.height, height: p.width) : p
    }

    static let standard = PageFormat()
}
