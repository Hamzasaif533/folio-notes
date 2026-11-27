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
                // Coloured spine with a soft fold shadow.
                Rectangle()
                    .fill(Color(hex: pal.2))
                    .frame(width: w * 0.1, height: h)
                LinearGradient(colors: [.black.opacity(0.18), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: w * 0.05, height: h)
                    .offset(x: w * 0.1)
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
            .clipShape(CoverShape(width: w))
            // Hairline edge so dark covers stay visible on a black background.
            .overlay(CoverShape(width: w).stroke(Color.primary.opacity(0.12), lineWidth: 0.75))
        }
    }
}

struct CoverShape: Shape {
    let width: CGFloat
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: width * 0.025,
                               bottomLeadingRadius: width * 0.025,
                               bottomTrailingRadius: width * 0.07,
                               topTrailingRadius: width * 0.07,
                               style: .continuous).path(in: rect)
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
                    .fill(base)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [.white.opacity(0.12), .black.opacity(0.10)],
                                             startPoint: .top, endPoint: .bottom)))
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
        VStack(spacing: 4) {
            NotebookCoverView(cover: notebook.cover)
                .aspectRatio(0.74, contentMode: .fit)
                .shadow(color: .black.opacity(0.22), radius: 7, x: 0, y: 4)
                .overlay(alignment: .topTrailing) {
                    if notebook.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                            .padding(8)
                    }
                }
            Text(notebook.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Text(Self.dateText(notebook.modifiedAt))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    static func dateText(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(d) { return "Today, \(time)" }
        if cal.isDateInYesterday(d) { return "Yesterday, \(time)" }
        return d.formatted(date: .numeric, time: .shortened)
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
