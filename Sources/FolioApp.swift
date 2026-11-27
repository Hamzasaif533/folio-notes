import SwiftUI

@main
struct FolioApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var tools = ToolState()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .environmentObject(tools)
                .tint(Theme.accent)
        }
    }
}
