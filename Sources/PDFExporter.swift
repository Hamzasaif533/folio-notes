import UIKit
import PencilKit

enum PDFExporter {
    static func export(title: String, template: PageTemplate, paper: PaperColor, drawings: [PKDrawing]) -> URL? {
        let size = TemplateRenderer.pageSize
        let rect = CGRect(origin: .zero, size: size)
        let safeName = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent((safeName.isEmpty ? "Notebook" : safeName) + ".pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: rect)
        do {
            try renderer.writePDF(to: url) { ctx in
                for drawing in drawings {
                    ctx.beginPage()
                    TemplateRenderer.draw(template: template, paper: paper, in: ctx.cgContext)
                    var image = UIImage()
                    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                        image = drawing.image(from: rect, scale: 3)
                    }
                    image.draw(in: rect)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    /// Infinite canvas: one page that fits everything that was written.
    static func exportCanvas(title: String, paper: PaperColor, drawing: PKDrawing, rect: CGRect) -> URL? {
        let safeName = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent((safeName.isEmpty ? "Canvas" : safeName) + ".pdf")
        let bounds = CGRect(origin: .zero, size: rect.size)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                ctx.cgContext.setFillColor(paper.uiColor.cgColor)
                ctx.cgContext.fill(bounds)
                var image = UIImage()
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    image = drawing.image(from: rect, scale: min(3, 6000 / max(rect.width, rect.height, 1)))
                }
                image.draw(in: bounds)
            }
            return url
        } catch {
            return nil
        }
    }
}
