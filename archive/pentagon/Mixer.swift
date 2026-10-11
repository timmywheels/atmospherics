import SwiftUI
import Observation

/// App-facing state: the dots on the sound field, the noise levels they produce, and playback.
@Observable
final class Mixer {
    static let maxDots = 3

    /// Dot positions in field unit space (see `Field`).
    private(set) var dots: [CGPoint]
    private(set) var levels: [NoiseColor: Float] = [:]
    private(set) var isPlaying = false
    var errorMessage: String?

    @ObservationIgnored private let engine = NoiseEngine()
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        if let flat = defaults.array(forKey: "dots") as? [Double], flat.count >= 2, flat.count % 2 == 0 {
            dots = stride(from: 0, to: flat.count, by: 2).map { CGPoint(x: flat[$0], y: flat[$0 + 1]) }
        } else {
            // First launch: one dot leaning toward pink, with some brown and white in the mix.
            let pink = Field.vertex(for: .pink)
            dots = [CGPoint(x: pink.x * 0.5, y: pink.y * 0.5)]
        }
        recompute()
    }

    func level(_ color: NoiseColor) -> Float { levels[color] ?? 0 }

    // MARK: Dots

    func nearestDot(to p: CGPoint, within radius: CGFloat) -> Int? {
        dots.indices
            .map { ($0, hypot(dots[$0].x - p.x, dots[$0].y - p.y)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
    }

    func moveDot(_ index: Int, to p: CGPoint) {
        dots[index] = Field.clamp(p)
        recompute()
    }

    var canAddDot: Bool { dots.count < Self.maxDots }
    var canRemoveDot: Bool { dots.count > 1 }

    func addDot(at p: CGPoint) {
        guard canAddDot else { return }
        dots.append(Field.clamp(p))
        recompute()
        if !isPlaying { play() }
    }

    func removeDot(_ index: Int) {
        guard canRemoveDot else { return }
        dots.remove(at: index)
        recompute()
    }

    /// The blended color a dot shows at its position.
    func mixColor(at p: CGPoint) -> Color {
        var r = 0.0, g = 0.0, b = 0.0
        for (color, w) in Field.weights(at: p) {
            r += color.rgb.r * w; g += color.rgb.g * w; b += color.rgb.b * w
        }
        return Color(red: r, green: g, blue: b)
    }

    /// The whole mix as one color, weighted by level.
    var overallColor: Color {
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for color in NoiseColor.allCases {
            let w = Double(level(color))
            r += color.rgb.r * w; g += color.rgb.g * w; b += color.rgb.b * w; total += w
        }
        guard total > 0 else { return .white }
        return Color(red: r / total, green: g / total, blue: b / total)
    }

    /// A short name for what's playing, e.g. "Pink & Brown".
    var mixTitle: String {
        let top = NoiseColor.allCases
            .map { ($0, level($0)) }
            .filter { $0.1 > 0.18 }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map(\.0.name)
        switch top.count {
        case 0: return "A little of everything"
        case 1: return "\(top[0]) noise"
        default: return "\(top[0]) & \(top[1])"
        }
    }

    /// Levels in `Field.layout` order, as the shader expects.
    var layoutLevels: [Float] { Field.layout.map { level($0) } }

    /// Dots as [x0, y0, x1, y1, ...] for the shader.
    var flatDots: [Float] { dots.flatMap { [Float($0.x), Float($0.y)] } }

    /// Each dot adds its corner weights; overlapping dots get louder, capped at full.
    private func recompute() {
        var next: [NoiseColor: Float] = [:]
        for dot in dots {
            for (color, w) in Field.weights(at: dot) {
                next[color, default: 0] += Float(w) * 0.8
            }
        }
        for color in NoiseColor.allCases {
            let level = min(1, next[color] ?? 0)
            next[color] = level
            engine.setLevel(level, for: color)
        }
        levels = next
        defaults.set(dots.flatMap { [Double($0.x), Double($0.y)] }, forKey: "dots")
    }

    // MARK: Playback

    func togglePlayback() {
        isPlaying ? stop() : play()
    }

    func play() {
        do {
            try engine.play()
            isPlaying = true
        } catch {
            errorMessage = "Couldn't start audio: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine.stop()
        isPlaying = false
    }
}
