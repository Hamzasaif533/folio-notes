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
    static var penTest: Bool { args.contains("-FolioPenTest") }
    static var pdfTest: Bool { args.contains("-FolioPDFTest") }
    static var fountain: Bool { args.contains("-FolioFountain") }
    static var tipRound: Bool { args.contains("-FolioTipRound") }
    static var tipFlat: Bool { args.contains("-FolioTipFlat") }
    static var settings: Bool { args.contains("-FolioSettings") }
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
    static let penTestTitle = "Pen Test"
    static let pdfTestTitle = "PDF Test"

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
        let penTest = store.createNotebook(title: penTestTitle, folderId: nil,
                                           cover: CoverStyle(paletteIndex: 2, pattern: .plain),
                                           template: .blank, paper: .white)
        store.saveDrawing(penTestDrawing(), notebookId: penTest.id, pageId: penTest.pages[0])
        store.saveElements(penTestLabels(), notebookId: penTest.id, pageId: penTest.pages[0])
        if let url = samplePDF() {
            _ = store.importPDFNotebook(title: pdfTestTitle, folderId: nil, url: url)
        }
        let board = store.createNotebook(title: canvasTitle, folderId: projects.id,
                                         cover: CoverStyle(paletteIndex: 7, pattern: .dots),
                                         template: .dotted, paper: .white, kind: .canvas)
        // Strokes around the middle of the board, where the canvas opens.
        let mid = CGAffineTransform(translationX: 10000 - 360, y: 10000 - 400)
        store.saveDrawing(sampleDrawing().transformed(using: mid), notebookId: board.id, pageId: board.pages[0])
    }

    // MARK: Fountain pen test page

    private static let penRows: [(String, Double)] = [("Round", 0), ("25%", 0.25), ("Middle (default)", 0.5),
                                                       ("75%", 0.75), ("Flat", 1)]
    private static let rowTop: CGFloat = 150
    private static let rowGap: CGFloat = 160

    /// A fountain-pen stroke along `pts`, written like a real Pencil: lighter for the first
    /// moments after touching down, then at `pressure` (which can depend on direction).
    static func fountainStroke(_ pts: [CGPoint], flatness: Double, width: CGFloat, hex: String,
                               liftSpeed: CGFloat, pressure: (CGFloat) -> CGFloat) -> InkStroke {
        var feel = InkKind.fountain.defaultFeel
        feel.tipFlatness = flatness
        let pen = InkPen(style: .oval, colorHex: hex, width: width, feel: feel)
        var out: [InkPoint] = []
        for (i, p) in pts.enumerated() {
            let q = i > 0 ? pts[i - 1] : (pts.count > 1 ? CGPoint(x: 2 * p.x - pts[1].x, y: 2 * p.y - pts[1].y) : p)
            let dir = atan2(p.y - q.y, p.x - q.x)
            let ramp = min(1, CGFloat(i) / max(1, CGFloat(pts.count) * 0.1))
            out.append(InkPoint(p, w: pen.width(pressure: pressure(dir) * (0.45 + 0.55 * ramp), direction: dir)))
        }
        return InkStroke(style: .oval, color: InkColor(hex: hex), points: pen.liftTapered(out, speed: liftSpeed),
                         tip: pen.tip)
    }

    private static func line(from a: CGPoint, to b: CGPoint, steps: Int = 40) -> [CGPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    /// Loops like joined-up handwriting (pressing harder going down, lighter going up).
    private static func loops(at o: CGPoint, count: Int, size r: CGFloat) -> [CGPoint] {
        let n = count * 40
        return (0...n).map { i in
            let a = CGFloat(i) / 40 * 2 * .pi
            return CGPoint(x: o.x + a * r * 0.42 - sin(a) * r * 0.55, y: o.y - (1 - cos(a)) * r)
        }
    }

    /// Each row is one Tip Flatness: | and — at light, normal and hard pressure (like a pressure test
    /// written by hand), then the same curve lifted quickly (pointed tail) and stopped before lifting.
    static func penTestDrawing() -> InkDrawing {
        var strokes: [InkStroke] = []
        let red = "#E53935"
        for (row, spec) in penRows.enumerated() {
            let y = rowTop + CGFloat(row) * rowGap + 40
            for (col, p) in [CGFloat(0.12), 0.5, 1].enumerated() {
                let x = 40 + CGFloat(col) * 105
                strokes.append(fountainStroke(line(from: CGPoint(x: x, y: y), to: CGPoint(x: x + 4, y: y + 70)),
                                              flatness: spec.1, width: 6, hex: red, liftSpeed: 0) { _ in p })
                strokes.append(fountainStroke(line(from: CGPoint(x: x + 22, y: y + 30), to: CGPoint(x: x + 82, y: y + 30)),
                                              flatness: spec.1, width: 6, hex: red, liftSpeed: 0) { _ in p })
            }
            let hard: (CGFloat) -> CGFloat = { dir in 0.45 + 0.4 * sin(dir) } // harder going down
            strokes.append(fountainStroke(loops(at: CGPoint(x: 360, y: y + 62), count: 2, size: 26),
                                          flatness: spec.1, width: 6, hex: red, liftSpeed: 1600, pressure: hard))
            strokes.append(fountainStroke(loops(at: CGPoint(x: 560, y: y + 62), count: 2, size: 26),
                                          flatness: spec.1, width: 6, hex: red, liftSpeed: 0, pressure: hard))
        }
        // Big, to check the edges are smooth.
        let y = rowTop + CGFloat(penRows.count) * rowGap + 30
        strokes.append(fountainStroke(loops(at: CGPoint(x: 60, y: y + 90), count: 3, size: 70),
                                      flatness: 0.5, width: 18, hex: "#1F3BB3", liftSpeed: 1600) { dir in 0.45 + 0.4 * sin(dir) })
        return InkDrawing(strokes: strokes)
    }

    static func penTestLabels() -> [PageElement] {
        var out: [PageElement] = []
        let heads = [("Light", 40), ("Normal", 145), ("Hard", 250), ("Quick lift", 380), ("Stop, then lift", 580)]
        for (t, x) in heads {
            out.append(PageElement(kind: .text, x: CGFloat(x), y: 110, w: 190, h: 30, text: t, colorHex: "#6B6B70", fontSize: 18))
        }
        for (row, spec) in penRows.enumerated() {
            out.append(PageElement(kind: .text, x: 40, y: rowTop + CGFloat(row) * rowGap + 2, w: 400, h: 30,
                                   text: "Tip Flatness: " + spec.0, colorHex: "#1C1C1E", fontSize: 18))
        }
        return out
    }

    /// A small PDF (a portrait page and a landscape page), to check imported PDFs.
    static func samplePDF() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Folio PDF Test.pdf")
        let portrait = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: portrait)
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 30), .foregroundColor: UIColor.black]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.darkGray]
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                ("PDF Test: page 1" as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: title)
                for i in 0..<30 {
                    ("Line \(i + 1): small text stays sharp when you zoom in on a PDF page." as NSString)
                        .draw(at: CGPoint(x: 50, y: 110 + CGFloat(i) * 20), withAttributes: body)
                }
                let c = ctx.cgContext
                c.setStrokeColor(UIColor.systemBlue.cgColor)
                c.setLineWidth(3)
                c.strokeEllipse(in: CGRect(x: 380, y: 560, width: 180, height: 180))
                c.setStrokeColor(UIColor.systemRed.cgColor)
                c.stroke(CGRect(x: 2, y: 2, width: 608, height: 788))
                ctx.beginPage(withBounds: CGRect(x: 0, y: 0, width: 792, height: 612), pageInfo: [:])
                ("PDF Test: page 2 (landscape)" as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: title)
                ctx.cgContext.setStrokeColor(UIColor.systemGreen.cgColor)
                ctx.cgContext.setLineWidth(3)
                ctx.cgContext.stroke(CGRect(x: 2, y: 2, width: 788, height: 608))
            }
            return url
        } catch {
            return nil
        }
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
            (.ballpoint, "#000000", 3), (.oval, "#1F3BB3", 4), (.ballpoint, "#D32F2F", 3),
            (.ballpoint, "#3C3C43", 4), (.oval, "#2E6B1F", 3), (.highlighter, "#F7E14A", 22)
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
        let pen = InkPen(style: style, colorHex: hex, width: width,
                         feel: style == .oval ? InkKind.fountain.defaultFeel : .standard)
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
