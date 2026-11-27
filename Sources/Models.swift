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

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: w, height: h) }
        set { x = newValue.minX; y = newValue.minY; w = newValue.width; h = newValue.height }
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

    var isStarred: Bool { starred ?? false }
    func isBookmarked(_ page: UUID) -> Bool { bookmarks?.contains(page) ?? false }
    func outlineTitle(_ page: UUID) -> String? { outline?.first { $0.pageId == page }?.title }
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
