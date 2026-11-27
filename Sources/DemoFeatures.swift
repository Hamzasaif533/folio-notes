import UIKit

/// Demo content for the 1.12 screenshots (only used with -FolioDemo).
extension DemoMode {
    static var features: Bool { ProcessInfo.processInfo.arguments.contains("-FolioFeatures") }
    static var darkPDF: Bool { ProcessInfo.processInfo.arguments.contains("-FolioDarkPDF") }
    static var calculator: Bool { ProcessInfo.processInfo.arguments.contains("-FolioCalc") }
    static var browser: Bool { ProcessInfo.processInfo.arguments.contains("-FolioBrowser") }
    static var paperSheet: Bool { ProcessInfo.processInfo.arguments.contains("-FolioPaper") }
    static let featuresTitle = "New in 1.12"

    /// A notebook with a 16:9 page, an A5 page and an A4 page, wide line spacing,
    /// crossing highlights and a cropped picture; plus a photo cover and a custom colour cover.
    @MainActor
    static func seedFeatures(_ store: LibraryStore) {
        guard store.notebooks.first(where: { $0.title == featuresTitle }) == nil else { return }
        var cover = CoverStyle(paletteIndex: 0, pattern: .plain)
        if let photo = CoverPhotos.save(samplePicture(size: CGSize(width: 666, height: 900))) { cover.photo = photo }
        let nb = store.createNotebook(title: featuresTitle, folderId: nil, cover: cover, template: .ruled, paper: .white,
                                      format: PageFormat(size: .widescreen, landscape: true), lineSpacing: 1.5)
        // Page 2 is A5, page 3 the standard A4 (new pages take the size chosen at the time).
        if var n = store.notebook(nb.id) {
            n.pageFormat = PageFormat(size: .a5)
            store.updateNotebook(n)
        }
        let a5 = store.insertPage(notebookId: nb.id, at: 1)
        if var n = store.notebook(nb.id) {
            n.pageFormat = nil
            store.updateNotebook(n)
        }
        _ = store.insertPage(notebookId: nb.id, at: 2)

        store.saveDrawing(InkDrawing(strokes: highlightTest()), notebookId: nb.id, pageId: nb.pages[0])
        store.saveElements([
            label("Same colour crossing: no darker overlap", x: 80, y: 40),
            label("Two colours crossing still mix", x: 640, y: 40),
            label("Straight highlight", x: 80, y: 470)
        ], notebookId: nb.id, pageId: nb.pages[0])

        if let a5, let file = store.saveImageAsset(samplePicture(size: CGSize(width: 900, height: 600)), notebookId: nb.id) {
            var img = PageElement(kind: .image, x: 80, y: 150, w: 400, h: 267, imageFile: file)
            img.setCrop(CGRect(x: 0.3, y: 0.1, width: 0.4, height: 0.8), imageSize: CGSize(width: 900, height: 600))
            img.x = 80
            img.y = 150
            store.saveElements([label("Cropped picture", x: 80, y: 80), img], notebookId: nb.id, pageId: a5)
        }
        store.touch(nb.id)

        if var meeting = store.notebooks.first(where: { $0.title == "Meeting Notes" }) {
            meeting.cover.customHex = "#7B3FE4"
            store.updateNotebook(meeting)
        }
        // Black ink on the PDF, to check it turns light on a dark page.
        if let pdf = store.notebooks.first(where: { $0.title == pdfTestTitle }), let first = pdf.pages.first {
            var d = store.loadDrawing(notebookId: pdf.id, pageId: first)
            if d.strokes.isEmpty {
                d.strokes.append(penLine([CGPoint(x: 90, y: 1000), CGPoint(x: 300, y: 960), CGPoint(x: 520, y: 1010),
                                          CGPoint(x: 700, y: 970)], hex: "#000000"))
                d.strokes.append(penLine([CGPoint(x: 90, y: 1060), CGPoint(x: 400, y: 1040), CGPoint(x: 700, y: 1060)],
                                         hex: "#2F6FDE"))
                store.saveDrawing(d, notebookId: pdf.id, pageId: first)
            }
        }
    }

