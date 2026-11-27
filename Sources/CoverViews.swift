import SwiftUI

/// A notebook cover: gradient, subtle pattern, a darker spine and a title label.
struct NotebookCoverView: View {
    let cover: CoverStyle
    var title: String? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pal = Theme.coverPalettes[abs(cover.paletteIndex) % Theme.coverPalettes.count]
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: pal.0), Color(hex: pal.1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                CoverPatternView(pattern: cover.pattern)
                    .opacity(0.16)
                LinearGradient(colors: [.black.opacity(0.32), .black.opacity(0.05)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: w * 0.09, height: h)
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: h)
                    .offset(x: w * 0.09)
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: max(8, w * 0.085), weight: .semibold, design: .serif))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, w * 0.05)
                        .padding(.vertical, w * 0.035)
                        .frame(width: w * 0.66)
                        .background(RoundedRectangle(cornerRadius: w * 0.025).fill(Color(hex: "#FBF8F2")))
                        .position(x: w * 0.545, y: h * 0.3)
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: w * 0.025,
                                              bottomLeadingRadius: w * 0.025,
                                              bottomTrailingRadius: w * 0.07,
                                              topTrailingRadius: w * 0.07))
        }
    }
}

struct CoverPatternView: View {
    let pattern: CoverPattern

    var body: some View {
        Canvas { ctx, size in
            let white = GraphicsContext.Shading.color(.white)
            let unit = max(size.width / 14, 4)
            switch pattern {
            case .plain:
                break
            case .stripes:
                var p = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += unit * 1.4
                }
                ctx.stroke(p, with: white, lineWidth: unit * 0.4)
            case .dots:
                var y = unit / 2
                var row = 0
                while y < size.height {
                    var x = row % 2 == 0 ? unit / 2 : unit
                    while x < size.width {
                        let r = unit * 0.16
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: white)
                        x += unit
                    }
                    y += unit
                    row += 1
                }
            case .grid:
                var p = Path()
                var x: CGFloat = 0
                while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += unit * 1.2 }
                var y: CGFloat = 0
                while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += unit * 1.2 }
                ctx.stroke(p, with: white, lineWidth: max(0.5, unit * 0.08))
            case .waves:
                var p = Path()
                var y: CGFloat = unit
                while y < size.height + unit {
                    p.move(to: CGPoint(x: 0, y: y))
                    var x: CGFloat = 0
                    while x <= size.width {
                        p.addLine(to: CGPoint(x: x, y: y + sin(x / unit * 1.2) * unit * 0.3))
                        x += 2
                    }
                    y += unit * 1.1
                }
                ctx.stroke(p, with: white, lineWidth: max(0.6, unit * 0.12))
            case .linen:
                var p = Path()
                let step = max(2, unit * 0.3)
                var x: CGFloat = 0
                while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.stroke(p, with: white, lineWidth: 0.35)
            }
        }
    }
}

/// Folder shape with a tab on the top left.
struct FolderShape: Shape {
    func path(in r: CGRect) -> Path {
        let tabW = r.width * 0.4
        let tabH: CGFloat = 14
        let rad: CGFloat = 14
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + rad, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tabW - 12, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + tabW + 10, y: r.minY + tabH),
                       control: CGPoint(x: r.minX + tabW, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY + tabH))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + tabH + rad), control: CGPoint(x: r.maxX, y: r.minY + tabH))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A folder card: coloured folder with the first notebooks peeking out of it.
struct FolderCard: View {
    let folder: Folder
    let notebooks: [Notebook]

    var body: some View {
        let base = Color(hex: Theme.folderColors[abs(folder.colorIndex) % Theme.folderColors.count])
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                FolderShape()
                    .fill(base.opacity(0.55))
                HStack(spacing: -22) {
                    ForEach(Array(notebooks.prefix(3).enumerated()), id: \.element.id) { i, nb in
                        NotebookCoverView(cover: nb.cover)
                            .frame(width: 54, height: 72)
                            .rotationEffect(.degrees(Double(i - 1) * 7))
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                    if notebooks.isEmpty {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 70, height: 64)
                            .rotationEffect(.degrees(-4))
                    }
                }
                .offset(y: -42)
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [base, base.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 92)
                    .overlay(alignment: .bottomLeading) {
                        HStack {
                            Image(systemName: folder.icon)
                                .font(.system(size: 22, weight: .semibold))
                            Spacer()
                            Text("\(notebooks.count)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.25)))
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: -1)
            }
            .frame(height: 150)
            Text(folder.name)
                .font(.headline)
                .lineLimit(1)
            Text(notebooks.count == 1 ? "1 notebook" : "\(notebooks.count) notebooks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct NotebookTile: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NotebookCoverView(cover: notebook.cover, title: notebook.title)
                .aspectRatio(0.76, contentMode: .fit)
                .shadow(color: .black.opacity(0.18), radius: 6, x: 2, y: 4)
            Text(notebook.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.top, 4)
            Text(notebook.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct NewNotebookTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.5)))
                .aspectRatio(0.76, contentMode: .fit)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 30, weight: .light))
                        Text("New Notebook")
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
            Text(" ").font(.subheadline).padding(.top, 4)
            Text(" ").font(.caption)
        }
        .contentShape(Rectangle())
    }
}

/// Small page preview used when picking a template.
struct TemplateThumbnail: View {
    let template: PageTemplate
    let paper: PaperColor

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / TemplateRenderer.pageSize.width
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(uiColor: paper.uiColor)))
            for layer in TemplateRenderer.layers(template: template, paper: paper, scale: s) {
                let path = Path(layer.path)
                if layer.filled {
                    ctx.fill(path, with: .color(Color(uiColor: layer.color)))
                } else {
                    ctx.stroke(path, with: .color(Color(uiColor: layer.color)), lineWidth: max(0.5, layer.lineWidth))
                }
            }
        }
        .aspectRatio(TemplateRenderer.pageSize.width / TemplateRenderer.pageSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }
}
