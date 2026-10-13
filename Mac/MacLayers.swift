import SwiftUI

/// Layers: every sound that's playing, each with its own level to set, and below, every sound to
/// add or take away, as in the iPhone app.
struct MacLayers: View {
    @Environment(Mixer.self) private var mixer
    @Environment(MacNavigation.self) private var navigation

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Spacer()
                if mixer.currentPlaceIsTweaked {
                    Button { navigation.resetting = true } label: { Text("Reset") }
                        .help("Put \(mixer.currentPlaceName) back to how it sounds by default")
                }
                Button { navigation.saving = true } label: { Text("Save") }
                    .disabled(mixer.orbs.isEmpty)
                    .help("Save this mix to your Library  ⌘S")
            }
            .font(Theme.label(12, .medium))
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .frame(height: 20)

            SoundList()
                .frame(maxWidth: 560)

            SoundSections()
                .padding(.bottom, 8)
        }
    }
}
