import SwiftUI

/// A notebook cover: gradient, subtle pattern, a darker spine and a title label.
struct NotebookCoverView: View {
    let cover: CoverStyle
    var title: String? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pal = cover.colors
            let photo = cover.photo.flatMap(CoverPhotos.image)
            ZStack(alignment: .topLeading) {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    LinearGradient(colors: [Color(hex: pal.0), Color(hex: pal.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    CoverPatternView(pattern: cover.pattern)
                        .opacity(0.16)
                }
                // Coloured spine with a soft fold shadow (a photo gets a soft dark one).
                Rectangle()
                    .fill(photo == nil ? Color(hex: pal.2) : Color.black.opacity(0.28))
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

/// Folder shape with a tab on the top left. The bottom corners use the same
/// circular radius as the glass front, so the back never peeks out at the corners.
struct FolderShape: Shape {
    var bottomRadius: CGFloat = 22

    func path(in r: CGRect) -> Path {
        let tabW = r.width * 0.4
        let tabH: CGFloat = 14
        let rad: CGFloat = 14
        let br = min(bottomRadius, r.width / 2, (r.height - tabH) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + rad, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tabW - 12, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + tabW + 10, y: r.minY + tabH),
                       control: CGPoint(x: r.minX + tabW, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY + tabH))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + tabH + rad), control: CGPoint(x: r.maxX, y: r.minY + tabH))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: br)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: br)
        p.closeSubpath()
        return p
    }
}

/// A frosted-glass folder: the notebooks inside stick out of the top and show
/// through the glass front, blurred, so you can see what's in the folder.
struct FolderCard: View {
    let folder: Folder
    let notebooks: [Notebook]
    var subfolders: Int = 0
    /// Notebooks in this folder and its subfolders (defaults to the direct ones).
    var total: Int? = nil
    @Environment(\.colorScheme) private var scheme

    private var base: Color { Color(hex: Theme.folderColors[abs(folder.colorIndex) % Theme.folderColors.count]) }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                // Back of the folder, with the tab.
                FolderShape()
                    .fill(LinearGradient(colors: [base.opacity(scheme == .dark ? 0.50 : 0.40),
                                                  base.opacity(scheme == .dark ? 0.30 : 0.22)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(FolderShape().stroke(Color.white.opacity(scheme == .dark ? 0.14 : 0.55), lineWidth: 1))

                contents
                    .frame(height: 150, alignment: .top)
                    .padding(.top, 20)

                // Frosted glass front.
                let front = RoundedRectangle(cornerRadius: 22, style: .circular)
                // Frosted glass: blurs the notebooks behind it, tinted with the folder colour.
                front
                    .fill(.thinMaterial)
                    .overlay(front.fill(base.opacity(scheme == .dark ? 0.22 : 0.16)))
                    .overlay(front.fill(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.08 : 0.28),
                                                                Color.white.opacity(0.0)],
                                                       startPoint: .top, endPoint: .bottom)))
                    .overlay(front.strokeBorder(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.35 : 0.9),
                                                                        Color.white.opacity(0.1)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .frame(height: 112)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: folder.icon)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(LinearGradient(colors: [base, base.opacity(0.75)],
                                                            startPoint: .top, endPoint: .bottom))
                            .shadow(color: base.opacity(0.35), radius: 6, y: 3)
                            .padding(16)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let latest = notebooks.first {
                            Text(latest.title)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 120, alignment: .leading)
                                .padding(.leading, 16)
                                .padding(.bottom, 18)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if subfolders > 0 {
                            Label("\(subfolders)", systemImage: "folder.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(base)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(scheme == .dark ? 0.12 : 0.6)))
                                .padding(12)
                        }
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.07), radius: 12, x: 0, y: 6)
            }
            .frame(height: 170)

            HStack(spacing: 7) {
                Text(folder.name)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                Text("\(total ?? notebooks.count)")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
    }

    /// The first few notebooks, fanned out; their lower half sits behind the glass.
    @ViewBuilder
    private var contents: some View {
        if notebooks.isEmpty && subfolders > 0 {
            // Only subfolders inside: show little folder tabs peeking out.
            HStack(spacing: -22) {
                ForEach(0..<min(subfolders, 3), id: \.self) { i in
                    FolderShape()
                        .fill(base.opacity(0.55 - Double(i) * 0.12))
                        .frame(width: 80, height: 64)
                        .rotationEffect(.degrees(Double(i - 1) * 6))
                        .offset(y: i == 1 ? -6 : 0)
                }
            }
        } else if notebooks.isEmpty {
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(scheme == .dark ? 0.75 : 0.95))
                        .frame(width: 84, height: 100)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        .rotationEffect(.degrees(i == 0 ? -6 : 5))
                        .offset(x: i == 0 ? -14 : 14)
                }
            }
        } else {
            HStack(spacing: -30) {
                ForEach(Array(notebooks.prefix(3).enumerated()), id: \.element.id) { i, nb in
                    NotebookCoverView(cover: nb.cover)
                        .frame(width: 66, height: 88)
                        .rotationEffect(.degrees(notebooks.count == 1 ? -3 : Double(i - 1) * 8))
                        .offset(y: i == 1 ? -6 : 0)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 2)
                        .zIndex(Double(i == 1 ? 3 : 3 - i))
                }
            }
        }
    }
}

struct NotebookTile: View {
    let notebook: Notebook
    var zoomNS: Namespace.ID? = nil

    var body: some View {
        VStack(spacing: 4) {
            NotebookCoverView(cover: notebook.cover)
                .aspectRatio(0.74, contentMode: .fit)
                .zoomSource(id: notebook.id, in: zoomNS)
                .shadow(color: .black.opacity(0.22), radius: 7, x: 0, y: 4)
                .overlay(alignment: .bottomTrailing) {
                    if notebook.isCanvas {
                        Image(systemName: "infinity")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(8)
                            .accessibilityLabel("Infinite canvas")
                    }
                }
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
    var spacing: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / TemplateRenderer.pageSize.width
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(uiColor: paper.uiColor)))
            for layer in TemplateRenderer.layers(template: template, paper: paper, scale: s, spacing: spacing) {
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
