import SwiftUI

/// Marks a scene or a mix as a favorite: a ring, filled in at the middle when it is one.
struct FavoriteToggle: View {
    @Environment(Mixer.self) private var mixer
    let key: String
    var size: CGFloat = 16
    @State private var taps = 0

    var body: some View {
        let on = mixer.isFavorite(key)
        Button {
            taps += 1
            withAnimation(.smooth(duration: 0.2)) { mixer.toggleFavorite(key) }
        } label: {
            Image(systemName: on ? "circle.inset.filled" : "circle")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(on ? Theme.text : Theme.text.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .haptic(.tap, trigger: taps)
        .accessibilityLabel(on ? "Remove from favorites" : "Add to favorites")
        #if os(macOS)
        .help(on ? "Remove from favorites" : "Add to favorites")
        #endif
    }
}
