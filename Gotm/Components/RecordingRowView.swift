import SwiftUI
import UIKit

struct RecordingRowView: View {
    let entry: RecordingEntry
    let index: Int
    let isSelectable: Bool
    let isSelected: Bool
    let isTranscribing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if isSelectable {
                SelectionIndicator(isSelected: isSelected)
                    .frame(width: 20, height: 20)
                    .padding(.top, 3)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                Text("\(index)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(width: 20, alignment: .trailing)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(relativeDateText(from: entry.date))
                    if !entry.isTextEntry {
                        Text("·")
                        Text(formattedDuration(entry.duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if isTranscribing {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.65)
                        Text("Transcribing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                } else if let transcript = entry.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }

            Spacer()

            if let mediaURL = entry.mediaURL, entry.mediaType == .image,
               let uiImage = UIImage(contentsOfFile: mediaURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if entry.mediaType == .file {
                Image(systemName: "doc.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.2), value: isSelectable)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func relativeDateText(from date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct SelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.separator), lineWidth: 1)
                .frame(width: 20, height: 20)
            if isSelected {
                Circle()
                    .fill(Color(.label))
                    .frame(width: 10, height: 10)
            }
        }
    }
}
