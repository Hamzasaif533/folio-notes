import Foundation
import PencilKit
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
    static let firstTitle = "Lecture Notes"

    @MainActor
    static func seedIfNeeded(_ store: LibraryStore) {
        guard enabled, store.notebooks.isEmpty else { return }
        let uni = store.createFolder(name: "University", colorIndex: 0, icon: "graduationcap.fill")
        let personal = store.createFolder(name: "Personal", colorIndex: 2, icon: "heart.fill")
        let projects = store.createFolder(name: "Projects", colorIndex: 4, icon: "briefcase.fill")

        let specs: [(String, UUID?, Int, CoverPattern, PageTemplate)] = [
            ("Radio Receivers", uni.id, 1, .waves, .ruled),
            ("Aircraft Structures", uni.id, 6, .plain, .cornell),
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
                store.touch(nb.id)
            }
        }
    }

    /// A few strokes in different pens and colours, to check ink visibility.
    static func sampleDrawing() -> PKDrawing {
        let rows: [(PKInkingTool.InkType, String, CGFloat)] = [
            (.pen, "#000000", 3), (.fountainPen, "#1F3BB3", 4), (.pen, "#D32F2F", 3),
            (.pencil, "#3C3C43", 4), (.monoline, "#2E6B1F", 3), (.marker, "#F7E14A", 22)
        ]
        var strokes: [PKStroke] = []
        for (i, row) in rows.enumerated() {
            let y = 230 + CGFloat(i) * 90
            strokes.append(wave(ink: PKInk(row.0, color: UIColor(hex: row.1)), width: row.2,
                                from: CGPoint(x: 80, y: y), length: 560, amplitude: 18))
        }
        return PKDrawing(strokes: strokes)
    }

    static func wave(ink: PKInk, width: CGFloat, from start: CGPoint, length: CGFloat, amplitude: CGFloat) -> PKStroke {
        var points: [PKStrokePoint] = []
        let n = 90
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            points.append(PKStrokePoint(location: CGPoint(x: start.x + t * length,
                                                          y: start.y + sin(t * .pi * 4) * amplitude),
                                        timeOffset: TimeInterval(t),
                                        size: CGSize(width: width, height: width),
                                        opacity: 1,
                                        force: 0.4 + sin(t * .pi),
                                        azimuth: 0,
                                        altitude: .pi / 2))
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()),
                        transform: .identity, mask: nil)
    }
}
