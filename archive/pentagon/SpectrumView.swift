import SwiftUI

/// A live frequency curve of the current mix, 20 Hz to 20 kHz.
/// Each noise has a known spectral shape; the curve is their level-weighted sum.
struct SpectrumView: View {
    @Environment(Mixer.self) private var mixer

    private static let points = 72
    /// Low to high frequency: where each noise has the most energy.
    private static let gradient = Gradient(colors: [NoiseColor.brown, .pink, .green, .white, .blue].map(\.tint))

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !mixer.isPlaying)) { timeline in
                let time = timeline.date.timeIntervalSince(appStart)
                Canvas { ctx, size in draw(in: &ctx, size: size, time: time) }
            }
            HStack {
                ForEach(["20 Hz", "200", "2k", "20k"], id: \.self) { label in
                    Text(label)
                    if label != "20k" { Spacer() }
                }
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
        }
        .opacity(mixer.isPlaying ? 1 : 0.55)
        .animation(.smooth, value: mixer.isPlaying)
        .accessibilityHidden(true)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let n = Self.points
        let shimmer = mixer.isPlaying ? 1.0 : 0.0
        let points: [CGPoint] = (0..<n).map { i in
            let x = Double(i) / Double(n - 1)
            let f = 20 * pow(1000, x)   // log scale, 20 Hz → 20 kHz
            var db = 10 * log10(power(at: f) + 1e-5)
            db += shimmer * (0.8 * sin(Double(i) * 0.7 + time * 6) + 0.5 * sin(Double(i) * 1.9 - time * 9))
            let y = min(1, max(0, (db + 30) / 42))   // -30 dB … +12 dB
            return CGPoint(x: x * size.width, y: size.height * (1 - y))
        }

        var curve = Path()
        curve.move(to: points[0])
        for i in 1..<n {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            curve.addQuadCurve(to: mid, control: points[i - 1])
        }
        curve.addLine(to: points[n - 1])

        var fill = curve
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.addLine(to: CGPoint(x: 0, y: size.height))
        fill.closeSubpath()

        let horizontal = GraphicsContext.Shading.linearGradient(
            Self.gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
        ctx.drawLayer { layer in
            layer.opacity = 0.22
            layer.fill(fill, with: horizontal)
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.stroke(curve, with: horizontal, lineWidth: 3)
        }
        ctx.stroke(curve, with: horizontal, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
    }

    /// Relative power of the mix at frequency f, normalized so each noise is 1 at 1 kHz
    /// (green at its 500 Hz peak).
    private func power(at f: Double) -> Double {
        var total = 0.0
        for color in NoiseColor.allCases {
            let level = Double(mixer.level(color))
            guard level > 0 else { continue }
            let shape: Double
            switch color {
            case .white: shape = 1
            case .pink:  shape = 1000 / f
            case .brown: shape = pow(1000 / f, 2)
            case .blue:  shape = f / 1000
            case .green:
                let r = f / 500, q = 0.5
                shape = pow(r / q, 2) / (pow(1 - r * r, 2) + pow(r / q, 2))
            }
            total += level * level * shape
        }
        return total
    }
}
