import Foundation
import UIKit

struct Folder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorIndex: Int = 0
    var icon: String = "folder.fill"
    var createdAt: Date = Date()
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
