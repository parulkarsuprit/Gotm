import SwiftUI

struct AttachmentMenuView: View {
    @Bindable var viewModel: ComposeViewModel
    let onDismiss: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            }

        VStack(alignment: .leading, spacing: 0) {
            menuButton("Photos & Videos", icon: "photo.on.rectangle") {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
                viewModel.showPhotoPicker = true
            }
            Divider().padding(.leading, 48)
            menuButton("Files & Documents", icon: "folder") {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
                viewModel.showFileImporter = true
            }
            Divider().padding(.leading, 48)
            menuButton("Camera", icon: "camera") {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    viewModel.showCamera = true
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(width: 230)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, 16)
        .padding(.bottom, 2)
        .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
    }

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
