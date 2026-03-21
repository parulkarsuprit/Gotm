import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void
    var size: CGFloat = 64

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color(.systemBackground))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(Color(.separator), lineWidth: 0.5)
                            .opacity(isRecording ? 0 : 1)
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: size * 0.33, weight: .medium))
                    .foregroundStyle(isRecording ? Color.white : Color(.label))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop Recording" : "Start Recording")
    }
}
