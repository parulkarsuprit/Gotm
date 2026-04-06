import SwiftUI

struct RecordingDetailSheet: View {
    let entry: RecordingEntry

    @Environment(\.dismiss) private var dismiss
    @State private var recordingService = RecordingService.shared
    @State private var selectedTag: EntryTag? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Primary audio card with its title + transcript
                    if entry.hasAudio, let audioURL = entry.audioURL {
                        audioCard(
                            url: audioURL,
                            duration: entry.duration,
                            clipTitle: entry.audioTitle,
                            transcript: entry.transcript
                        )
                    }

                    // Additional audio clips — each with their own title + transcript
                    ForEach(Array(entry.audioAttachments.enumerated()), id: \.element.id) { idx, attachment in
                        audioCard(
                            url: attachment.url,
                            duration: nil,
                            clipTitle: attachment.name,
                            transcript: attachment.transcript
                        )
                    }

                    // Image attachments
                    ForEach(entry.imageAttachments) { attachment in
                        if let uiImage = UIImage(contentsOfFile: attachment.url.path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    // File attachments
                    ForEach(entry.fileAttachments) { attachment in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(attachment.url.lastPathComponent)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Text note
                    if let text = entry.text, !text.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note")
                                .font(.headline)
                            highlightedText(text, tag: selectedTag)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    // Tags
                    if !entry.prioritisedTags.isEmpty {
                        tagsSection
                    }
                }
                .padding()
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        recordingService.stopPlayback()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func audioCard(url: URL, duration: TimeInterval?, clipTitle: String?, transcript: String?) -> some View {
        let isThisPlaying = recordingService.isPlaying && recordingService.playingURL == url
        VStack(alignment: .leading, spacing: 12) {
            if let clipTitle {
                Text(clipTitle)
                    .font(.headline)
            }

            HStack(spacing: 14) {
                Button {
                    recordingService.play(url: url)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.label))
                            .frame(width: 44, height: 44)
                        Image(systemName: isThisPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .offset(x: isThisPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    if isThisPlaying {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemFill)).frame(height: 3)
                                Capsule()
                                    .fill(Color(.label))
                                    .frame(width: geo.size.width * progressFraction(for: url), height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                    HStack {
                        Text(isThisPlaying
                             ? formatDur(recordingService.playbackProgress)
                             : formatDur(duration ?? 0))
                        Spacer()
                        Text(formatDate(entry.date))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let transcript, !transcript.isEmpty {
                highlightedText(transcript, tag: selectedTag)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            } else {
                Text("No transcription")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Tags section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                ForEach(entry.prioritisedTags) { tag in
                    TagChip(tag: tag, isSelected: selectedTag?.id == tag.id)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTag = selectedTag?.id == tag.id ? nil : tag
                            }
                        }
                }
            }

            if let selected = selectedTag {
                if selected.triggerText == nil {
                    Text("AI detected this from the overall context of your note.")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                }
            }
        }
    }

    // MARK: - Transcript highlighting

    private func highlightedText(_ text: String, tag: EntryTag?) -> Text {
        guard let trigger = tag?.triggerText else { return Text(text) }
        var attributed = AttributedString(text)
        guard let range = attributed.range(of: trigger, options: .caseInsensitive) else {
            return Text(text)
        }
        attributed[range].backgroundColor = TagChip(tag: tag!).chipColor.opacity(0.28)
        return Text(attributed)
    }

    private func progressFraction(for url: URL) -> CGFloat {
        guard recordingService.isPlaying && recordingService.playingURL == url,
              recordingService.playbackDuration > 0 else { return 0 }
        return CGFloat(min(recordingService.playbackProgress / recordingService.playbackDuration, 1))
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatDur(_ d: TimeInterval) -> String {
        String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}
