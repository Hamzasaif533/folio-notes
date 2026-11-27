import UIKit
import PencilKit

/// Reshapes a finished PencilKit stroke: the GoodNotes-style pen feel
/// (tip sharpness, pressure sensitivity, tip flatness, stabilization) and
/// the Shapes tool, which snaps a rough drawing into a clean shape.
enum StrokeShaper {

    // MARK: Pen feel

    static func apply(_ feel: InkFeel, to stroke: PKStroke) -> PKStroke {
        var pts = Array(stroke.path)
        guard pts.count > 2, !feel.isStandard else { return stroke }

        // 1. Stabilization: smooth the line (two passes of a moving average, ends kept).
        if feel.stabilization > 0.01 {
            let passes = feel.stabilization > 0.6 ? 3 : 2
            let a = CGFloat(0.85 * feel.stabilization)
            for _ in 0..<passes {
                var smoothed = pts
                for i in 1..<(pts.count - 1) {
                    let prev = smoothed[i - 1].location
                    let cur = pts[i].location
                    let next = pts[i + 1].location
                    let avg = CGPoint(x: (prev.x + cur.x + next.x) / 3, y: (prev.y + cur.y + next.y) / 3)
                    let loc = CGPoint(x: cur.x + (avg.x - cur.x) * a, y: cur.y + (avg.y - cur.y) * a)
                    smoothed[i] = point(pts[i], location: loc)
                }
                pts = smoothed
            }
        }

        // 2. Pressure sensitivity: 0 = even width, 0.5 = as drawn, 1 = double the variation.
        let widths = pts.map { $0.size.width }
        let mean = max(widths.reduce(0, +) / CGFloat(widths.count), 0.1)
        let gain = CGFloat(feel.pressure / 0.5)

        // 3. Tip sharpness: taper the first and last stretch of the stroke.
        var lengths: [CGFloat] = [0]
        for i in 1..<pts.count {
            lengths.append(lengths[i - 1] + hypot(pts[i].location.x - pts[i - 1].location.x,
                                                  pts[i].location.y - pts[i - 1].location.y))
        }
        let total = lengths.last ?? 0
        let taper = min(CGFloat(feel.tipSharpness) * max(mean * 8, 30), total * 0.4)

        // 4. Tip flatness: a flat nib held at 45°, thin on one diagonal, thick on the other.
        let flat = CGFloat(feel.tipFlatness)

        for i in pts.indices {
            var w = mean + (widths[i] - mean) * gain
            w = max(w, mean * 0.15)
            if taper > 0.5 {
                let d = min(lengths[i], total - lengths[i])
                if d < taper {
                    let t = d / taper
                    w *= 0.12 + 0.88 * (t * t * (3 - 2 * t))
                }
            }
            var size = CGSize(width: w, height: w)
            var azimuth = pts[i].azimuth
            if flat > 0.02 {
                size = CGSize(width: w * (1 + flat * 0.6), height: max(w * (1 - flat * 0.85), 0.3))
                azimuth = .pi / 4
            }
            pts[i] = PKStrokePoint(location: pts[i].location, timeOffset: pts[i].timeOffset, size: size,
                                   opacity: pts[i].opacity, force: pts[i].force,
                                   azimuth: azimuth, altitude: pts[i].altitude)
        }
        let path = PKStrokePath(controlPoints: pts, creationDate: stroke.path.creationDate)
        return PKStroke(ink: stroke.ink, path: path, transform: stroke.transform, mask: stroke.mask)
    }

    private static func point(_ p: PKStrokePoint, location: CGPoint) -> PKStrokePoint {
        PKStrokePoint(location: location, timeOffset: p.timeOffset, size: p.size, opacity: p.opacity,
                      force: p.force, azimuth: p.azimuth, altitude: p.altitude)
    }

    // MARK: Shape recognition

