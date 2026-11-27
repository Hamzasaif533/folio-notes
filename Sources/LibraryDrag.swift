import SwiftUI

/// Dragging notebooks and folders around the library: drop them on a folder to move
/// them in, on Unfiled / Folders to take them out, or on Trash to throw notebooks away.
enum LibraryDrag {
    static let notebookPrefix = "folio-notebooks:"
    static let folderPrefix = "folio-folder:"

    static func payload(notebooks ids: [UUID]) -> String {
        notebookPrefix + ids.map(\.uuidString).joined(separator: ",")
    }

    static func payload(folder id: UUID) -> String { folderPrefix + id.uuidString }

    enum Target: Equatable {
        /// A folder, or the top level (nil).
        case folder(UUID?)
        case trash
    }

    /// Moves what was dropped. Returns false when nothing could go there.
    @MainActor
    static func drop(_ items: [String], on target: Target, store: LibraryStore) -> Bool {
        var moved = false
        for item in items {
            if item.hasPrefix(notebookPrefix) {
                let ids = item.dropFirst(notebookPrefix.count).split(separator: ",").compactMap { UUID(uuidString: String($0)) }
                for id in ids {
                    guard let nb = store.notebook(id) else { continue }
                    switch target {
                    case .folder(let f):
                        guard nb.folderId != f || nb.isTrashed else { continue }
                        if nb.isTrashed { store.restore(id) }
                        store.moveNotebook(id, to: f)
                    case .trash:
                        guard !nb.isTrashed else { continue }
                        store.moveToTrash(id)
                    }
                    moved = true
                }
            } else if item.hasPrefix(folderPrefix),
                      let id = UUID(uuidString: String(item.dropFirst(folderPrefix.count))),
                      case .folder(let parent) = target,
                      let f = store.folder(id), f.parentId != parent, parent != id {
                let before = store.folder(id)?.parentId
                store.moveFolder(id, to: parent)
                if store.folder(id)?.parentId != before { moved = true }
            }
        }
        if moved { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        return moved
    }
}

/// Makes a view take dropped notebooks / folders, glowing while something is held over it.
struct LibraryDropTarget: ViewModifier {
    let target: LibraryDrag.Target
    let store: LibraryStore
    var cornerRadius: CGFloat = 16
    @State private var over = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.accent, lineWidth: 3)
                    .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.accent.opacity(0.12)))
                    .padding(-4)
                    .opacity(over ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .scaleEffect(over ? 1.04 : 1)
            .animation(.snappy(duration: 0.18), value: over)
            .dropDestination(for: String.self) { items, _ in
                over = false
                return withAnimation(.snappy) { LibraryDrag.drop(items, on: target, store: store) }
            } isTargeted: { over = $0 }
    }
}

extension View {
    func libraryDropTarget(_ target: LibraryDrag.Target, store: LibraryStore, cornerRadius: CGFloat = 16) -> some View {
        modifier(LibraryDropTarget(target: target, store: store, cornerRadius: cornerRadius))
    }
}
