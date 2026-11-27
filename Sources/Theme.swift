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
    static func dynamic(light: String, dark: String) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }

    /// Coral: selected sidebar tiles.
    static let accent = Color(hex: "#E8714F")
    /// Cyan: primary actions and the selected tool.
    static let action = Color(hex: "#18AFC9")
    static let libraryBackground = Color(uiColor: dynamic(light: "#F7F7F9", dark: "#000000"))
    static let sidebarPanel = Color(uiColor: dynamic(light: "#EDEDF0", dark: "#1C1C1E"))
    static let tileFill = Color(uiColor: dynamic(light: "#FFFFFF", dark: "#2C2C2E"))
    static let shelfBackground = libraryBackground
    static let deskBackground = dynamic(light: "#E3E3E8", dark: "#111113")

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

    /// (top colour, bottom colour, spine colour)
    static let coverPalettes: [(String, String, String)] = [
        ("#FFD43B", "#FFC300", "#F0476B"), ("#2E3A59", "#1B2236", "#E9A23B"),
        ("#C0392B", "#8E2A20", "#2B2B2B"), ("#2D6A4F", "#1B4332", "#D8CFC4"),
        ("#6C5B7B", "#4A3B58", "#F4A6A6"), ("#F4A6A6", "#E07A7A", "#6C5B7B"),
        ("#3A7CA5", "#255A7C", "#FFD43B"), ("#D8CFC4", "#B8AC9E", "#8E2A20"),
        ("#2B2B2B", "#0E0E0E", "#E8714F"), ("#88B04B", "#5E8A2E", "#F7E14A"),
        ("#F7CAC9", "#92A8D1", "#FFFFFF"), ("#FF9A8B", "#FF6A88", "#2E3A59")
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
