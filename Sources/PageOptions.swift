import SwiftUI
import PhotosUI

// MARK: - Cover photos

/// Photos used as notebook covers, already cropped to the cover's shape
/// (Documents/Folio/Covers/<name>.jpg).
enum CoverPhotos {
    static var dir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("Folio", isDirectory: true).appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 40
        return c
    }()

    static func save(_ image: UIImage) -> String? {
        let name = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: 0.85),
              (try? data.write(to: dir.appendingPathComponent(name), options: .atomic)) != nil else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return name
    }

    static func image(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let img = UIImage(contentsOfFile: dir.appendingPathComponent(name).path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }
}

extension CoverStyle {
    /// Main colour, lighter corner and spine, as hex.
    var colors: (String, String, String) {
        if let hex = customHex {
            let c = UIColor(hex: hex)
            return (c.adjusted(brightness: 1.12).hexString, c.adjusted(brightness: 0.92).hexString,
                    c.adjusted(brightness: 0.72).hexString)
        }
        return Theme.coverPalettes[abs(paletteIndex) % Theme.coverPalettes.count]
    }
}

extension UIColor {
    /// The same colour, brighter (> 1) or darker (< 1).
    func adjusted(brightness f: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: min(max(b * f, 0), 1), alpha: a)
    }
}

/// Pick a photo, then move and zoom it inside the cover's frame.
struct CoverPhotoEditor: View {
    let image: UIImage
    let onDone: (UIImage) -> Void
    let onCancel: () -> Void

    /// The cover's width / height.
    static let aspect: CGFloat = 0.74

    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    /// The cover frame as laid out on screen.
    @State private var frameNow: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let frame = frameSize(in: geo.size)
                let fill = max(frame.width / image.size.width, frame.height / image.size.height)
                let shown = CGSize(width: image.size.width * fill * zoom, height: image.size.height * fill * zoom)
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: shown.width, height: shown.height)
                        .offset(offset)
                    // Darken what falls outside the cover.
                    Rectangle()
                        .fill(Color.black.opacity(0.55))
                        .mask {
                            Rectangle()
                                .overlay {
                                    CoverShape(width: frame.width)
                                        .frame(width: frame.width, height: frame.height)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)
                    CoverShape(width: frame.width)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                        .frame(width: frame.width, height: frame.height)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { v in
                                zoom = min(max(baseZoom * v, 1), 6)
                                offset = clamped(offset, shown: scaled(fill), frame: frame)
                            }
                            .onEnded { _ in baseZoom = zoom },
                        DragGesture()
                            .onChanged { v in
                                let o = CGSize(width: baseOffset.width + v.translation.width,
                                               height: baseOffset.height + v.translation.height)
                                offset = clamped(o, shown: scaled(fill), frame: frame)
                            }
                            .onEnded { _ in baseOffset = offset }
                    )
                )
                .overlay(alignment: .bottom) {
                    Text("Drag to move, pinch to zoom")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 24)
                }
                .onAppear { frameNow = frame }
                .onChange(of: geo.size) { _, s in frameNow = frameSize(in: s) }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Cover Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        if frameNow.width > 0 { onDone(render(frame: frameNow)) }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func scaled(_ fill: CGFloat) -> CGSize {
        CGSize(width: image.size.width * fill * zoom, height: image.size.height * fill * zoom)
    }

    private func frameSize(in area: CGSize) -> CGSize {
        let h = min(area.height * 0.78, area.width * 0.8 / Self.aspect)
        return CGSize(width: h * Self.aspect, height: h)
    }

    /// The photo always covers the whole frame.
    private func clamped(_ o: CGSize, shown: CGSize, frame: CGSize) -> CGSize {
        let mx = max(0, (shown.width - frame.width) / 2), my = max(0, (shown.height - frame.height) / 2)
        return CGSize(width: min(max(o.width, -mx), mx), height: min(max(o.height, -my), my))
    }

    /// What's inside the frame, as a picture about 900 pixels tall.
    private func render(frame: CGSize) -> UIImage {
        let fill = max(frame.width / image.size.width, frame.height / image.size.height)
        let s = fill * zoom
        // The frame's rectangle in the photo's own points.
        let w = frame.width / s, h = frame.height / s
        let cx = image.size.width / 2 - offset.width / s
        let cy = image.size.height / 2 - offset.height / s
        let crop = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        let out = CGSize(width: (900 * Self.aspect).rounded(), height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            let k = out.width / crop.width
            image.draw(in: CGRect(x: -crop.minX * k, y: -crop.minY * k,
                                  width: image.size.width * k, height: image.size.height * k))
        }
    }
}

// MARK: - Page size and line spacing

/// The paper sizes, as small page outlines, plus portrait / landscape.
struct PageSizePicker: View {
    @Binding var format: PageFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(PageSize.allCases) { size in
                        tile(size)
                    }
                }
                .padding(.vertical, 4)
            }
            Picker("Orientation", selection: $format.landscape) {
                Label("Portrait", systemImage: "rectangle.portrait").tag(false)
                Label("Landscape", systemImage: "rectangle").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
    }

    private func tile(_ size: PageSize) -> some View {
        let on = format.size == size
        let shape = PageFormat(size: size, landscape: format.landscape).unitSize
        let k = 64 / max(shape.width, shape.height)
        return Button {
            withAnimation(.snappy) {
                if format.size != size, size.prefersLandscape != format.size.prefersLandscape {
                    format.landscape = size.prefersLandscape
                }
                format.size = size
            }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? Theme.action : Color.black.opacity(0.2),
                                                                      lineWidth: on ? 2.5 : 1))
                    .frame(width: shape.width * k, height: shape.height * k)
                    .frame(width: 70, height: 68, alignment: .bottom)
                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                Text(size.title).font(.caption.weight(on ? .semibold : .regular))
                Text(size.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Line spacing: closer or wider lines, grid and dots.
struct LineSpacingControl: View {
    @Binding var spacing: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Slider(value: $spacing, in: 0.6...2, step: 0.05)
                .frame(maxWidth: 320)
            Image(systemName: "text.alignleft")
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
            Text("\(Int((spacing * 100).rounded()))%")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            if abs(spacing - 1) > 0.001 {
                Button("Reset") { withAnimation(.snappy) { spacing = 1 } }
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}

/// Everything the Paper sheet can change.
struct PaperChoice {
    var template: PageTemplate
    var paper: PaperColor
    var spacing: Double
    var format: PageFormat
    var darkPages: Bool
}
