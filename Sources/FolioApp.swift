import SwiftUI

@main
struct FolioApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var tools = ToolState()
    @StateObject private var themes = ThemeCenter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                // A new theme redraws the whole library in its colours.
                .id(themes.appearanceKey)
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
                // "Open in Folio" and the share sheet.
                .onOpenURL { url in ImportInbox.shared.receive(url) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { ImportInbox.shared.scan() }
                }
        }
    }
}
