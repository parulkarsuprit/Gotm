import SwiftUI
import UIKit

struct RecordingRowView: View {
    let entry: RecordingEntry
    let index: Int
    let isSelectable: Bool
    let isSelected: Bool
    let isTranscribing: Bool
    let backgroundColor: Color

    private let cardInset: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // Index / selection indicator
            if isSelectable {
                SelectionIndicator(isSelected: isSelected)
                    .frame(width: 20, height: 20)
                    .padding(.top, 4)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                Text("#\(index)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Color(.tertiaryLabel), lineWidth: 0.5))
                    .padding(.top, 4)
            }

            // Main content — left aligned
            // paddingBottom reserves space so content never overlaps the pinned chip overlay
            // chip height ~28pt + cardInset gap = ~48pt minimum clearance
            VStack(alignment: .leading, spacing: 0) {

                // Row 1: title + timestamp
                HStack(alignment: .top, spacing: 8) {
                    if entry.isTitleLoading {
                        Text("Loading…")
                            .font(.custom("InterTight-Regular", size: 30).weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                    } else {
                        Text(entry.name)
                            .font(.custom("InterTight-Regular", size: 30).weight(.medium))
                            .lineLimit(nil)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(relativeDayText(from: entry.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(formattedTime(from: entry.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .fixedSize()
                }

                // Transcript / text preview — natural height, 8pt below title
                if isTranscribing {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.65)
                        Text("Transcribing…")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } else if let transcript = entry.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .padding(.top, 8)
                } else if let text = entry.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .padding(.top, 8)
                }

                // Image mosaic
                if !entry.imageAttachments.isEmpty {
                    ImageMosaicView(attachments: entry.imageAttachments)
                        .padding(.top, 8)
                }

                // File pills
                if !entry.fileAttachments.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(entry.fileAttachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 12))
                                Text(attachment.url.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 48) // clears pinned chip overlay (chip ~28pt + 20pt gap)
        }
        .padding(.top, cardInset)
        .padding(.bottom, cardInset)
        .padding(.leading, 12)
        .padding(.trailing, 20)
        // Chips pinned to bottom — same inset from bottom edge as title has from top edge
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 6) {
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
            .padding(.leading, 12 + 20 + 12) // card leading + index chip width + hstack spacing
            .padding(.bottom, cardInset)
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
        .shadow(color: Color.black.opacity(0.015), radius: 4, x: 0, y: 1)
        .animation(.easeInOut(duration: 0.2), value: isSelectable)
    }


    private func relativeDayText(from date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "MMM d" : "MMM d, yyyy"
        return fmt.string(from: date)
    }

    private func formattedTime(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }
}

private struct ImageMosaicView: View {
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
