import SwiftUI
import UIKit

/// The colours of one theme, each with a light and a dark version.
struct ThemePalette {
    let accent: UIColor
    let action: UIColor
    let background: UIColor
    let sidebar: UIColor
    let tile: UIColor
    /// Behind the pages inside a notebook.
    let desk: UIColor

    init(accent: (String, String), action: (String, String), background: (String, String),
         sidebar: (String, String), tile: (String, String), desk: (String, String)) {
        self.accent = Theme.dynamic(light: accent.0, dark: accent.1)
        self.action = Theme.dynamic(light: action.0, dark: action.1)
        self.background = Theme.dynamic(light: background.0, dark: background.1)
        self.sidebar = Theme.dynamic(light: sidebar.0, dark: sidebar.1)
        self.tile = Theme.dynamic(light: tile.0, dark: tile.1)
        self.desk = Theme.dynamic(light: desk.0, dark: desk.1)
    }
}

/// App themes. Each one tints the library, the sidebar, buttons, the selected tool and
/// the desk behind the pages; notebook covers and ink colours stay as you made them.
enum AppTheme: String, CaseIterable, Identifiable {
    // One colour: the whole library is tinted with the theme's own colour.
    case classic, redWine, latte, mocha, forest, ocean, lavender, rose, midnight
    // Two colours: a main colour for buttons and highlights, on a background of another colour.
    case pistachio, navySand, terracottaSage, plumPeach, tealBlush, mustardPine, cherryCream, lavenderSlate
    /// Two colours you pick yourself.
    case custom

    var id: String { rawValue }

    static let storageKey = "folio.theme"
    /// Set at launch and whenever a theme is picked.
    static var current: AppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .classic

    static let singleColour: [AppTheme] = [.classic, .redWine, .latte, .mocha, .forest, .ocean, .lavender, .rose, .midnight]
    static let twoColour: [AppTheme] = [.pistachio, .navySand, .terracottaSage, .plumPeach, .tealBlush,
                                        .mustardPine, .cherryCream, .lavenderSlate]

    static let customMainKey = "folio.theme.customMain"
    static let customBackgroundKey = "folio.theme.customBackground"
    static var customMain = UserDefaults.standard.string(forKey: customMainKey) ?? "#6E9B4E" { didSet { revision += 1 } }
    static var customBackground = UserDefaults.standard.string(forKey: customBackgroundKey) ?? "#8B5E3C" {
        didSet { revision += 1 }
    }
    /// Changes whenever the custom colours do, so cached colours get worked out again.
    private(set) static var revision = 0

    /// Main colour and background colour of a two-colour theme.
    var duo: (main: String, background: String)? {
        switch self {
        case .pistachio: return ("#6E9B4E", "#8B5E3C")
        case .navySand: return ("#24406E", "#C8A96E")
        case .terracottaSage: return ("#B95A38", "#7F9A7A")
        case .plumPeach: return ("#6D3B6E", "#EBA27F")
        case .tealBlush: return ("#1F7A7A", "#DFA0A4")
        case .mustardPine: return ("#B07D12", "#2F5D4A")
        case .cherryCream: return ("#B3243B", "#DCC79B")
        case .lavenderSlate: return ("#7A5FB0", "#6F7785")
        case .custom: return (Self.customMain, Self.customBackground)
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .redWine: return "Red Wine"
        case .latte: return "Latte"
        case .mocha: return "Mocha"
        case .forest: return "Forest"
        case .ocean: return "Ocean"
        case .lavender: return "Lavender"
        case .rose: return "Rose"
        case .midnight: return "Midnight"
        case .pistachio: return "Pistachio"
        case .navySand: return "Navy & Sand"
        case .terracottaSage: return "Terracotta & Sage"
        case .plumPeach: return "Plum & Peach"
        case .tealBlush: return "Teal & Blush"
        case .mustardPine: return "Mustard & Pine"
        case .cherryCream: return "Cherry & Cream"
        case .lavenderSlate: return "Lavender & Slate"
        case .custom: return "Your Colours"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "Coral and teal"
        case .redWine: return "Deep burgundy"
        case .latte: return "Light brown and cream"
        case .mocha: return "Coffee brown"
        case .forest: return "Calm greens"
        case .ocean: return "Cool blues"
        case .lavender: return "Soft purple"
        case .rose: return "Dusty pink"
        case .midnight: return "Navy and gold"
        case .pistachio: return "Green on brown"
        case .navySand: return "Navy on warm sand"
        case .terracottaSage: return "Clay on sage green"
        case .plumPeach: return "Plum on peach"
        case .tealBlush: return "Teal on blush pink"
        case .mustardPine: return "Mustard on pine green"
        case .cherryCream: return "Cherry red on cream"
        case .lavenderSlate: return "Lavender on slate grey"
        case .custom: return "Pick a main and a background"
        }
    }

