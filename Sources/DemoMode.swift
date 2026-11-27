import Foundation
import UIKit

/// Only active when the app is launched with -FolioDemo (used by the automated
/// simulator screenshots in the cloud build). Normal launches never touch this.
enum DemoMode {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    static var enabled: Bool { args.contains("-FolioDemo") }
    static var openFirst: Bool { args.contains("-FolioOpenFirst") }
    static var focus: Bool { args.contains("-FolioFocus") }
    static var showPen: Bool { args.contains("-FolioShowPen") }
    static var showFolders: Bool { args.contains("-FolioShowFolders") }
    static var squeeze: Bool { args.contains("-FolioSqueeze") }
    static var sidebar: Bool { args.contains("-FolioSidebar") }
    static var openCanvas: Bool { args.contains("-FolioOpenCanvas") }
    static var showNew: Bool { args.contains("-FolioShowNew") }
    static var openFolder: Bool { args.contains("-FolioOpenFolder") }
    static var showAdd: Bool { args.contains("-FolioShowAdd") }
    static var showMore: Bool { args.contains("-FolioShowMore") }
    static var customize: Bool { args.contains("-FolioCustomize") }
    static var zoomBox: Bool { args.contains("-FolioZoomBox") }
    static var horizontal: Bool { args.contains("-FolioHorizontal") }
    static var allNotes: Bool { args.contains("-FolioAllNotes") }
    static var textTool: Bool { args.contains("-FolioTextTool") }
    static var editColor: Bool { args.contains("-FolioEditColor") }
    static var selectMode: Bool { args.contains("-FolioSelect") }
    static var pageMenu: Bool { args.contains("-FolioPageMenu") }
    static var zoomMenu: Bool { args.contains("-FolioZoomMenu") }
    static var split: Bool { args.contains("-FolioSplit") }
    static var addSpace: Bool { args.contains("-FolioAddSpace") }
    static var tapeTool: Bool { args.contains("-FolioTapeTool") }
    static var colorsDock: ToolbarDock? {
        if args.contains("-FolioColorsBottom") { return .bottom }
        if args.contains("-FolioColorsRight") { return .right }
        return nil
    }
    static var dock: ToolbarDock? {
        if args.contains("-FolioDockLeft") { return .left }
        if args.contains("-FolioDockBottom") { return .bottom }
        return nil
    }
    static let firstTitle = "Lecture Notes"
    static let canvasTitle = "Whiteboard"

    @MainActor
    static func seedIfNeeded(_ store: LibraryStore) {
        guard enabled, store.notebooks.isEmpty else { return }
        let uni = store.createFolder(name: "University", colorIndex: 0, icon: "graduationcap.fill")
        let personal = store.createFolder(name: "Personal", colorIndex: 2, icon: "heart.fill")
        let projects = store.createFolder(name: "Projects", colorIndex: 4, icon: "briefcase.fill")
        let year2 = store.createFolder(name: "Year 2", colorIndex: 1, icon: "books.vertical.fill", parentId: uni.id)
        _ = store.createFolder(name: "Labs", colorIndex: 3, icon: "flask.fill", parentId: uni.id)
        // Open University in the sidebar tree so its subfolders show.
        UserDefaults.standard.set(uni.id.uuidString, forKey: "folio.openFolders")

        let specs: [(String, UUID?, Int, CoverPattern, PageTemplate)] = [
            ("Radio Receivers", uni.id, 1, .waves, .ruled),
            ("Aircraft Structures", year2.id, 6, .plain, .cornell),
            ("Journal", personal.id, 5, .dots, .dotted),
            ("Sketchbook", personal.id, 8, .linen, .blank),
            ("App Ideas", projects.id, 9, .grid, .grid),
            ("Meeting Notes", nil, 3, .stripes, .narrowRuled),
            (firstTitle, nil, 0, .plain, .grid)
        ]
        for (title, folder, palette, pattern, template) in specs {
            let nb = store.createNotebook(title: title, folderId: folder,
                                          cover: CoverStyle(paletteIndex: palette, pattern: pattern),
                                          template: template, paper: .white)
            if title == firstTitle || title == "Journal" { store.setStarred(nb.id, true) }
            if title == firstTitle {
                store.saveDrawing(sampleDrawing(), notebookId: nb.id, pageId: nb.pages[0])
                store.saveElements(sampleObjects(), notebookId: nb.id, pageId: nb.pages[0])
                store.toggleBookmark(notebookId: nb.id, pageId: nb.pages[0])
                store.setOutline(notebookId: nb.id, pageId: nb.pages[0], title: "Waves")
                if let p2 = store.insertPage(notebookId: nb.id, at: 1) {
                    store.saveDrawing(sampleDrawing(), notebookId: nb.id, pageId: p2)
                }
                _ = store.insertPage(notebookId: nb.id, at: 2)
                store.touch(nb.id)
            }
        }
        let board = store.createNotebook(title: canvasTitle, folderId: projects.id,
                                         cover: CoverStyle(paletteIndex: 7, pattern: .dots),
                                         template: .dotted, paper: .white, kind: .canvas)
        // Strokes around the middle of the board, where the canvas opens.
        let mid = CGAffineTransform(translationX: 10000 - 360, y: 10000 - 400)
        store.saveDrawing(sampleDrawing().transformed(using: mid), notebookId: board.id, pageId: board.pages[0])
    }

