import SwiftUI
#if os(iOS)
import CoreHaptics
#endif

/// Taps you can feel, but never a jolt. On the iPhone they're Core Haptics patterns, kept light:
/// a soft tick as the form turns under a finger, a crisp tick for a notch or a choice, a tap for a
/// button, and a fuller landing for arriving somewhere, play and pause, or taking a layer away.
/// The wheel's detents are a little firmer and sharper, to feel each word go by. (Without Core Haptics, the system's
/// taps, softened.) On a Mac it's the Force Touch trackpad, felt only while touching it.
enum Haptics {
    enum Feel {
        /// The form turning under a finger: barely there.
        case soft
        /// A slider's notch, a part chosen: crisp.
        case tick
        /// The wheel passing a word: a picker's click.
        case detent
        /// A button: light.
        case tap
        /// Arriving somewhere, play and pause, a layer taken away: a tap with a little weight after it.
        case thud
    }

    static func play(_ feel: Feel = .tap) {
        #if os(iOS)
        if let engine = Engine.shared, (try? engine.play(feel)) != nil { return }
        let impact: (UIImpactFeedbackGenerator.FeedbackStyle, CGFloat) = switch feel {
        case .soft: (.soft, 0.45)
        case .tick: (.rigid, 0.6)
        case .detent: (.rigid, 0.9)
        case .tap: (.medium, 0.6)
        case .thud: (.medium, 0.8)
        }
        UIImpactFeedbackGenerator(style: impact.0).impactOccurred(intensity: impact.1)
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(feel == .tap || feel == .thud ? .generic : .alignment, performanceTime: .now)
        #endif
    }


    #if os(iOS)
    /// The phone's haptic engine, started on first use and again after the system stops it.
    private final class Engine {
        static let shared: Engine? = CHHapticEngine.capabilitiesForHardware().supportsHaptics ? Engine() : nil

        private var engine: CHHapticEngine?
        private var patterns: [Feel: CHHapticPattern] = [:]

        func play(_ feel: Feel) throws {
            let engine = try running()
            let pattern = try patterns[feel] ?? Self.pattern(feel)
            patterns[feel] = pattern
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        }

        private func running() throws -> CHHapticEngine {
            if let engine { try engine.start(); return engine }
            let made = try CHHapticEngine()
            // Haptics only, so it never touches the app's sound.
            made.playsHapticsOnly = true
            made.isAutoShutdownEnabled = true
            made.resetHandler = { [weak self] in self?.engine = nil }
            made.stoppedHandler = { [weak self] _ in self?.engine = nil }
            try made.start()
            engine = made
            return made
        }

        private static func pattern(_ feel: Feel) throws -> CHHapticPattern {
            func hit(_ intensity: Float, _ sharpness: Float, at time: TimeInterval = 0) -> CHHapticEvent {
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ], relativeTime: time)
            }
            func hum(_ intensity: Float, _ sharpness: Float, at time: TimeInterval, for duration: TimeInterval) -> CHHapticEvent {
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ], relativeTime: time, duration: duration)
            }
            let events: [CHHapticEvent] = switch feel {
            case .soft: [hit(0.3, 0.15)]
            case .tick: [hit(0.5, 0.7)]
            case .detent: [hit(0.85, 0.9)]
            case .tap: [hit(0.6, 0.45)]
            case .thud: [hit(0.7, 0.35), hum(0.3, 0.1, at: 0.01, for: 0.07), hit(0.4, 0.25, at: 0.09)]
            }
            return try CHHapticPattern(events: events, parameters: [])
        }
    }
    #endif
}

extension View {
    /// Plays `feel` when `trigger` changes (and `when` agrees), as `sensoryFeedback` does, with the
    /// app's own haptics.
    func haptic<T: Equatable>(_ feel: Haptics.Feel, trigger: T, when: ((T, T) -> Bool)? = nil) -> some View {
        onChange(of: trigger) { old, new in
            if when?(old, new) ?? true { Haptics.play(feel) }
        }
    }
}