    var palette: ThemePalette {
        if let d = duo { return .duo(main: d.main, background: d.background) }
        switch self {
        case .classic:
            return ThemePalette(accent: ("#E8714F", "#EC8264"), action: ("#18AFC9", "#2BBFD8"),
                                background: ("#F7F7F9", "#000000"), sidebar: ("#EDEDF0", "#1C1C1E"),
                                tile: ("#FFFFFF", "#2C2C2E"), desk: ("#E3E3E8", "#111113"))
        case .redWine:
            return ThemePalette(accent: ("#7B2238", "#B4475F"), action: ("#A8324F", "#D06A80"),
                                background: ("#FBF6F5", "#140A0D"), sidebar: ("#F2E4E4", "#241418"),
                                tile: ("#FFFFFF", "#321C22"), desk: ("#EADCDC", "#1A0E12"))
        case .latte:
            return ThemePalette(accent: ("#9C6B43", "#C99A6E"), action: ("#B07A4F", "#D8A87C"),
                                background: ("#FAF5EE", "#16110D"), sidebar: ("#F0E5D6", "#251D16"),
                                tile: ("#FFFCF7", "#31271E"), desk: ("#E9DDCC", "#1C1611"))
        case .mocha:
            return ThemePalette(accent: ("#6F4E37", "#B08868"), action: ("#8B5E3C", "#C79A72"),
                                background: ("#F6F1EC", "#120D0A"), sidebar: ("#E9DFD5", "#211913"),
                                tile: ("#FFFDFB", "#2C221B"), desk: ("#E2D6CA", "#18120E"))
        case .forest:
            return ThemePalette(accent: ("#2F6B4F", "#5FA582"), action: ("#3A8A64", "#6CC497"),
                                background: ("#F4F8F4", "#0B120E"), sidebar: ("#E4EEE6", "#16211A"),
                                tile: ("#FFFFFF", "#1F2D24"), desk: ("#DCE7DE", "#101712"))
        case .ocean:
            return ThemePalette(accent: ("#1F5FA8", "#5B9BE6"), action: ("#1E88C7", "#4FB3EA"),
                                background: ("#F3F7FB", "#07101A"), sidebar: ("#E2ECF6", "#122030"),
                                tile: ("#FFFFFF", "#1A2B3E"), desk: ("#DCE6F0", "#0C1622"))
        case .lavender:
            return ThemePalette(accent: ("#6E52A3", "#A58BDB"), action: ("#8A6CC7", "#B79CF0"),
                                background: ("#F8F5FC", "#100C17"), sidebar: ("#ECE5F6", "#1E1828"),
                                tile: ("#FFFFFF", "#2A2236"), desk: ("#E4DDF0", "#15101E"))
        case .rose:
            return ThemePalette(accent: ("#C9577D", "#E58AA8"), action: ("#D96C90", "#F09AB5"),
                                background: ("#FDF5F7", "#160B0F"), sidebar: ("#F6E4EA", "#27161C"),
                                tile: ("#FFFFFF", "#341F27"), desk: ("#F0DDE3", "#1D1015"))
        case .midnight:
            return ThemePalette(accent: ("#C8962E", "#E8B54D"), action: ("#3F6FD8", "#6E9BFF"),
                                background: ("#EEF1F7", "#0A0F1C"), sidebar: ("#E1E6F1", "#131A2C"),
                                tile: ("#FFFFFF", "#1C2540"), desk: ("#DADFEA", "#0E1426"))
        default:
            return AppTheme.classic.palette
        }
    }
}

