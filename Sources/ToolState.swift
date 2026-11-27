import SwiftUI
import PencilKit

enum EditorTool: String, Codable {
    case pen, highlighter, eraser, lasso
}

enum InkKind: String, Codable, CaseIterable, Identifiable {
    case ballpoint, fountain, pencil, monoline, brush, crayon
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ballpoint: return "Ballpoint"
        case .fountain: return "Fountain"
        case .pencil: return "Pencil"
        case .monoline: return "Fineliner"
        case .brush: return "Brush"
        case .crayon: return "Crayon"
        }
    }

    var subtitle: String {
        switch self {
        case .ballpoint: return "Smooth"
        case .fountain: return "Pressure + angle"
        case .pencil: return "Textured"
        case .monoline: return "Even width"
        case .brush: return "Soft & wet"
        case .crayon: return "Waxy"
        }
    }

    var symbol: String {
        switch self {
        case .ballpoint: return "pencil.tip"
        case .fountain: return "pencil.tip.crop.circle"
        case .pencil: return "pencil"
        case .monoline: return "pencil.line"
        case .brush: return "paintbrush.pointed"
        case .crayon: return "scribble.variable"
        }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .ballpoint: return .pen
        case .fountain: return .fountainPen
        case .pencil: return .pencil
        case .monoline: return .monoline
        case .brush: return .watercolor
        case .crayon: return .crayon
        }
    }

    var widthRange: ClosedRange<CGFloat> {
        switch self {
        case .ballpoint: return 0.5...20
        case .fountain: return 1...25
        case .pencil: return 1...16
        case .monoline: return 0.5...20
        case .brush: return 3...40
        case .crayon: return 4...40
        }
    }
}

struct PenPreset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: InkKind
    var colorHex: String
    var width: CGFloat
    var opacity: CGFloat = 1

    var uiColor: UIColor { UIColor(hex: colorHex).withAlphaComponent(opacity) }

    func sameLook(as other: PenPreset) -> Bool {
        kind == other.kind && colorHex == other.colorHex
            && abs(width - other.width) < 0.01 && abs(opacity - other.opacity) < 0.01
    }
}

enum EraserMode: String, Codable, CaseIterable, Identifiable {
    case stroke, pixel
    var id: String { rawValue }
    var title: String { self == .stroke ? "Whole Stroke" : "Precise" }
}

enum DrawingInput: String, Codable, CaseIterable, Identifiable {
    case auto, pencilOnly, anyInput
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .pencilOnly: return "Apple Pencil Only"
        case .anyInput: return "Pencil and Finger"
        }
    }
}

/// The current tool and every pen setting, remembered between launches.
@MainActor
final class ToolState: ObservableObject {
    @Published var tool: EditorTool = .pen
    @Published var pen: PenPreset { didSet { save() } }
    @Published var highlighter: PenPreset { didSet { save() } }
    @Published var eraserMode: EraserMode { didSet { save() } }
    @Published var eraserWidth: CGFloat { didSet { save() } }
    @Published var favorites: [PenPreset] { didSet { save() } }
    @Published var recentColors: [String] { didSet { save() } }
    @Published var inputMode: DrawingInput { didSet { save() } }
    @Published var penQuickColors: [String] { didSet { save() } }
    @Published var penQuickSizes: [CGFloat] { didSet { save() } }
    @Published var highlighterQuickColors: [String] { didSet { save() } }
    @Published var highlighterQuickSizes: [CGFloat] { didSet { save() } }
    @Published var eraserQuickSizes: [CGFloat] { didSet { save() } }
    @Published var rulerActive = false

    static let defaultPenColors = ["#D32F2F", "#1F3BB3", "#2E6B1F"]
    static let defaultPenSizes: [CGFloat] = [1.5, 3, 6]
    static let defaultHighlighterColors = ["#F7E14A", "#A3D977", "#FF9EC4"]
    static let defaultHighlighterSizes: [CGFloat] = [10, 18, 30]
    static let defaultEraserSizes: [CGFloat] = [10, 25, 50]

