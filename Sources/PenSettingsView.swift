import SwiftUI
import PencilKit

/// Live preview of a pen: draws a real PencilKit stroke with varying pressure.
struct StrokePreview: View {
    let inkType: PKInkingTool.InkType
    let color: UIColor
    let width: CGFloat
    var feel: InkFeel = .standard

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > 40, geo.size.height > 10 {
                Image(uiImage: Self.render(inkType: inkType, color: color, width: width, size: geo.size, feel: feel))
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    static func render(inkType: PKInkingTool.InkType, color: UIColor, width: CGFloat, size: CGSize,
                       feel: InkFeel = .standard) -> UIImage {
        let ink = PKInk(inkType, color: color)
        var points: [PKStrokePoint] = []
        let n = 80
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let x = 20 + t * (size.width - 40)
            // A slightly shaky line, so stabilization has something to smooth.
            let wobble = sin(t * 90) * 1.2
            let y = size.height / 2 + sin(t * .pi * 2) * size.height * 0.22 + wobble
            let force = 0.3 + 1.2 * sin(t * .pi)
            let w = width * (0.55 + 0.75 * force / 1.5)
            points.append(PKStrokePoint(location: CGPoint(x: x, y: y),
                                        timeOffset: TimeInterval(t),
                                        size: CGSize(width: w, height: w),
                                        opacity: 1,
                                        force: force,
                                        azimuth: 0,
                                        altitude: .pi / 2))
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = StrokeShaper.apply(feel, to: PKStroke(ink: ink, path: path, transform: .identity, mask: nil))
        let drawing = PKDrawing(strokes: [stroke])
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: size), scale: UIScreen.main.scale)
        }
        return image
    }
}

/// A drawn pen tip for each pen type (barrel with an ink-coloured band, then the nib).
struct PenTipIcon: View {
    let kind: InkKind
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let barrelW = w * 0.46
            let barrelTop: CGFloat = 0
            let barrelBottom = h * 0.42
            let barrel = Path(roundedRect: CGRect(x: cx - barrelW / 2, y: barrelTop, width: barrelW, height: barrelBottom),
                              cornerSize: CGSize(width: 3, height: 3))
            ctx.fill(barrel, with: .linearGradient(Gradient(colors: [Color(white: 0.62), Color(white: 0.86), Color(white: 0.58)]),
                                                   startPoint: CGPoint(x: cx - barrelW / 2, y: 0),
                                                   endPoint: CGPoint(x: cx + barrelW / 2, y: 0)))
            // Ink-coloured band.
            ctx.fill(Path(CGRect(x: cx - barrelW / 2, y: barrelTop, width: barrelW, height: h * 0.14)), with: .color(color))

