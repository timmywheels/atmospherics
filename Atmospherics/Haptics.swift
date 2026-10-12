import SwiftUI

/// A tap you can feel, for actions that happen in code rather than through `sensoryFeedback`:
/// the phone's haptic engine, or on a Mac the Force Touch trackpad (felt only while touching it).
enum Haptics {
    enum Weight { case light, medium }

    static func tap(_ weight: Weight = .medium) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: weight == .light ? .light : .medium).impactOccurred()
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(weight == .light ? .alignment : .generic, performanceTime: .now)
        #endif
    }
}
