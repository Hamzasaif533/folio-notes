import SwiftUI
import PencilKit

/// Tapping the pen that's already in use: just pick the pen type.
struct PenTypePicker: View {
    @EnvironmentObject var tools: ToolState

    var body: some View {
        VStack(spacing: 6) {
            ForEach(InkKind.penKinds) { kind in
                let on = tools.pen.kind == kind
                Button {
                    withAnimation(.snappy(duration: 0.2)) { tools.pen.kind = kind }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.body.weight(.semibold))
                            Text(kind == .fountain ? "Thick and thin, like ink" : "Smooth, even line")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.action)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(on ? Theme.action.opacity(0.22) : Color.white.opacity(0.06)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(12)
        .frame(width: 270)
        .presentationCompactAdaptation(.popover)
        .darkPanel()
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