    /// A text box, sticky note, tape strip, sticker and emoji for the screenshots.
    static func sampleObjects() -> [PageElement] {
        [PageElement(kind: .text, x: 80, y: 90, w: 520, h: 56, text: "Lecture 4: Waves", colorHex: "#1F3BB3", fontSize: 36),
         PageElement(kind: .emoji, x: 640, y: 80, w: 80, h: 80, colorHex: "#F5B700", symbol: "star.fill"),
         PageElement(kind: .sticky, x: 500, y: 760, w: 230, h: 210, text: "Exam Friday!\nReview chapter 3",
                     colorHex: "#FFE680", fontSize: 26),
         PageElement(kind: .emoji, x: 120, y: 800, w: 90, h: 90, text: "💡"),
         PageElement(kind: .tape, x: 360, y: 390, w: 300, h: 34, colorHex: "#FFB8D1")]
    }

    /// A few strokes in different pens and colours, to check ink visibility.
    static func sampleDrawing() -> InkDrawing {
        let rows: [(InkStyle, String, CGFloat)] = [
            (.ballpoint, "#000000", 3), (.fountain, "#1F3BB3", 4), (.ballpoint, "#D32F2F", 3),
            (.ballpoint, "#3C3C43", 4), (.fountain, "#2E6B1F", 3), (.highlighter, "#F7E14A", 22)
        ]
        var strokes: [InkStroke] = []
        for (i, row) in rows.enumerated() {
            let y = 230 + CGFloat(i) * 90
            strokes.append(wave(style: row.0, hex: row.1, width: row.2,
                                from: CGPoint(x: 80, y: y), length: 560, amplitude: 18))
        }
        return InkDrawing(strokes: strokes)
    }

    static func wave(style: InkStyle, hex: String, width: CGFloat, from start: CGPoint,
                     length: CGFloat, amplitude: CGFloat) -> InkStroke {
        let pen = InkPen(style: style, colorHex: hex, width: width)
        var points: [InkPoint] = []
        var prev: CGPoint?
        let n = 90
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let p = CGPoint(x: start.x + t * length, y: start.y + sin(t * .pi * 4) * amplitude)
            let dir = prev.map { atan2(p.y - $0.y, p.x - $0.x) } ?? 0
            prev = p
            points.append(InkPoint(p, w: pen.width(pressure: 0.3 + 0.6 * sin(t * .pi), direction: dir)))
        }
        return InkStroke(style: style, color: InkColor(hex: hex), points: points, tip: pen.tip)
    }
}
