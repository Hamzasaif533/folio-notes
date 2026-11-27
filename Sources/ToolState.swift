import SwiftUI
import PencilKit

enum EditorTool: String, Codable {
    case pen, highlighter, eraser, lasso
    /// Draw roughly; the stroke snaps to a clean line, circle, rectangle, triangle…
    case shapes
    /// Tap the page to type. Also moves and resizes photos, stickies and stickers.
    case text
    /// A glowing pointer that fades away (for presenting).
    case laser
    /// Drag to cover writing with tape; tap tape to peek under it.
    case tape

    /// Tools that put PencilKit ink on the page.
    var inks: Bool { self == .pen || self == .highlighter || self == .shapes }
    /// Tools that have a colour/size bar.
    var hasContextBar: Bool { self == .pen || self == .highlighter || self == .eraser || self == .shapes || self == .text || self == .tape }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        case .shapes: return "square.on.circle"
        case .text: return "textformat"
        case .laser: return "wand.and.rays"
        case .tape: return "bandage"
        }
    }
}

/// GoodNotes-style pen feel. All values 0…1.
struct InkFeel: Codable, Hashable {
    /// How pointed the start and end of each stroke are.
    var tipSharpness: Double = 0
    /// How much the line width follows how hard you press.
    var pressure: Double = 0.5
    /// 0 = round nib, 1 = flat, calligraphy-style nib.
    var tipFlatness: Double = 0
    /// Smooths out shaky lines.
    var stabilization: Double = 0

    static let standard = InkFeel()
    var isStandard: Bool { self == .standard }
}

/// Everything that can be put on the editor toolbar ("Customize Toolbar").
enum ToolbarItemKind: String, Codable, CaseIterable, Identifiable {
    case shapes, textBox, laser, tape, ruler, zoomBox, stickyNote, photo, camera, emoji, stickers
    case addPage, duplicatePage, bookmark, outline, readOnly, viewMode, search, allNotes
    case sharePDF, sharePNG, savePhoto

    var id: String { rawValue }

    static let defaults: [ToolbarItemKind] = [.shapes, .textBox, .laser, .ruler]

    var title: String {
        switch self {
        case .shapes: return "Shapes"
        case .textBox: return "Text Box"
        case .laser: return "Laser Pointer"
        case .tape: return "Tape"
        case .ruler: return "Ruler"
        case .zoomBox: return "Zoom Box"
        case .stickyNote: return "Sticky Note"
        case .photo: return "Photo"
        case .camera: return "Camera"
        case .emoji: return "Emojis"
        case .stickers: return "Stickers"
        case .addPage: return "Add Page"
        case .duplicatePage: return "Duplicate Page"
        case .bookmark: return "Bookmark"
        case .outline: return "Add to Outline"
        case .readOnly: return "Reading Mode"
        case .viewMode: return "View Mode"
        case .search: return "Search"
        case .allNotes: return "Recent Notebooks"
        case .sharePDF: return "Share Notebook as PDF"
        case .sharePNG: return "Share Page as PNG"
        case .savePhoto: return "Save Page as Photo"
        }
    }

    var symbol: String {
        switch self {
        case .shapes: return "square.on.circle"
        case .textBox: return "textformat"
        case .laser: return "wand.and.rays"
        case .tape: return "bandage"
        case .ruler: return "ruler"
        case .zoomBox: return "rectangle.and.text.magnifyingglass"
        case .stickyNote: return "note.text"
        case .photo: return "photo"
        case .camera: return "camera"
        case .emoji: return "face.smiling"
        case .stickers: return "seal"
        case .addPage: return "doc.badge.plus"
        case .duplicatePage: return "plus.square.on.square"
        case .bookmark: return "bookmark"
        case .outline: return "list.bullet.indent"
        case .readOnly: return "book"
        case .viewMode: return "rectangle.split.2x1"
        case .search: return "magnifyingglass"
        case .allNotes: return "clock.arrow.circlepath"
        case .sharePDF: return "doc.richtext"
        case .sharePNG: return "square.and.arrow.up"
        case .savePhoto: return "photo.badge.arrow.down"
        }
    }

