import SwiftUI

/// Layers: the shape of what's playing, from the iPhone app. Pull a sound out to hear more of it or
/// in to let it go, drag around it to turn it, and add or take away sounds below.
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

            ShapeField()

            Text(mixer.currentPlaceIsTweaked
                 ? "Your changes to \(mixer.currentPlaceName) are kept"
                 : "Pull a sound out to hear more · drag to turn")
                .font(Theme.label(10.5))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 14)

            SoundSections()
                .padding(.bottom, 8)
        }
    }
}
