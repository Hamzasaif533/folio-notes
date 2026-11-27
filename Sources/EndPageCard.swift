import SwiftUI
import PhotosUI

/// What the card after the last page asks for.
enum EndCardAction {
    case newPage, template, importFile, scan, camera
    case image(UIImage)
}

/// Always sits after the last page: a big New Page button, then Template, Image, Import and More.
struct EndPageCard: View {
    let onAction: (EndCardAction) -> Void
    @State private var photo: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 12) {
            Button { onAction(.newPage) } label: {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 30, weight: .regular))
                    Text("New Page").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 400, height: 400)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: "#232325")))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressableStyle(scale: 0.97))

            HStack(spacing: 10) {
                small("doc.text", "Template") { onAction(.template) }
                PhotosPicker(selection: $photo, matching: .images) {
                    smallLabel("photo", "Image")
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                small("square.and.arrow.down", "Import") { onAction(.importFile) }
                Menu {
                    Button { onAction(.newPage) } label: { Label("Add Page", systemImage: "doc.badge.plus") }
                    Button { onAction(.template) } label: { Label("Choose Template…", systemImage: "doc.text") }
                    Button { onAction(.scan) } label: { Label("Scan Document", systemImage: "doc.viewfinder") }
                    Button { onAction(.camera) } label: { Label("Page from Camera", systemImage: "camera") }
                    Button { onAction(.importFile) } label: {
                        Label("Import PDF, Word or PowerPoint", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    smallLabel("ellipsis.circle", "More")
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    onAction(.image(img))
                }
            }
        }
    }

    private func small(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { smallLabel(symbol, title) }
            .buttonStyle(PressableStyle(scale: 0.94))
    }

    private func smallLabel(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 19, weight: .regular))
            Text(title).font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(.white)
        .frame(width: 93, height: 93)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#232325")))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
