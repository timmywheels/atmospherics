import SwiftUI

/// Marks a scene or a mix as a favorite: a ring, filled in at the middle when it is one. In
/// `glass`, a round glass button like the others beside it.
struct FavoriteToggle: View {
    @Environment(Mixer.self) private var mixer
    let key: String
    var size: CGFloat = 16
    var glass = false
    @State private var taps = 0

    var body: some View {
        let on = mixer.isFavorite(key)
        Button {
            taps += 1
            withAnimation(.smooth(duration: 0.2)) { mixer.toggleFavorite(key) }
        } label: {
            let ring = Image(systemName: on ? "circle.inset.filled" : "circle")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(on ? Theme.text : Theme.text.opacity(glass ? 0.8 : 0.55))
                .contentTransition(.symbolEffect(.replace))
            if glass {
                ring.glassCircle()
            } else {
                ring.frame(width: 40, height: 40).contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .haptic(.tap, trigger: taps)
        .accessibilityLabel(on ? "Remove from favorites" : "Add to favorites")
        #if os(macOS)
        .help(on ? "Remove from favorites" : "Add to favorites")
        #endif
    }
}

extension View {
    /// A round glass button's face: Liquid Glass where there is it (iOS and macOS 26), frosted
    /// glass before.
    @ViewBuilder func glassCircle(_ size: CGFloat = 44) -> some View {
        let face = frame(width: size, height: size).contentShape(Circle())
        if #available(iOS 26.0, macOS 26.0, *) {
            face.glassEffect(.regular.interactive(), in: Circle())
        } else {
            face.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}