extension ThemePalette {
    /// A two-colour theme: `main` for buttons and highlights, `background` tinting everything
    /// behind them (light in light mode, deep in dark mode).
    static func duo(main: String, background bg: String) -> ThemePalette {
        func mix(_ a: String, _ b: String, _ t: CGFloat) -> String {
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            UIColor(hex: a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            UIColor(hex: b).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1).hexString
        }
        let white = "#FFFFFF", black = "#000000"
        return ThemePalette(accent: (main, mix(main, white, 0.22)),
                            action: (mix(main, black, 0.06), mix(main, white, 0.32)),
                            background: (mix(bg, white, 0.72), mix(bg, black, 0.8)),
                            sidebar: (mix(bg, white, 0.55), mix(bg, black, 0.68)),
                            tile: (mix(bg, white, 0.9), mix(bg, black, 0.56)),
                            desk: (mix(bg, white, 0.45), mix(bg, black, 0.75)))
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The picked theme and light/dark setting, shared by the whole app.
@MainActor
final class ThemeCenter: ObservableObject {
    static let themeKey = AppTheme.storageKey
    static let appearanceKey = "folio.appearance"

    @Published var theme: AppTheme {
        didSet {
            AppTheme.current = theme
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
        }
    }
    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    @Published var showPicker = false
    /// Your Colours: the main colour and the background colour.
    @Published var customMain: String {
        didSet {
            AppTheme.customMain = customMain
            UserDefaults.standard.set(customMain, forKey: AppTheme.customMainKey)
        }
    }
    @Published var customBackground: String {
        didSet {
            AppTheme.customBackground = customBackground
            UserDefaults.standard.set(customBackground, forKey: AppTheme.customBackgroundKey)
        }
    }
    /// Redraw key for the whole app: the theme, plus the custom colours when they're in use.
    var appearanceKey: String {
        theme == .custom ? "\(theme.rawValue)-\(customMain)-\(customBackground)" : theme.rawValue
    }

    init() {
        customMain = AppTheme.customMain
        customBackground = AppTheme.customBackground
        theme = AppTheme.current
        appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "") ?? .system
    }
}

/// Themes sheet: light/dark and a grid of themes, each shown as a tiny library.
struct ThemePickerView: View {
    @EnvironmentObject var center: ThemeCenter
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 18)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Appearance", selection: $center.appearance) {
                        ForEach(Appearance.allCases) { a in Text(a.title).tag(a) }
                    }
                    .pickerStyle(.segmented)

                    section("One Colour", "The whole library in one colour.", AppTheme.singleColour)
                    section("Two Colours", "A main colour for buttons and highlights, on a background of another.",
                            AppTheme.twoColour)
                    customCard
                }
                .padding(24)
            }
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.accent)
        .presentationDetents([.large])
    }

    private func section(_ title: String, _ detail: String, _ themes: [AppTheme]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 22, weight: .regular, design: .serif))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(themes) { t in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { center.theme = t }
                    } label: { ThemeCard(theme: t, selected: center.theme == t) }
                    .buttonStyle(PressableStyle(scale: 0.96))
                }
            }
        }
    }

    /// Your Colours: pick any main colour and any background colour.
    private var customCard: some View {
        let main = Binding<Color>(
            get: { Color(hex: center.customMain) },
            set: { c in
                center.customMain = UIColor(c).hexString
                center.theme = .custom
            })
        let back = Binding<Color>(
            get: { Color(hex: center.customBackground) },
            set: { c in
                center.customBackground = UIColor(c).hexString
                center.theme = .custom
            })
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Colours").font(.system(size: 22, weight: .regular, design: .serif))
                Text("Pick a main colour and a background colour.").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { center.theme = .custom }
                } label: { ThemeCard(theme: .custom, selected: center.theme == .custom) }
                .buttonStyle(PressableStyle(scale: 0.96))
                .frame(maxWidth: 260)
                VStack(alignment: .leading, spacing: 14) {
                    ColorPicker(selection: main, supportsOpacity: false) {
                        Label("Main", systemImage: "circle.lefthalf.filled")
                    }
                    ColorPicker(selection: back, supportsOpacity: false) {
                        Label("Background", systemImage: "square.fill")
                    }
                    Text("Tip: a deep main colour on a soft background is easiest to read.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.tileFill))
            }
        }
    }
}

/// A miniature of the library in a theme's colours.
private struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                // Sidebar with a selected tile.
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(uiColor: p.accent))
                        .frame(height: 22)
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(uiColor: p.tile))
                        .frame(height: 22)
                    Capsule().fill(Color.primary.opacity(0.18)).frame(width: 34, height: 5)
                    Capsule().fill(Color.primary.opacity(0.12)).frame(width: 26, height: 5)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(width: 66)
                .frame(maxHeight: .infinity)
                .background(Color(uiColor: p.sidebar))

                // Notebooks and the New button.
                VStack(alignment: .trailing, spacing: 8) {
                    Capsule().fill(Color(uiColor: p.action)).frame(width: 38, height: 13)
                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(i == 0 ? Color(uiColor: p.accent).opacity(0.85)
                                      : (i == 1 ? Color(uiColor: p.action).opacity(0.75) : Color(uiColor: p.tile)))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                                .frame(width: 26, height: 34)
                                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    LinearGradient(colors: [Color(uiColor: p.accent).opacity(0.14), Color(uiColor: p.background)],
                                   startPoint: .top, endPoint: .bottom)
                        .background(Color(uiColor: p.background)))
            }
            .frame(height: 118)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Color(uiColor: p.accent) : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.title).font(.headline).foregroundStyle(.primary)
                    Text(theme.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(uiColor: p.accent))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.tileFill))
        .shadow(color: .black.opacity(selected ? 0.12 : 0.05), radius: selected ? 10 : 4, y: 3)
    }
}
