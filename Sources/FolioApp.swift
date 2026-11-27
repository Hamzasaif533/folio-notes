import SwiftUI

@main
struct FolioApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var tools = ToolState()
    @StateObject private var themes = ThemeCenter()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                // A new theme redraws the whole library in its colours.
                .id(themes.theme)
                .environmentObject(store)
                .environmentObject(tools)
                .environmentObject(themes)
                .tint(Theme.accent)
                .preferredColorScheme(themes.appearance.scheme)
                // Shown from up here so it stays open while the library behind it changes theme.
                .sheet(isPresented: $themes.showPicker) {
                    ThemePickerView()
                        .environmentObject(themes)
                        .preferredColorScheme(themes.appearance.scheme)
                }
        }
    }
}
