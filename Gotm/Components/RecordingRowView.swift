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
                if entry.isTitleLoading {
                    Text("Loading…")
                        .font(.body.italic())
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(entry.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(relativeDateText(from: entry.date))
                    if entry.hasAudio {
                        Text("·")
                        Text(formattedDuration(entry.duration))
                    }
                    // Show item count badge for mixed entries
                    if entry.totalItemCount > 1 {
                        entryTypeBadges
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !entry.prioritisedTags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(Array(entry.prioritisedTags.prefix(2))) { tag in
                            TagChip(tag: tag)
                        }
                        if entry.tags.count > 2 {
                            Text("+\(entry.tags.count - 2)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(.systemFill))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }

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
                } else if let text = entry.text, !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }

            Spacer()

            // Right thumbnail: first image or file icon or audio icon
            if let firstImage = entry.imageAttachments.first,
               let uiImage = UIImage(contentsOfFile: firstImage.url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if !entry.fileAttachments.isEmpty {
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

    @ViewBuilder
    private var entryTypeBadges: some View {
        let count = entry.totalItemCount
        Text("· \(count) item\(count == 1 ? "" : "s")")
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

private struct TagChip: View {
    let tag: EntryTag

    var body: some View {
        Text(tag.type.label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(chipColor.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(chipColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var chipColor: Color {
        switch tag.type {
        case .event:     return Color(red: 0.27, green: 0.52, blue: 0.93)
        case .reminder:  return Color(red: 0.95, green: 0.67, blue: 0.20)
        case .action:    return Color(red: 0.95, green: 0.55, blue: 0.20)
        case .idea:      return Color(red: 0.25, green: 0.72, blue: 0.45)
        case .question:  return Color(red: 0.42, green: 0.35, blue: 0.82)
        case .decision:  return Color(red: 0.20, green: 0.67, blue: 0.67)
        case .person:    return Color(red: 0.55, green: 0.55, blue: 0.60)
        case .reference: return Color(red: 0.55, green: 0.55, blue: 0.60)
        case .purchase:  return Color(red: 0.95, green: 0.67, blue: 0.20)
        case .money:     return Color(red: 0.45, green: 0.62, blue: 0.45)
        }
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
