import SwiftUI

struct RecordingCard: View {
    let entry: RecordingEntry
    let index: Int
    let isSelectable: Bool
    let isSelected: Bool
    let isTranscribing: Bool
    let backgroundColor: Color
    
    private let actionHandler = TagActionHandler.shared
    private let cardInset: CGFloat = 20
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main content row
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
                
                // Content column
                VStack(alignment: .leading, spacing: 0) {
                    // Title + timestamp
                    HStack(alignment: .top, spacing: 8) {
                        if entry.isTitleLoading {
                            Text("Loading…")
                                .font(.system(size: 24, weight: .semibold, design: .default))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                        } else {
                            Text(entry.name)
                                .font(.system(size: 24, weight: .semibold, design: .default))
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
                    
                    // Transcript preview
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
                    
                    // Tags row - inline with content, NOT overlay
                    if !entry.prioritisedTags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(entry.prioritisedTags.prefix(4))) { tag in
                                TagChip(
                                    tag: tag,
                                    actionState: actionHandler.state(for: entry.id, tagType: tag.type),
                                    onAction: {
                                        actionHandler.executeAction(for: tag, entry: entry)
                                    },
                                    showActionIndicator: actionHandler.canExecuteAction(for: tag.type)
                                )
                            }
                            if entry.tags.count > 4 {
                                Text("+\(entry.tags.count - 4)")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color(.systemFill))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
        .padding(.top, cardInset)
        .padding(.bottom, cardInset)
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
        .shadow(color: Color.black.opacity(0.015), radius: 4, x: 0, y: 1)
        .animation(.easeInOut(duration: 0.2), value: isSelectable)
        .tagActionSheets()
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
        // Use non-breaking space to prevent "2 PM" from wrapping
        return fmt.string(from: date).replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

// MARK: - Selection Indicator

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
