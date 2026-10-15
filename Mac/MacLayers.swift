import SwiftUI

/// Layers: every sound that's playing, each with its own level to set, and below, every sound to
/// add or take away, as in the iPhone app.
struct MacLayers: View {
    @Environment(Mixer.self) private var mixer
    @Environment(MacNavigation.self) private var navigation

    var body: some View {
        VStack(spacing: 0) {
            TuneHeader(reset: { navigation.resetting = true }, save: { navigation.saving = true })
                .frame(maxWidth: 560)
                .padding(.top, 4)

            SoundList()
                .frame(maxWidth: 560)

            SoundSections()
                .padding(.bottom, 8)
        }
    }
}