    private struct Saved: Codable {
        var pen: PenPreset
        var highlighter: PenPreset
        var eraserMode: EraserMode
        var eraserWidth: CGFloat
        var favorites: [PenPreset]
        var recentColors: [String]
        var inputMode: DrawingInput
        // Added in 1.1 (optional so 1.0 settings still load).
        var penQuickColors: [String]?
        var penQuickSizes: [CGFloat]?
        var highlighterQuickColors: [String]?
        var highlighterQuickSizes: [CGFloat]?
        var eraserQuickSizes: [CGFloat]?
    }

    private static let key = "folio.toolstate.v1"
    private var loading = true

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(Saved.self, from: data) {
            pen = s.pen
            highlighter = s.highlighter
            eraserMode = s.eraserMode
            eraserWidth = s.eraserWidth
            favorites = s.favorites
            recentColors = s.recentColors
            inputMode = s.inputMode
            penQuickColors = Self.three(s.penQuickColors, Self.defaultPenColors)
            penQuickSizes = Self.three(s.penQuickSizes, Self.defaultPenSizes)
            highlighterQuickColors = Self.three(s.highlighterQuickColors, Self.defaultHighlighterColors)
            highlighterQuickSizes = Self.three(s.highlighterQuickSizes, Self.defaultHighlighterSizes)
            eraserQuickSizes = Self.three(s.eraserQuickSizes, Self.defaultEraserSizes)
        } else {
            penQuickColors = Self.defaultPenColors
            penQuickSizes = Self.defaultPenSizes
            highlighterQuickColors = Self.defaultHighlighterColors
            highlighterQuickSizes = Self.defaultHighlighterSizes
            eraserQuickSizes = Self.defaultEraserSizes
            pen = PenPreset(kind: .ballpoint, colorHex: "#000000", width: 3)
            highlighter = PenPreset(kind: .monoline, colorHex: "#F7E14A", width: 18, opacity: 1)
            eraserMode = .stroke
            eraserWidth = 20
            favorites = [
                PenPreset(kind: .ballpoint, colorHex: "#000000", width: 3),
                PenPreset(kind: .ballpoint, colorHex: "#2F6FDE", width: 3),
                PenPreset(kind: .ballpoint, colorHex: "#E53935", width: 3),
                PenPreset(kind: .fountain, colorHex: "#1E7F4F", width: 5)
            ]
            recentColors = []
            inputMode = .auto
        }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let s = Saved(pen: pen, highlighter: highlighter, eraserMode: eraserMode,
                      eraserWidth: eraserWidth, favorites: favorites,
                      recentColors: recentColors, inputMode: inputMode,
                      penQuickColors: penQuickColors, penQuickSizes: penQuickSizes,
                      highlighterQuickColors: highlighterQuickColors,
                      highlighterQuickSizes: highlighterQuickSizes,
                      eraserQuickSizes: eraserQuickSizes)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var pkTool: PKTool {
        switch tool {
        case .pen:
            return PKInkingTool(pen.kind.inkType, color: pen.uiColor, width: pen.width)
        case .highlighter:
            return PKInkingTool(.marker, color: highlighter.uiColor, width: highlighter.width)
        case .eraser:
            return eraserMode == .stroke ? PKEraserTool(.vector) : PKEraserTool(.bitmap, width: eraserWidth)
        case .lasso:
            return PKLassoTool()
        }
    }

    private static func three<T>(_ saved: [T]?, _ fallback: [T]) -> [T] {
        guard let saved, saved.count == 3 else { return fallback }
        return saved
    }

    func noteRecent(_ hex: String) {
        var list = recentColors.filter { $0 != hex }
        list.insert(hex, at: 0)
        recentColors = Array(list.prefix(8))
    }

    func addFavorite(_ preset: PenPreset) {
        guard !favorites.contains(where: { $0.sameLook(as: preset) }) else { return }
        var p = preset
        p.id = UUID()
        favorites.append(p)
    }

    func removeFavorite(_ id: UUID) {
        favorites.removeAll { $0.id == id }
    }

    func selectFavorite(_ preset: PenPreset) {
        pen = preset
        tool = .pen
    }
}