    /// Returns a clean version of the stroke, or nil when it doesn't look like a shape.
    static func recognizeShape(_ stroke: PKStroke) -> PKStroke? {
        let raw = stroke.path.map { $0.location.applying(stroke.transform) }
        guard raw.count >= 4 else { return nil }
        let pts = resample(raw, spacing: 3)
        guard pts.count >= 4 else { return nil }
        let box = bounds(pts)
        let diag = hypot(box.width, box.height)
        guard diag > 14 else { return nil }
        let width = max(stroke.path.map { $0.size.width }.reduce(0, +) / CGFloat(max(stroke.path.count, 1)), 1)

        let closed = dist(pts.first!, pts.last!) < diag * 0.22
        var outline: [CGPoint]
        var corners: Set<Int> = []

        if !closed {
            // Straight line?
            let a = pts.first!, b = pts.last!
            let len = dist(a, b)
            let dev = pts.map { distanceToLine($0, a, b) }.max() ?? 0
            if len > 10 && dev < max(len * 0.07, 4) {
                outline = [a, snapAngle(from: a, to: b)]
            } else {
                // An angle or zig-zag: straighten each segment.
                let simple = rdp(pts, epsilon: diag * 0.06)
                guard simple.count <= 5 else { return nil }
                outline = simple
                corners = Set(1..<max(simple.count - 1, 1))
            }
        } else {
            let center = CGPoint(x: box.midX, y: box.midY)
            let rx = box.width / 2, ry = box.height / 2
            let ellipseError = pts.map { p -> CGFloat in
                let dx = (p.x - center.x) / max(rx, 1), dy = (p.y - center.y) / max(ry, 1)
                return abs(sqrt(dx * dx + dy * dy) - 1)
            }.reduce(0, +) / CGFloat(pts.count)

            var loop = pts
            loop.removeLast()
            var poly = rdp(loop + [loop[0]], epsilon: diag * 0.075)
            if poly.count > 1 && dist(poly.first!, poly.last!) < diag * 0.1 { poly.removeLast() }

            if ellipseError < 0.11 && !(poly.count == 4 && isRectangular(poly)) {
                var r = CGSize(width: rx, height: ry)
                if abs(rx - ry) / max(rx, ry) < 0.16 { let m = (rx + ry) / 2; r = CGSize(width: m, height: m) }
                outline = (0...72).map { i in
                    let t = CGFloat(i) / 72 * .pi * 2 - .pi / 2
                    return CGPoint(x: center.x + r.width * cos(t), y: center.y + r.height * sin(t))
                }
            } else if poly.count == 3 {
                outline = poly + [poly[0]]
                corners = [0, 1, 2, 3]
            } else if poly.count == 4 {
                if isRectangular(poly) && isAxisAligned(poly) {
                    let b = bounds(poly)
                    outline = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                               CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY),
                               CGPoint(x: b.minX, y: b.minY)]
                } else {
                    outline = poly + [poly[0]]
                }
                corners = [0, 1, 2, 3, 4]
            } else if poly.count >= 5 && poly.count <= 8 {
                outline = poly + [poly[0]]
                corners = Set(0...poly.count)
            } else {
                return nil
            }
        }
        return makeStroke(outline, corners: corners, width: width, ink: stroke.ink)
    }

    private static func makeStroke(_ outline: [CGPoint], corners: Set<Int>, width: CGFloat, ink: PKInk) -> PKStroke {
        var points: [PKStrokePoint] = []
        var t: TimeInterval = 0
        func add(_ p: CGPoint) {
            points.append(PKStrokePoint(location: p, timeOffset: t, size: CGSize(width: width, height: width),
                                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
            t += 0.004
        }
        for i in outline.indices {
            let p = outline[i]
            if i > 0 {
                let q = outline[i - 1]
                let steps = max(1, Int(dist(p, q) / 6))
                for s in 1..<steps {
                    let f = CGFloat(s) / CGFloat(steps)
                    add(CGPoint(x: q.x + (p.x - q.x) * f, y: q.y + (p.y - q.y) * f))
                }
            }
            add(p)
            // Repeat corner points so the B-spline keeps the corner sharp.
            if corners.contains(i) || i == 0 || i == outline.count - 1 { add(p); add(p) }
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()),
                        transform: .identity, mask: nil)
    }

    // MARK: Geometry helpers

    private static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private static func bounds(_ pts: [CGPoint]) -> CGRect {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    private static func distanceToLine(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let len = dist(a, b)
        guard len > 0.001 else { return dist(p, a) }
        return abs((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)) / len
    }

    /// Lines within 7° of horizontal/vertical snap straight.
    private static func snapAngle(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let len = dist(a, b)
        for target in stride(from: -CGFloat.pi, through: CGFloat.pi, by: CGFloat.pi / 2) {
            if abs(angle - target) < 7 * .pi / 180 {
                return CGPoint(x: a.x + len * cos(target), y: a.y + len * sin(target))
            }
        }
        return b
    }

    private static func resample(_ pts: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        var out = [pts[0]]
        var acc: CGFloat = 0
        for i in 1..<pts.count {
            acc += dist(pts[i], pts[i - 1])
            if acc >= spacing {
                out.append(pts[i])
                acc = 0
            }
        }
        if out.last != pts.last { out.append(pts.last!) }
        return out
    }

    /// Ramer–Douglas–Peucker line simplification.
    private static func rdp(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var maxD: CGFloat = 0
        var index = 0
        for i in 1..<(pts.count - 1) {
            let d = distanceToLine(pts[i], pts.first!, pts.last!)
            if d > maxD { maxD = d; index = i }
        }
        if maxD > epsilon {
            let left = rdp(Array(pts[0...index]), epsilon: epsilon)
            let right = rdp(Array(pts[index...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [pts.first!, pts.last!]
    }

    private static func isRectangular(_ q: [CGPoint]) -> Bool {
        guard q.count == 4 else { return false }
        for i in 0..<4 {
            let a = q[(i + 3) % 4], b = q[i], c = q[(i + 1) % 4]
            let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y), v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
            let cosA = (v1.dx * v2.dx + v1.dy * v2.dy) / max(hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy), 0.001)
            if abs(cosA) > 0.3 { return false }
        }
        return true
    }

    private static func isAxisAligned(_ q: [CGPoint]) -> Bool {
        for i in 0..<q.count {
            let a = q[i], b = q[(i + 1) % q.count]
            let angle = abs(atan2(b.y - a.y, b.x - a.x)).truncatingRemainder(dividingBy: .pi / 2)
            if min(angle, .pi / 2 - angle) > 12 * .pi / 180 { return false }
        }
        return true
    }
}

extension UIImage {
    /// Shrinks big photos so notebooks stay small; never enlarges.
    func scaledDown(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return self }
        let s = maxSide / longest
        let newSize = CGSize(width: (size.width * s).rounded(), height: (size.height * s).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
