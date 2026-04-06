import SwiftUI

struct ComposeBar: View {
    @Bindable var viewModel: ComposeViewModel
    @FocusState.Binding var isTextFieldFocused: Bool
    let isShowingRecordingUI: Bool
    let onNormalRecordTap: () -> Void
    let onShowPermissionAlert: () -> Void
    let onStopQuickRecord: () -> Void

    private var isNormalRecording: Bool {
        (isShowingRecordingUI || viewModel.isRecording) && viewModel.quickRecordState == .idle
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Left slot
            leftSlot

            // Center slot
            centerSlot

            // Right slot
            rightSlot
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                // Red fill expanding from trailing side during quick record
                Capsule()
                    .fill(quickBarFillColor)
                    .scaleEffect(
                        x: (viewModel.quickRecordState == .holding || viewModel.quickRecordState == .locked) ? 1.0 : 0.001,
                        anchor: .trailing
                    )
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
    }

    // MARK: - Left Slot

    @ViewBuilder
    private var leftSlot: some View {
        switch viewModel.quickRecordState {
        case .processing:
            Color.clear.frame(width: 32, height: 32)
        case .holding, .locked:
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 32, height: 32)
                    .scaleEffect(1.0 + viewModel.lockProgress * 0.2)
                Image(systemName: viewModel.quickRecordState == .locked ? "lock.fill" : "lock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .transition(.scale.combined(with: .opacity))
        default:
            if isNormalRecording {
                RecordingDotView()
                    .frame(width: 32, height: 32)
            } else {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        viewModel.showAttachmentMenu.toggle()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Center Slot

    @ViewBuilder
    private var centerSlot: some View {
        switch viewModel.quickRecordState {
        case .processing:
            Text("Processing…")
                .font(.body)
                .foregroundStyle(Color.red.opacity(0.75))
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        case .holding, .locked:
            VStack(spacing: 3) {
                RecordingTimerView(elapsedTime: viewModel.elapsedTime)
                    .foregroundStyle(.white)
                if viewModel.quickRecordState == .holding {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.7 - Double(i) * 0.2))
                                .offset(x: CGFloat(i) * -2 * viewModel.lockProgress)
                        }
                        Text("slide to lock")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        default:
            if isNormalRecording {
                RecordingTimerView(elapsedTime: viewModel.elapsedTime)
                    .frame(maxWidth: .infinity)
            } else {
                TextField("Write a note...", text: $viewModel.draft.text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isTextFieldFocused)
                    .frame(maxWidth: .infinity)
                    .onSubmit { viewModel.submit() }

                if viewModel.draft.hasContent {
                    Button(action: { viewModel.submit() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(.label))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Right Slot

    @ViewBuilder
    private var rightSlot: some View {
        switch viewModel.quickRecordState {
        case .locked:
            Button { onStopQuickRecord() } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 48, height: 48)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.red)
                }
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        case .processing:
            Color.clear.frame(width: 48, height: 48)
        default:
            QuickRecordButton(
                viewModel: viewModel,
                isNormalRecording: isNormalRecording,
                onNormalTap: { onNormalRecordTap() }
            )
        }
    }

    // MARK: - Helpers

    private var quickBarFillColor: Color {
        switch viewModel.quickRecordState {
        case .idle, .processing: return .clear
        case .holding, .locked: return .red
        }
    }
}

// MARK: - Recording Dot

private struct RecordingDotView: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .shadow(color: Color.red.opacity(0.5), radius: isPulsing ? 8 : 3)
            .scaleEffect(isPulsing ? 1.4 : 0.9)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Recording Timer

private struct RecordingTimerView: View {
    let elapsedTime: TimeInterval

    var body: some View {
        Text(formattedElapsedTime(elapsedTime))
            .font(.body)
            .monospacedDigit()
    }

    private func formattedElapsedTime(_ duration: TimeInterval) -> String {
        let t = Int(duration.rounded())
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}
