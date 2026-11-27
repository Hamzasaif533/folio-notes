import UIKit

/// Builds the page background (lines, grid, dots) as vector paths so it can be
/// re-rendered sharply at any zoom level, in thumbnails and in PDF export.
enum TemplateRenderer {
    static let pageSize = CGSize(width: 800, height: 1131)

    struct Layer {
        var path: CGPath
        var color: UIColor
        var lineWidth: CGFloat
        var filled: Bool
    }

    static func layers(template: PageTemplate, paper: PaperColor, scale z: CGFloat = 1,
                       size: CGSize = pageSize, spacing: CGFloat = 1) -> [Layer] {
        // Line spacing: 1 is normal; kept sensible so a page never fills with lines.
        let sp = min(max(spacing, 0.5), 2.5)
        let w = size.width
        let h = size.height
        var result: [Layer] = []

        func add(_ path: CGMutablePath, color: UIColor, width: CGFloat, filled: Bool = false) {
            var t = CGAffineTransform(scaleX: z, y: z)
            if let scaled = path.copy(using: &t) {
                result.append(Layer(path: scaled, color: color, lineWidth: max(0.4, width * z), filled: filled))
            }
        }

        func ruled(spacing: CGFloat, top: CGFloat, bottom: CGFloat, fromX: CGFloat = 0) {
            let p = CGMutablePath()
            var y = top
            while y <= h - bottom {
                p.move(to: CGPoint(x: fromX, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
                y += spacing
            }
            add(p, color: paper.lineColor, width: 1)
        }

        func vertical(x: CGFloat, from y0: CGFloat, to y1: CGFloat, color: UIColor, width: CGFloat) {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: y0))
            p.addLine(to: CGPoint(x: x, y: y1))
            add(p, color: color, width: width)
        }

        func horizontal(y: CGFloat, color: UIColor, width: CGFloat) {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: w, y: y))
            add(p, color: color, width: width)
        }

        switch template {
        case .blank:
            break
        case .ruled:
            ruled(spacing: 32 * sp, top: 120, bottom: 50)
            vertical(x: 96, from: 0, to: h, color: paper.marginColor, width: 1.2)
        case .narrowRuled:
            ruled(spacing: 24 * sp, top: 100, bottom: 40)
            vertical(x: 80, from: 0, to: h, color: paper.marginColor, width: 1.2)
        case .grid:
            let p = CGMutablePath()
            let step: CGFloat = 25 * sp
            var x: CGFloat = step
            while x < w { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)); x += step }
            var y: CGFloat = step
            while y < h { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)); y += step }
            add(p, color: paper.lineColor.withAlphaComponent(0.75), width: 0.7)
        case .dotted:
            let p = CGMutablePath()
            let step: CGFloat = 25 * sp
            let r: CGFloat = 1.5
            var y: CGFloat = step
            while y < h {
                var x: CGFloat = step
                while x < w {
                    p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += step
                }
                y += step
            }
            add(p, color: paper.lineColor, width: 0, filled: true)
        case .cornell:
            let header: CGFloat = 130
            let summary: CGFloat = h - 220
            ruled(spacing: 32 * sp, top: header + 32 * sp, bottom: 230, fromX: 220)
            horizontal(y: header, color: paper.lineColor, width: 1.6)
            horizontal(y: summary, color: paper.lineColor, width: 1.6)
            vertical(x: 220, from: header, to: summary, color: paper.lineColor, width: 1.6)
        }
        return result
    }

    /// Draws the template into a Core Graphics context (used by PDF export).
    static func draw(template: PageTemplate, paper: PaperColor, in ctx: CGContext, size: CGSize = pageSize,
                     spacing: CGFloat = 1) {
        ctx.setFillColor(paper.uiColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        for layer in layers(template: template, paper: paper, size: size, spacing: spacing) {
            ctx.addPath(layer.path)
            if layer.filled {
                ctx.setFillColor(layer.color.cgColor)
                ctx.fillPath()
            } else {
                ctx.setStrokeColor(layer.color.cgColor)
                ctx.setLineWidth(layer.lineWidth)
                ctx.strokePath()
            }
        }
    }
}
