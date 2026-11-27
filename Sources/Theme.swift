import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((v >> 24) & 0xFF) / 255
            g = CGFloat((v >> 16) & 0xFF) / 255
            b = CGFloat((v >> 8) & 0xFF) / 255
            a = CGFloat(v & 0xFF) / 255
        } else {
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255
            a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }
}

enum Theme {
    static let accent = Color(hex: "#E8613C")
    static let shelfBackground = Color(hex: "#F3F0EA")
    static let toolbarBackground = Color(hex: "#FBFAF7")
    static let deskBackground = UIColor(hex: "#E6E2DB")

    static let folderColors: [String] = [
        "#5B8DEF", "#E8613C", "#3FB68B", "#F2B33D",
        "#9B6BDF", "#E5527A", "#3BB4C9", "#7A8699"
    ]

    static let folderIcons: [String] = [
        "folder.fill", "book.closed.fill", "graduationcap.fill", "briefcase.fill",
        "heart.fill", "star.fill", "lightbulb.fill", "pencil.and.ruler.fill",
        "flask.fill", "globe.europe.africa.fill", "music.note", "paintpalette.fill",
        "calendar", "house.fill", "leaf.fill", "camera.fill"
    ]

    static let coverPalettes: [(String, String)] = [
        ("#2E3A59", "#1B2236"), ("#C0392B", "#8E2A20"), ("#2D6A4F", "#1B4332"),
        ("#E9A23B", "#C97C1A"), ("#6C5B7B", "#4A3B58"), ("#F4A6A6", "#E07A7A"),
        ("#3A7CA5", "#255A7C"), ("#D8CFC4", "#B8AC9E"), ("#2B2B2B", "#0E0E0E"),
        ("#88B04B", "#5E8A2E"), ("#F7CAC9", "#92A8D1"), ("#FF9A8B", "#FF6A88")
    ]

    static let penColors: [String] = [
        "#000000", "#3C3C43", "#8E8E93", "#FFFFFF",
        "#1F3A93", "#2F6FDE", "#4FA3F7", "#5AC8C8",
        "#1E7F4F", "#34C759", "#A3D977", "#F7E14A",
        "#F2A33A", "#FF7A2F", "#E53935", "#B71C1C",
        "#FF6FA8", "#C2185B", "#9C5BD6", "#5E35B1",
        "#8D6E63", "#5D4037", "#C9A27E", "#F5DEB3"
    ]
}
