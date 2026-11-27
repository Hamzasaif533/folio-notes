import SwiftUI

/// Tapping the pen that's already in use: pick Fountain, Ball or Brush pen and tune how it feels.
struct PenTypePicker: View {
    @EnvironmentObject var tools: ToolState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(tools.pen.kind.title)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                        .padding(.top, 4)

                    StrokePreview(style: tools.pen.kind.inkStyle, color: tools.pen.uiColor, width: tools.pen.width,
                                  feel: tools.pen.inkFeel)
                        .frame(height: 80)

                    HStack(spacing: 10) {
                        ForEach(InkKind.penKinds) { kind in tile(kind) }
                    }

                    VStack(spacing: 16) {
                        feel("Tip Sharpness", \.tipSharpness)
                        feel("Pressure Sensitivity", \.pressure)
                        // The fountain pen's flat nib has its own fixed shape.
                        if tools.pen.kind != .fountain { feel("Tip Flatness", \.tipFlatness) }
                        feel("Stroke Stabilization", \.stabilization)
                        if tools.pen.inkFeel != tools.pen.kind.defaultFeel {
                            Button {
                                withAnimation(.snappy) { tools.pen.feel = nil }
                            } label: {
                                Text("Reset to Default")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.action)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#1C1C1E")))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Settings")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        NavigationLink {
                            PenSettingsView(embedded: true).environmentObject(tools)
                        } label: {
                            HStack {
                                Text("Pen Settings").foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#1C1C1E")))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(hex: "#2C2C2E"))
        }
        .tint(Theme.action)
        .animation(.snappy(duration: 0.2), value: tools.pen.kind)
        .frame(width: 360, height: 640)
        .presentationCompactAdaptation(.popover)
        .darkPanel()
    }

    private func tile(_ kind: InkKind) -> some View {
        let on = tools.pen.kind == kind
        return Button {
            withAnimation(.snappy(duration: 0.2)) { tools.choosePen(kind) }
        } label: {
            VStack(spacing: 8) {
                PenTipIcon(kind: kind, color: Color(hex: tools.pen.colorHex))
                    .frame(width: 24, height: 44)
                    .offset(y: on ? -3 : 0)
                Text(kind.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(on ? Theme.action.opacity(0.25) : Color(hex: "#1C1C1E")))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(on ? Theme.action : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(kind.title)
    }

    private func feel(_ title: String, _ key: WritableKeyPath<InkFeel, Double>) -> some View {
        let value = Binding<Double>(
            get: { tools.pen.inkFeel[keyPath: key] },
            set: { v in
                var f = tools.pen.inkFeel
                f[keyPath: key] = v
                tools.pen.feel = f
            })
        return VStack(spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Slider(value: value, in: 0...1)
        }
    }
}

/// Tapping the size that's already in use: fine-tune it with a slider.
struct SizeSlotPicker: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    /// Colour of the sample line (the tool's current colour).
    let colorHex: String
    /// Tape is drawn as a flat band; ink as a rounded line.
    var flat = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Size").font(.subheadline.weight(.semibold))
                Spacer()
                Text(value < 10 ? String(format: "%.1f", Double(value)) : "\(Int(value.rounded()))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)

            // A sample of the line at this size (capped so huge sizes still fit).
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                SampleStroke()
                    .stroke(Color(hex: colorHex),
                            style: StrokeStyle(lineWidth: min(value, 44), lineCap: flat ? .butt : .round, lineJoin: .round))
                    .padding(.horizontal, 26)
            }
            .frame(height: 70)

            HStack(spacing: 10) {
                Button { nudge(-1) } label: { Image(systemName: "minus") }
                    .buttonStyle(PressableStyle())
                Slider(value: Binding(get: { Double(value) }, set: { value = CGFloat($0) }),
                       in: Double(range.lowerBound)...Double(range.upperBound))
                    .tint(Theme.action)
                Button { nudge(1) } label: { Image(systemName: "plus") }
                    .buttonStyle(PressableStyle())
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(16)
        .frame(width: 300)
        .presentationCompactAdaptation(.popover)
        .darkPanel()
    }

    private func nudge(_ dir: CGFloat) {
        let step: CGFloat = range.upperBound - range.lowerBound > 40 ? 2 : 0.5
        value = min(max(value + dir * step, range.lowerBound), range.upperBound)
    }
}

private struct SampleStroke: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + 6))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.midY - 6),
                   control1: CGPoint(x: r.minX + r.width * 0.35, y: r.midY - 16),
                   control2: CGPoint(x: r.minX + r.width * 0.65, y: r.midY + 16))
        return p
    }
}

/// Tapping the colour that's already in use: change that colour hole, and nothing else.
struct ColorSlotPicker: View {
    @Binding var hex: String
    /// Nil when this is the last colour (there's always at least one).
    var onDelete: (() -> Void)?

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 10), count: 6)

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Theme.penColors, id: \.self) { c in
                    let on = c.lowercased() == hex.lowercased()
                    Button { hex = c } label: {
                        Circle()
                            .fill(Color(hex: c))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                            .padding(2)
                            .overlay(Circle().stroke(on ? Color.white : Color.clear, lineWidth: 2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            HStack(spacing: 10) {
                ColorPicker(selection: Binding(
                    get: { Color(hex: hex) },
                    set: { hex = UIColor($0).hexString }), supportsOpacity: false) {
                    Text("Custom").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))

                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.40))
                            .frame(width: 44, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Delete Colour")
                }
            }
        }
        .padding(14)
        .frame(width: 290)
        .presentationCompactAdaptation(.popover)
        .darkPanel()
    }
}
