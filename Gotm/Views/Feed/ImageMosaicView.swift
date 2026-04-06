import SwiftUI

struct ImageMosaicView: View {
    let attachments: [MediaAttachment]
    private let gap: CGFloat = 2

    var body: some View {
        let items = Array(attachments.prefix(4))
        let overflow = attachments.count - 4

        switch items.count {
        case 1:
            cell(items[0])
                .frame(maxWidth: .infinity)
                .frame(height: 200)
        case 2:
            HStack(spacing: gap) {
                cell(items[0])
                cell(items[1])
            }
            .frame(height: 160)
        case 3:
            HStack(spacing: gap) {
                cell(items[0])
                VStack(spacing: gap) {
                    cell(items[1])
                    cell(items[2])
                }
            }
            .frame(height: 200)
        default:
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    cell(items[0])
                    cell(items[1])
                }
                HStack(spacing: gap) {
                    cell(items[2])
                    ZStack {
                        cell(items[3])
                        if overflow > 0 {
                            Color.black.opacity(0.45)
                            Text("+\(overflow)")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
    }

    private func cell(_ attachment: MediaAttachment) -> some View {
        Color.clear
            .overlay {
                if let uiImage = UIImage(contentsOfFile: attachment.url.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemFill)
                }
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
