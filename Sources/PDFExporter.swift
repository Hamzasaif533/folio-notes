import UIKit
import PencilKit

enum PDFExporter {
    private static func fileURL(_ title: String, fallback: String, ext: String) -> URL {
        let safeName = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent((safeName.isEmpty ? fallback : safeName) + "." + ext)
    }

    static func export(title: String, template: PageTemplate, paper: PaperColor, pages: [PageContent],
                       imageLoader: (String) -> UIImage?) -> URL? {
        let rect = CGRect(origin: .zero, size: TemplateRenderer.pageSize)
        let url = fileURL(title, fallback: "Notebook", ext: "pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: rect)
        do {
            try renderer.writePDF(to: url) { ctx in
                for page in pages {
                    // Pages with added space get a bigger PDF page.
                    ctx.beginPage(withBounds: CGRect(origin: .zero, size: page.extent.size), pageInfo: [:])
                    PageRenderer.draw(page, template: template, paper: paper, in: ctx.cgContext, imageLoader: imageLoader)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    /// One page as a PNG file, for sharing.
    static func exportPNG(title: String, image: UIImage) -> URL? {
        let url = fileURL(title, fallback: "Page", ext: "png")
        guard let data = image.pngData() else { return nil }
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    /// Infinite canvas: one page that fits everything that was written.
    static func exportCanvas(title: String, paper: PaperColor, drawing: PKDrawing, elements: [PageElement],
                             rect: CGRect, imageLoader: (String) -> UIImage?) -> URL? {
        let url = fileURL(title, fallback: "Canvas", ext: "pdf")
        let bounds = CGRect(origin: .zero, size: rect.size)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                let cg = ctx.cgContext
                cg.setFillColor(paper.uiColor.cgColor)
                cg.fill(bounds)
                cg.saveGState()
                cg.translateBy(x: -rect.minX, y: -rect.minY)
                ElementRenderer.draw(elements, overInk: false, in: cg, imageLoader: imageLoader)
                cg.restoreGState()
                var image = UIImage()
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    image = drawing.image(from: rect, scale: min(3, 6000 / max(rect.width, rect.height, 1)))
                }
                image.draw(in: bounds)
                cg.saveGState()
                cg.translateBy(x: -rect.minX, y: -rect.minY)
                ElementRenderer.draw(elements, overInk: true, in: cg, imageLoader: imageLoader)
                cg.restoreGState()
            }
            return url
        } catch {
            return nil
        }
    }
}
