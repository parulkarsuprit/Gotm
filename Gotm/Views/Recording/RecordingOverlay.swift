import SwiftUI

struct RecordingOverlay: View {
    let level: Double

    var body: some View {
        VStack {
            Spacer()

            WaveformView(level: level)
                .frame(height: 34)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(red: 0.91, green: 0.87, blue: 0.80), Color(red: 0.87, green: 0.83, blue: 0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct WaveformView: View {
    let level: Double

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let midY = size.height / 2
                let width = size.width
                let time = context.date.timeIntervalSinceReferenceDate
                let phase = time * 2.2
                let clampedLevel = max(0, min(1, level))
                let boosted = pow(clampedLevel, 0.4)
                let rawAmplitude = boosted * 20
                let baseAmplitude = rawAmplitude < 0.4 ? 0 : rawAmplitude
                let inset: CGFloat = 1.5
                let maxAmplitude = max(0, midY - inset)
                let amplitude = min(Double(maxAmplitude), baseAmplitude)

                var samples: [CGPoint] = []
                let step = max(2, width / 80)
                var x: CGFloat = 0
                while x <= width {
                    let progress = x / width
                    let wave = sin((progress * 8 * Double.pi) + phase)
                    let envelope = max(0, 1 - abs(progress - 0.5) * 1.6)
                    let y = midY + CGFloat(wave) * CGFloat(amplitude) * CGFloat(envelope)
                    samples.append(CGPoint(x: x, y: y))
                    x += step
                }

                var path = Path()
                if let first = samples.first {
                    path.move(to: first)
                    for index in 1..<samples.count {
                        let prev = samples[index - 1]
                        let current = samples[index]
                        let mid = CGPoint(x: (prev.x + current.x) / 2, y: (prev.y + current.y) / 2)
                        path.addQuadCurve(to: mid, control: prev)
                    }
                    if let last = samples.last {
                        path.addLine(to: last)
                    }
                }

                canvas.stroke(
                    path,
                    with: .color(Color(.label).opacity(0.5)),
                    lineWidth: 1
                )
            }
        }
    }
}
