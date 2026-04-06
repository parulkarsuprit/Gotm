import SwiftUI

struct DraftChipsView: View {
    let audioItems: [DraftAudioItem]
    let attachments: [DraftAttachment]
    let onRemoveAudio: (UUID) -> Void
    let onRemoveAttachment: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(audioItems) { item in
                    DraftChip(
                        icon: "waveform",
                        label: item.isTranscribing ? "Processing…" : formatDuration(item.duration),
                        isLoading: item.isTranscribing
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            onRemoveAudio(item.id)
                        }
                    }
                }
                ForEach(attachments) { attachment in
                    if attachment.type == .image, let thumb = attachment.thumbnail {
                        DraftImageChip(image: thumb) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                onRemoveAttachment(attachment.id)
                            }
                        }
                    } else {
                        DraftChip(
                            icon: "doc.fill",
                            label: attachment.fileName,
                            isLoading: false
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                onRemoveAttachment(attachment.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let t = Int(duration.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Chip Components

struct DraftChip: View {
    let icon: String
    let label: String
    let isLoading: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)

            if !isLoading {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(4)
                        .background(Color(.quaternarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }
}

struct DraftImageChip: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button(action: onRemove) {
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground).opacity(0.9))
                        .frame(width: 20, height: 20)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
        }
    }
}