            var cone = Path()
            switch kind {
            case .pencil:
                cone.move(to: CGPoint(x: cx - barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx, y: h * 0.98))
                cone.closeSubpath()
                ctx.fill(cone, with: .color(Color(hex: "#E8C99A")))
                var lead = Path()
                lead.move(to: CGPoint(x: cx - barrelW * 0.16, y: h * 0.82))
                lead.addLine(to: CGPoint(x: cx + barrelW * 0.16, y: h * 0.82))
                lead.addLine(to: CGPoint(x: cx, y: h * 0.98))
                lead.closeSubpath()
                ctx.fill(lead, with: .color(color))
            case .crayon:
                cone.move(to: CGPoint(x: cx - barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + barrelW * 0.28, y: h * 0.9))
                cone.addQuadCurve(to: CGPoint(x: cx - barrelW * 0.28, y: h * 0.9), control: CGPoint(x: cx, y: h * 0.98))
                cone.closeSubpath()
                ctx.fill(cone, with: .color(color))
            case .brush:
                cone.move(to: CGPoint(x: cx - barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + barrelW * 0.3, y: h * 0.58))
                cone.addLine(to: CGPoint(x: cx - barrelW * 0.3, y: h * 0.58))
                cone.closeSubpath()
                ctx.fill(cone, with: .color(Color(white: 0.7)))
                var bristle = Path()
                bristle.move(to: CGPoint(x: cx - barrelW * 0.3, y: h * 0.58))
                bristle.addQuadCurve(to: CGPoint(x: cx, y: h * 0.99), control: CGPoint(x: cx - barrelW * 0.45, y: h * 0.85))
                bristle.addQuadCurve(to: CGPoint(x: cx + barrelW * 0.3, y: h * 0.58), control: CGPoint(x: cx + barrelW * 0.45, y: h * 0.85))
                bristle.closeSubpath()
                ctx.fill(bristle, with: .color(color))
            case .fountain:
                cone.move(to: CGPoint(x: cx - barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + barrelW / 2, y: barrelBottom))
                cone.addQuadCurve(to: CGPoint(x: cx, y: h * 0.98), control: CGPoint(x: cx + barrelW * 0.45, y: h * 0.78))
                cone.addQuadCurve(to: CGPoint(x: cx - barrelW / 2, y: barrelBottom), control: CGPoint(x: cx - barrelW * 0.45, y: h * 0.78))
                cone.closeSubpath()
                ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.85), Color(white: 0.55)]),
                                                     startPoint: CGPoint(x: cx - barrelW / 2, y: 0),
                                                     endPoint: CGPoint(x: cx + barrelW / 2, y: 0)))
                var slit = Path()
                slit.move(to: CGPoint(x: cx, y: h * 0.66))
                slit.addLine(to: CGPoint(x: cx, y: h * 0.96))
                ctx.stroke(slit, with: .color(Color(white: 0.25)), lineWidth: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 2, y: h * 0.62, width: 4, height: 4)), with: .color(Color(white: 0.25)))
            case .monoline:
                cone.move(to: CGPoint(x: cx - barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + barrelW * 0.14, y: h * 0.8))
                cone.addLine(to: CGPoint(x: cx - barrelW * 0.14, y: h * 0.8))
                cone.closeSubpath()
                ctx.fill(cone, with: .color(Color(white: 0.72)))
                ctx.fill(Path(roundedRect: CGRect(x: cx - 1.6, y: h * 0.8, width: 3.2, height: h * 0.18), cornerSize: CGSize(width: 1.5, height: 1.5)),
                         with: .color(color))
            case .ballpoint:
                cone.move(to: CGPoint(x: cx - barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + barrelW / 2, y: barrelBottom))
                cone.addLine(to: CGPoint(x: cx + 2, y: h * 0.92))
                cone.addLine(to: CGPoint(x: cx - 2, y: h * 0.92))
                cone.closeSubpath()
                ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color(white: 0.6), Color(white: 0.88), Color(white: 0.6)]),
                                                     startPoint: CGPoint(x: cx - barrelW / 2, y: 0),
                                                     endPoint: CGPoint(x: cx + barrelW / 2, y: 0)))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 2.2, y: h * 0.9, width: 4.4, height: 4.4)), with: .color(color))
            }
        }
    }
}

enum ColorTab: String, CaseIterable, Identifiable {
    case presets = "Presets", grid = "Grid", spectrum = "Spectrum"
    var id: String { rawValue }
}

/// Colour picker with Presets, Grid and Spectrum tabs, recent colours and a hex field.
struct ColorPalettePicker: View {
    @EnvironmentObject var tools: ToolState
    @Binding var hex: String
    @AppStorage("folio.colorTab") private var tabRaw = ColorTab.presets.rawValue
    @State private var hexField = ""

    private var tab: ColorTab { ColorTab(rawValue: tabRaw) ?? .presets }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Colours", selection: $tabRaw) {
                ForEach(ColorTab.allCases) { t in Text(t.rawValue).tag(t.rawValue) }
            }
            .pickerStyle(.segmented)

            Group {
                switch tab {
                case .presets:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                        ForEach(Theme.penColors, id: \.self) { c in swatch(c) }
                    }
                case .grid:
                    ColorGrid(hex: $hex) { tools.noteRecent($0) }
                case .spectrum:
                    SpectrumPicker(hex: $hex) { tools.noteRecent($0) }
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: tabRaw)

            if !tools.recentColors.isEmpty {
                Text("Recent").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(tools.recentColors, id: \.self) { c in swatch(c) }
                }
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: hex))
                    .frame(width: 44, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                ColorPicker("Custom", selection: Binding(
                    get: { Color(hex: hex) },
                    set: { newColor in
                        let h = UIColor(newColor).hexString
                        hex = h
                        hexField = h
                        tools.noteRecent(h)
                    }), supportsOpacity: false)
                    .labelsHidden()
                Spacer()
                TextField("#000000", text: $hexField)
                    .font(.system(.subheadline, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 96)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        var s = hexField.trimmingCharacters(in: .whitespaces).uppercased()
                        if !s.hasPrefix("#") { s = "#" + s }
                        if s.count == 7, s.dropFirst().allSatisfy({ $0.isHexDigit }) {
                            hex = s
                            hexField = s
                            tools.noteRecent(s)
                        } else {
                            hexField = hex
                        }
                    }
            }
        }
        .onAppear { hexField = hex }
        .onChange(of: hex) { _, newValue in hexField = newValue }
    }

    private func swatch(_ c: String) -> some View {
        let selected = hex.uppercased() == c.uppercased()
        return Circle()
            .fill(Color(hex: c))
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
            .overlay(Circle().stroke(Theme.action, lineWidth: selected ? 2.5 : 0).padding(-3))
            .scaleEffect(selected ? 1.08 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selected)
            .onTapGesture {
                hex = c
                tools.noteRecent(c)
            }
    }
}

