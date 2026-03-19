import SwiftUI

struct RecordingRowView: View {
    let entry: RecordingEntry
    let isPlaying: Bool
    let playbackProgress: TimeInterval
    let playbackDuration: TimeInterval
    let isSelectable: Bool
    let isSelected: Bool
    let playAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if isSelectable {
                    SelectionIndicator(isSelected: isSelected)
                        .frame(width: 24, height: 24)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Button(action: playAction) {
                    ZStack {
                        Circle()
                            .stroke(Color(.secondarySystemFill), lineWidth: 1)
                            .frame(width: 28, height: 28)
                            .opacity(isPlaying ? 1 : 0)

                        Circle()
                            .trim(from: 0, to: progressFraction)
                            .stroke(Color(.label).opacity(0.7), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 28, height: 28)
                            .opacity(isPlaying ? 1 : 0)

                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(.label))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)

                    Text(relativeDateText(from: entry.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formattedDuration(displayDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.2), value: isSelectable)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if isSelectable {
                    SelectionIndicator(isSelected: isSelected)
                        .frame(width: 24, height: 24)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Button(action: playAction) {
                    ZStack {
                        Circle()
                            .stroke(Color(.secondarySystemFill), lineWidth: 1)
                            .frame(width: 28, height: 28)
                            .opacity(isPlaying ? 1 : 0)

                        Circle()
                            .trim(from: 0, to: progressFraction)
                            .stroke(Color(.label).opacity(0.7), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 28, height: 28)
                            .opacity(isPlaying ? 1 : 0)

                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(.label))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)

                    Text(relativeDateText(from: entry.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formattedDuration(displayDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.2), value: isSelectable)
    }


    private var displayDuration: TimeInterval {
        if entry.duration > 0 {
            return entry.duration
        }
        if isPlaying {
            return max(playbackDuration, playbackProgress)
        }
        return 0
    }

    private var progressFraction: CGFloat {
        guard playbackDuration > 0 else { return 0 }
        return CGFloat(min(max(playbackProgress / playbackDuration, 0), 1))
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func relativeDateText(from date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

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

