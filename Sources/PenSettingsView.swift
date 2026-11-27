import SwiftUI
import PencilKit

/// Live preview of a pen: draws a real PencilKit stroke with varying pressure.
struct StrokePreview: View {
    let inkType: PKInkingTool.InkType
    let color: UIColor
    let width: CGFloat

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > 40, geo.size.height > 10 {
                Image(uiImage: Self.render(inkType: inkType, color: color, width: width, size: geo.size))
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    static func render(inkType: PKInkingTool.InkType, color: UIColor, width: CGFloat, size: CGSize) -> UIImage {
        let ink = PKInk(inkType, color: color)
        var points: [PKStrokePoint] = []
        let n = 80
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let x = 20 + t * (size.width - 40)
            let y = size.height / 2 + sin(t * .pi * 2) * size.height * 0.22
            let force = 0.3 + 1.2 * sin(t * .pi)
            points.append(PKStrokePoint(location: CGPoint(x: x, y: y),
                                        timeOffset: TimeInterval(t),
                                        size: CGSize(width: width, height: width),
                                        opacity: 1,
                                        force: force,
                                        azimuth: 0,
                                        altitude: .pi / 2))
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(ink: ink, path: path, transform: .identity, mask: nil)
        let drawing = PKDrawing(strokes: [stroke])
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: size), scale: UIScreen.main.scale)
        }
        return image
    }
}

/// Colour picker: preset grid, recent colours, system picker and a hex field.
struct ColorPalettePicker: View {
    @EnvironmentObject var tools: ToolState
    @Binding var hex: String
    @State private var hexField = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(Theme.penColors, id: \.self) { c in
                    swatch(c)
                }
            }
            if !tools.recentColors.isEmpty {
                Text("Recent").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(tools.recentColors, id: \.self) { c in swatch(c) }
                }
            }
            HStack(spacing: 12) {
                ColorPicker("Custom", selection: Binding(
                    get: { Color(hex: hex) },
                    set: { newColor in
                        let h = UIColor(newColor).hexString
                        hex = h
                        hexField = h
                        tools.noteRecent(h)
                    }), supportsOpacity: false)
                    .labelsHidden()
                Text("Custom").font(.subheadline)
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
        Circle()
            .fill(Color(hex: c))
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
            .overlay(Circle().stroke(Theme.accent, lineWidth: hex.uppercased() == c.uppercased() ? 2.5 : 0).padding(-3))
            .onTapGesture {
                hex = c
                tools.noteRecent(c)
            }
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
                StrokePreview(inkType: tools.pen.kind.inkType, color: tools.pen.uiColor, width: tools.pen.width)
                    .frame(height: 76)

                label("Pen Type")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(InkKind.allCases) { k in
                        let selected = tools.pen.kind == k
                        Button {
                            tools.pen.kind = k
                            tools.pen.width = min(max(tools.pen.width, k.widthRange.lowerBound), k.widthRange.upperBound)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: k.symbol).font(.system(size: 20))
                                Text(k.title).font(.caption.weight(.medium))
                                Text(k.subtitle).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.accent.opacity(0.14) : Color.secondary.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.accent : Color.clear, lineWidth: 1.5))
                            .foregroundStyle(selected ? Theme.accent : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    label("Thickness")
                    Spacer()
                    Text(String(format: "%.1f pt", tools.pen.width))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    ForEach(sizePresets, id: \.self) { s in
                        Button { tools.pen.width = s } label: {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: min(26, 4 + s * 0.9), height: min(26, 4 + s * 0.9))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(abs(tools.pen.width - s) < 0.05 ? Theme.accent.opacity(0.15) : Color.clear))
                        }
                        .buttonStyle(.plain)
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
                        tools.addFavorite(tools.pen)
                    } label: {
                        Label("Save Current Pen", systemImage: "star")
                            .font(.subheadline.weight(.medium))
                    }
                }
                if tools.favorites.isEmpty {
                    Text("Saved pens appear in the toolbar for one-tap switching.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(tools.favorites) { fav in
                            HStack(spacing: 10) {
                                StrokePreview(inkType: fav.kind.inkType, color: fav.uiColor, width: fav.width)
                                    .frame(height: 34)
                                    .onTapGesture { tools.selectFavorite(fav) }
                                Button(role: .destructive) { tools.removeFavorite(fav.id) } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 360, height: 640)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.semibold))
    }
}

struct HighlighterSettingsView: View {
    @EnvironmentObject var tools: ToolState
    private let colors = ["#F7E14A", "#A3D977", "#7FD3F7", "#FF9EC4", "#FFB067", "#C9A7F5"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StrokePreview(inkType: .marker, color: tools.highlighter.uiColor, width: tools.highlighter.width)
                .frame(height: 64)
            HStack {
                Text("Thickness").font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.0f pt", tools.highlighter.width)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $tools.highlighter.width, in: 4...50)
            Text("Color").font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { c in
                    Circle()
                        .fill(Color(hex: c))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Theme.accent, lineWidth: tools.highlighter.colorHex == c ? 2.5 : 0).padding(-3))
                        .onTapGesture { tools.highlighter.colorHex = c }
                }
            }
            ColorPalettePicker(hex: $tools.highlighter.colorHex)
        }
        .padding(18)
        .frame(width: 340)
    }
}

struct EraserSettingsView: View {
    @EnvironmentObject var tools: ToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Eraser").font(.headline)
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
        }
        .padding(18)
        .frame(width: 300)
    }
}