    var info: String {
        switch self {
        case .shapes: return "Draw a rough shape and it snaps into a clean line, circle, rectangle or triangle."
        case .textBox: return "Tap anywhere to type. Also lets you move and resize photos and stickies."
        case .laser: return "Point things out while presenting. The trail fades away."
        case .tape: return "Cover answers with tape, then tap the tape to peek underneath."
        case .ruler: return "Show the ruler to draw perfectly straight lines."
        case .zoomBox: return "Write big in a magnified box; it lands small on the page."
        case .stickyNote: return "Add a coloured sticky note you can type on."
        case .photo: return "Place a photo from your library on the page."
        case .camera: return "Take a photo and put it straight on the page."
        case .emoji: return "Drop an emoji onto the page."
        case .stickers: return "Add a sticker: stars, arrows, check marks and more."
        case .addPage: return "Add a new page after this one."
        case .duplicatePage: return "Make a copy of this page."
        case .bookmark: return "Bookmark this page so it's easy to find."
        case .outline: return "Name this page in the notebook's outline."
        case .readOnly: return "Lock the notebook so you can read without marking it."
        case .viewMode: return "Switch between scrolling pages down or across."
        case .search: return "Find pages by outline titles and typed text."
        case .allNotes: return "Jump to another notebook."
        case .sharePDF: return "Export the whole notebook as a PDF."
        case .sharePNG: return "Share this page as an image."
        case .savePhoto: return "Save this page to your Photos."
        }
    }

    /// Items that select a drawing tool rather than run an action.
    var tool: EditorTool? {
        switch self {
        case .shapes: return .shapes
        case .textBox: return .text
        case .laser: return .laser
        case .tape: return .tape
        default: return nil
        }
    }

    /// Only makes sense in a paged notebook (not the endless canvas).
    var pagedOnly: Bool {
        switch self {
        case .zoomBox, .addPage, .duplicatePage, .bookmark, .outline, .viewMode, .search, .sharePNG, .savePhoto:
            return true
        default: return false
        }
    }
}

enum InkKind: String, Codable, CaseIterable, Identifiable {
    case ballpoint, fountain, pencil, monoline, brush, crayon
    var id: String { rawValue }
    /// The pen types offered for the pen tool.
    static let penKinds: [InkKind] = [.ballpoint, .fountain]

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
    // Added in 1.3 (nil = standard feel).
    var feel: InkFeel? = nil

    var uiColor: UIColor { UIColor(hex: colorHex).withAlphaComponent(opacity) }
    var inkFeel: InkFeel {
        get { feel ?? .standard }
        set { feel = newValue }
    }