    private static func label(_ text: String, x: CGFloat, y: CGFloat) -> PageElement {
        PageElement(kind: .text, x: x, y: y, w: 440, h: 34, text: text, colorHex: "#3A3A3C", fontSize: 20)
    }

    private static func penLine(_ pts: [CGPoint], hex: String) -> InkStroke {
        var dense: [InkPoint] = []
        for i in 0..<(pts.count - 1) {
            for k in 0..<20 {
                let t = CGFloat(k) / 20
                dense.append(InkPoint(CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * t,
                                              y: pts[i].y + (pts[i + 1].y - pts[i].y) * t), w: 4))
            }
        }
        dense.append(InkPoint(pts[pts.count - 1], w: 4))
        return InkStroke(style: .ballpoint, color: InkColor(hex: hex), points: dense)
    }

    private static func highlight(_ pts: [CGPoint], hex: String, width: CGFloat = 26) -> InkStroke {
        var dense: [InkPoint] = []
        for i in 0..<(pts.count - 1) {
            for k in 0..<16 {
                let t = CGFloat(k) / 16
                dense.append(InkPoint(CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * t,
                                              y: pts[i].y + (pts[i + 1].y - pts[i].y) * t), w: width))
            }
        }
        dense.append(InkPoint(pts[pts.count - 1], w: width))
        return InkStroke(style: .highlighter, color: InkColor(hex: hex), points: dense)
    }

    private static func highlightTest() -> [InkStroke] {
        let yellow = "#F7E14A", pink = "#FF7EB6"
        return [
            // One stroke going back over itself, and two more crossing it.
            highlight([CGPoint(x: 90, y: 140), CGPoint(x: 480, y: 140), CGPoint(x: 120, y: 160), CGPoint(x: 470, y: 175)], hex: yellow),
            highlight([CGPoint(x: 120, y: 90), CGPoint(x: 420, y: 330)], hex: yellow),
            highlight([CGPoint(x: 140, y: 330), CGPoint(x: 440, y: 100)], hex: yellow),
            highlight([CGPoint(x: 660, y: 150), CGPoint(x: 1040, y: 150)], hex: yellow),
            highlight([CGPoint(x: 700, y: 90), CGPoint(x: 1000, y: 330)], hex: pink),
            highlight([CGPoint(x: 90, y: 540), CGPoint(x: 700, y: 540)], hex: yellow)
        ]
    }

    /// A made-up picture: sky, sun, hills.
    static func samplePicture(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { r in
            let ctx = r.cgContext
            let colors = [UIColor(hex: "#2B5876").cgColor, UIColor(hex: "#F09819").cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor(hex: "#FFE07A").setFill()
            let sun = min(size.width, size.height) * 0.18
            ctx.fillEllipse(in: CGRect(x: size.width * 0.5 - sun, y: size.height * 0.42 - sun, width: sun * 2, height: sun * 2))
            UIColor(hex: "#2E6B3F").setFill()
            let hills = UIBezierPath()
            hills.move(to: CGPoint(x: 0, y: size.height))
            hills.addLine(to: CGPoint(x: 0, y: size.height * 0.7))
            hills.addQuadCurve(to: CGPoint(x: size.width * 0.55, y: size.height * 0.68),
                               controlPoint: CGPoint(x: size.width * 0.25, y: size.height * 0.5))
            hills.addQuadCurve(to: CGPoint(x: size.width, y: size.height * 0.62),
                               controlPoint: CGPoint(x: size.width * 0.8, y: size.height * 0.8))
            hills.addLine(to: CGPoint(x: size.width, y: size.height))
            hills.close()
            hills.fill()
        }
    }
}