/// A 12 x 10 grid of hues and shades, like the system colour grid.
struct ColorGrid: View {
    @Binding var hex: String
    let onPick: (String) -> Void

    static let colors: [[String]] = {
        var rows: [[String]] = []
        rows.append((0..<12).map { i in UIColor(white: 1 - CGFloat(i) / 11, alpha: 1).hexString })
        for r in 1...9 {
            let sat: CGFloat = r <= 4 ? CGFloat(r) / 4.0 : 1
            let bri: CGFloat = r <= 4 ? 1 : 1 - CGFloat(r - 4) * 0.15
            rows.append((0..<12).map { c in
                UIColor(hue: CGFloat(c) / 12, saturation: sat, brightness: bri, alpha: 1).hexString
            })
        }
        return rows
    }()

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<Self.colors.count, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(Self.colors[r], id: \.self) { c in
                        Rectangle()
                            .fill(Color(hex: c))
                            .frame(height: 20)
                            .overlay(Rectangle().stroke(Color.white, lineWidth: hex.uppercased() == c.uppercased() ? 2.5 : 0))
                            .onTapGesture {
                                hex = c
                                onPick(c)
                            }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Saturation/brightness square plus a hue bar.
struct SpectrumPicker: View {
    @Binding var hex: String
    let onPick: (String) -> Void
    @State private var h: CGFloat = 0
    @State private var s: CGFloat = 1
    @State private var b: CGFloat = 1

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [.white, Color(hue: h, saturation: 1, brightness: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .frame(width: 22, height: 22)
                        .position(x: s * geo.size.width, y: (1 - b) * geo.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    s = min(max(v.location.x / geo.size.width, 0), 1)
                    b = 1 - min(max(v.location.y / geo.size.height, 0), 1)
                    push(final: false)
                }.onEnded { _ in push(final: true) })
            }
            .frame(height: 150)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) },
                                   startPoint: .leading, endPoint: .trailing)
                        .clipShape(Capsule())
                    Circle()
                        .fill(Color(hue: h, saturation: 1, brightness: 1))
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .frame(width: 24, height: 24)
                        .position(x: h * geo.size.width, y: geo.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    h = min(max(v.location.x / geo.size.width, 0), 0.999)
                    push(final: false)
                }.onEnded { _ in push(final: true) })
            }
            .frame(height: 24)
        }
        .onAppear {
            var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, a: CGFloat = 0
            UIColor(hex: hex).getHue(&hh, saturation: &ss, brightness: &bb, alpha: &a)
            h = hh; s = ss; b = bb
        }
    }

    private func push(final: Bool) {
        let c = UIColor(hue: h, saturation: s, brightness: b, alpha: 1).hexString
        hex = c
        if final { onPick(c) }
    }
}

struct PenSettingsView: View {
    @EnvironmentObject var tools: ToolState

