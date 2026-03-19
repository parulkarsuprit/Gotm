import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color(.systemBackground))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(Color(.label).opacity(isRecording ? 0 : 0.2), lineWidth: 1)
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isRecording ? Color.white : Color(.label))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop Recording" : "Start Recording")
    }
}

