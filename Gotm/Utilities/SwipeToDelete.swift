import SwiftUI
import UIKit

// MARK: - Swipe to Reveal Delete

struct SwipeToDelete: ViewModifier {
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0

    private let revealDistance: CGFloat = 80
    private let triggerThreshold: CGFloat = 44
    private let buttonSize: CGFloat = 52

    private var progress: CGFloat {
        min(abs(offset) / revealDistance, 1.0)
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            content
                .offset(x: offset)
                .overlay {
                    HorizontalPanGestureView(
                        onBegan: {
                            startOffset = offset
                        },
                        onChanged: { translation in
                            let proposed = startOffset + translation
                            if proposed >= 0 {
                                offset = 0
                            } else if proposed >= -revealDistance {
                                offset = proposed
                            } else {
                                let extra = -(proposed + revealDistance)
                                offset = -(revealDistance + extra * 0.25)
                            }
                        },
                        onEnded: { translation, velocityX in
                            let final = startOffset + translation
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                                offset = (final < -triggerThreshold || velocityX < -500) ? -revealDistance : 0
                            }
                        }
                    )
                }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 }
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(Color.red))
            }
            .scaleEffect(progress)
            .opacity(progress)
            .padding(.trailing, (revealDistance - buttonSize) / 2)
            .allowsHitTesting(progress > 0.5)
        }
    }
}

// MARK: - Horizontal Pan Gesture

private struct HorizontalPanGestureView: UIViewRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalPanGestureView

        init(parent: HorizontalPanGestureView) {
            self.parent = parent
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            let tx = pan.translation(in: pan.view).x
            let vx = pan.velocity(in: pan.view).x
            switch pan.state {
            case .began:
                parent.onBegan()
            case .changed:
                parent.onChanged(tx)
            case .ended, .cancelled:
                parent.onEnded(tx, vx)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
            guard let pan = gr as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.5
        }

        func gestureRecognizer(
            _ gr: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

// MARK: - View Extension

extension View {
    func swipeToDelete(perform action: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(onDelete: action))
    }
}