    private var sizePresets: [CGFloat] {
        let r = tools.pen.kind.widthRange
        return [0.04, 0.12, 0.25, 0.45, 0.75].map { r.lowerBound + (r.upperBound - r.lowerBound) * $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tools.pen.kind.title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                StrokePreview(inkType: tools.pen.kind.inkType, color: tools.pen.uiColor, width: tools.pen.width,
                              feel: tools.pen.inkFeel)
                    .frame(height: 76)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(InkKind.penKinds) { k in
                        penTile(k)
                    }
                }

                // Pen feel tuning was removed in 1.4.

                HStack {
                    label("Thickness")
                    Spacer()
                    Text(String(format: "%.1f pt", tools.pen.width))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                HStack(spacing: 0) {
                    ForEach(sizePresets, id: \.self) { s in
                        Button { withAnimation(.snappy) { tools.pen.width = s } } label: {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: min(26, 4 + s * 0.9), height: min(26, 4 + s * 0.9))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(abs(tools.pen.width - s) < 0.05 ? Theme.action.opacity(0.25) : Color.clear))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                Slider(value: $tools.pen.width, in: tools.pen.kind.widthRange)

                HStack {
                    label("Opacity")
                    Spacer()
                    Text("\(Int(tools.pen.opacity * 100))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $tools.pen.opacity, in: 0.1...1)

                label("Color")
                ColorPalettePicker(hex: $tools.pen.colorHex)

                Divider()

                HStack {
                    label("Favorites")
                    Spacer()
                    Button {
                        withAnimation(.spring) { tools.addFavorite(tools.pen) }
                    } label: {
                        Label("Save Current Pen", systemImage: "star")
                            .font(.subheadline.weight(.medium))
                    }
                }
                if tools.favorites.isEmpty {
                    Text("Saved pens appear here for one-tap switching.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(tools.favorites) { fav in
                            HStack(spacing: 10) {
                                StrokePreview(inkType: fav.kind.inkType, color: fav.uiColor, width: fav.width)
                                    .frame(height: 34)
                                    .onTapGesture { tools.selectFavorite(fav) }
                                Button(role: .destructive) { withAnimation(.spring) { tools.removeFavorite(fav.id) } } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(18)
        }
        .tint(Theme.action)
        .frame(width: 360, height: 680)
        .animation(.snappy(duration: 0.22), value: tools.pen.kind)
        .darkPanel()
    }

    /// GoodNotes-style pen customisation.
    private var feelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                label("Pen Feel")
                Spacer()
                if !tools.pen.inkFeel.isStandard {
                    Button("Reset") { withAnimation(.snappy) { tools.pen.inkFeel = .standard } }
                        .font(.caption.weight(.semibold))
                }
            }
            feelSlider("Tip Sharpness", value: $tools.pen.inkFeel.tipSharpness, low: "Round", high: "Sharp")
            feelSlider("Pressure Sensitivity", value: $tools.pen.inkFeel.pressure, low: "Even", high: "Strong")
            feelSlider("Tip Flatness", value: $tools.pen.inkFeel.tipFlatness, low: "Round", high: "Flat")
            feelSlider("Stroke Stabilization", value: $tools.pen.inkFeel.stabilization, low: "Off", high: "Smooth")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
    }

    private func feelSlider(_ title: String, value: Binding<Double>, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(low).font(.caption2).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                Slider(value: value, in: 0...1)
                Text(high).font(.caption2).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func penTile(_ k: InkKind) -> some View {
        let selected = tools.pen.kind == k
        return Button {
            tools.pen.kind = k
            tools.pen.width = min(max(tools.pen.width, k.widthRange.lowerBound), k.widthRange.upperBound)
        } label: {
            VStack(spacing: 4) {
                PenTipIcon(kind: k, color: Color(hex: tools.pen.colorHex))
                    .frame(width: 26, height: 46)
                    .offset(y: selected ? -3 : 0)
                Text(k.title).font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(k.subtitle).font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.action.opacity(0.28) : Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.action : Color.clear, lineWidth: 2))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(k.title)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.semibold))
    }
}

struct HighlighterSettingsView: View {
    @EnvironmentObject var tools: ToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Highlighter")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .frame(maxWidth: .infinity)
            StrokePreview(inkType: .marker, color: tools.highlighter.uiColor, width: tools.highlighter.width)
                .frame(height: 64)
            HStack {
                Text("Thickness").font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.0f pt", tools.highlighter.width)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $tools.highlighter.width, in: 4...50)
            Text("Color").font(.subheadline.weight(.semibold))
            ColorPalettePicker(hex: $tools.highlighter.colorHex)
        }
        .padding(18)
        .frame(width: 360)
        .tint(Theme.action)
        .darkPanel()
    }
}

struct EraserSettingsView: View {
    @EnvironmentObject var tools: ToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Eraser")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .frame(maxWidth: .infinity)
            Picker("Mode", selection: $tools.eraserMode) {
                ForEach(EraserMode.allCases) { m in Text(m.title).tag(m) }
            }
            .pickerStyle(.segmented)
            if tools.eraserMode == .pixel {
                HStack {
                    Text("Size").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.0f pt", tools.eraserWidth)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $tools.eraserWidth, in: 4...80)
            } else {
                Text("Touching a stroke erases the whole stroke.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Label("Double-tap Apple Pencil to switch between the eraser and your pen.", systemImage: "applepencil.tip")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 320)
        .tint(Theme.action)
        .darkPanel()
    }
}
