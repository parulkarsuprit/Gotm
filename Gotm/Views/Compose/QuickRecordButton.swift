import SwiftUI

struct QuickRecordButton: View {
    @Bindable var viewModel: ComposeViewModel
    let isNormalRecording: Bool
    let onNormalTap: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(isNormalRecording ? Color.red : Color(.systemBackground))
                .frame(width: 48, height: 48)
                .overlay(
                    Circle()
                        .stroke(Color(.separator), lineWidth: 0.5)
                        .opacity(isNormalRecording ? 0 : 1)
                )
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isNormalRecording ? Color.white : Color(.label))
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // First touch: arm the long-press timer
                    if viewModel.quickPressTask == nil && viewModel.quickRecordState == .idle {
                        viewModel.quickPressStart = Date()
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.prepare()
                        viewModel.quickPressTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                            guard !Task.isCancelled else { return }
                            generator.impactOccurred()
                            viewModel.startQuickRecord()
                        }
                    }
                    // Handle swipe-to-lock when holding
                    if viewModel.quickRecordState == .holding {
                        viewModel.quickDragOffset = min(0, value.translation.width)
                        if viewModel.quickDragOffset < -viewModel.lockThreshold {
                            viewModel.lockQuickRecord()
                        }
                    }
                }
                .onEnded { _ in
                    viewModel.quickDragOffset = 0
                    let pressDuration = viewModel.quickPressStart.map { Date().timeIntervalSince($0) } ?? 1.0
                    viewModel.quickPressStart = nil
                    if viewModel.quickRecordState == .holding {
                        // Will be handled by parent
                    } else if viewModel.quickRecordState == .locked {
                        // Locked = hands-free, finger release does nothing
                    } else if pressDuration < 0.2 {
                        // Genuine short tap (< 200ms): cancel timer and do normal action
                        viewModel.quickPressTask?.cancel()
                        viewModel.quickPressTask = nil
                        onNormalTap()
                    } else {
                        // Press was long enough that the task may be mid-flight
                        viewModel.quickPressTask?.cancel()
                        viewModel.quickPressTask = nil
                    }
                }
        )
    }
}
