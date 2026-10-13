import SwiftUI

/// A tap you can feel, for actions that happen in code rather than through `sensoryFeedback`:
/// the phone's haptic engine, or on a Mac the Force Touch trackpad (felt only while touching it).
enum Haptics {
    enum Weight { case light, medium }

    static func tap(_ weight: Weight = .medium) {
        #if os(iOS)
        // A step firmer than the names say, so a tap is felt rather than guessed at.
        UIImpactFeedbackGenerator(style: weight == .light ? .medium : .heavy).impactOccurred(intensity: 1)
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(weight == .light ? .alignment : .generic, performanceTime: .now)
        #endif
    }
}