    func sameLook(as other: PenPreset) -> Bool {
        kind == other.kind && colorHex == other.colorHex
            && abs(width - other.width) < 0.01 && abs(opacity - other.opacity) < 0.01
            && inkFeel == other.inkFeel
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
    @Published var tool: EditorTool = .pen {
        didSet { if oldValue != .eraser && oldValue != tool { lastDrawingTool = oldValue } }
    }
    /// The tool to go back to after a Pencil double-tap switched to the eraser.
    private var lastDrawingTool: EditorTool = .pen
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
    @Published var textColorHex: String { didSet { save() } }
    @Published var textSize: CGFloat { didSet { save() } }
    @Published var tapeColorHex: String { didSet { save() } }
    @Published var tapeWidth: CGFloat { didSet { save() } }
    @Published var tapeQuickSizes: [CGFloat] { didSet { save() } }
    @Published var toolbarItems: [ToolbarItemKind] { didSet { save() } }
    @Published var rulerActive = false

    static let defaultPenColors = ["#D32F2F", "#1F3BB3", "#2E6B1F"]
    static let defaultPenSizes: [CGFloat] = [1.5, 3, 6]
    static let defaultHighlighterColors = ["#F7E14A", "#A3D977", "#FF9EC4"]
    static let defaultHighlighterSizes: [CGFloat] = [10, 18, 30]
    static let defaultEraserSizes: [CGFloat] = [10, 25, 50]
    static let defaultTapeSizes: [CGFloat] = [18, 30, 46]

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
        // Added in 1.2.
        var palmMigrated: Bool?
        // Added in 1.3.
        var textColorHex: String?
        var textSize: CGFloat?
        var tapeColorHex: String?
        var tapeWidth: CGFloat?
        var toolbarItems: [String]?
        // Added in 1.5.
        var tapeQuickSizes: [CGFloat]?
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
            // 1.2: Apple Pencil only (palm rejection) is now the default.
            inputMode = (s.palmMigrated == nil && s.inputMode == .auto) ? .pencilOnly : s.inputMode
            penQuickColors = Self.three(s.penQuickColors, Self.defaultPenColors)
            penQuickSizes = Self.three(s.penQuickSizes, Self.defaultPenSizes)
            highlighterQuickColors = Self.three(s.highlighterQuickColors, Self.defaultHighlighterColors)
            highlighterQuickSizes = Self.three(s.highlighterQuickSizes, Self.defaultHighlighterSizes)
            eraserQuickSizes = Self.three(s.eraserQuickSizes, Self.defaultEraserSizes)
            textColorHex = s.textColorHex ?? "#1C1C1E"
            textSize = s.textSize ?? 22
            tapeColorHex = s.tapeColorHex ?? "#F2B8C6"
            tapeWidth = s.tapeWidth ?? 30
            tapeQuickSizes = Self.three(s.tapeQuickSizes, Self.defaultTapeSizes)
            toolbarItems = s.toolbarItems.map { $0.compactMap(ToolbarItemKind.init(rawValue:)) } ?? ToolbarItemKind.defaults
        } else {
            textColorHex = "#1C1C1E"
            textSize = 22
            tapeColorHex = "#F2B8C6"
            tapeWidth = 30
            toolbarItems = ToolbarItemKind.defaults
            tapeQuickSizes = Self.defaultTapeSizes
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
            inputMode = .pencilOnly
        }
        // 1.4: only ballpoint and fountain pens, and no pen-feel tuning.
        if !InkKind.penKinds.contains(pen.kind) { pen.kind = .ballpoint }
        pen.feel = nil
        loading = false
        save()
    }

    private func save() {
        guard !loading else { return }
        let s = Saved(pen: pen, highlighter: highlighter, eraserMode: eraserMode,
                      eraserWidth: eraserWidth, favorites: favorites,
                      recentColors: recentColors, inputMode: inputMode,
                      penQuickColors: penQuickColors, penQuickSizes: penQuickSizes,
                      highlighterQuickColors: highlighterQuickColors,
                      highlighterQuickSizes: highlighterQuickSizes,
                      eraserQuickSizes: eraserQuickSizes,
                      palmMigrated: true,
                      textColorHex: textColorHex, textSize: textSize,
                      tapeColorHex: tapeColorHex, tapeWidth: tapeWidth,
                      toolbarItems: toolbarItems.map { $0.rawValue },
                      tapeQuickSizes: tapeQuickSizes)
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
        case .shapes:
            return PKInkingTool(pen.kind == .brush || pen.kind == .crayon ? .pen : pen.kind.inkType,
                                color: pen.uiColor, width: pen.width)
        case .text, .laser, .tape:
            // These don't draw ink; the canvas is switched off while they're active.
            return PKInkingTool(.pen, color: pen.uiColor, width: pen.width)
        }
    }

    private static func three<T>(_ saved: [T]?, _ fallback: [T]) -> [T] {
        guard let saved, !saved.isEmpty else { return fallback }
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

    /// Apple Pencil double-tap: switch to the eraser, or back to the previous tool.
    func toggleEraser() {
        tool = tool == .eraser ? lastDrawingTool : .eraser
    }

    var toolTitle: String {
        switch tool {
        case .pen: return pen.kind.title
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .lasso: return "Lasso"
        case .shapes: return "Shapes"
        case .text: return "Text Box"
        case .laser: return "Laser Pointer"
        case .tape: return "Tape"
        }
    }

    /// The toolbar symbol for the current tool (pen shows its pen type).
    var toolSymbol: String { tool == .pen ? pen.kind.symbol : tool.symbol }

    func selectFavorite(_ preset: PenPreset) {
        pen = preset
        tool = .pen
    }
}
