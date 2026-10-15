import SwiftUI

/// Keeps a place, a scene or a mix in Yours, in the Library: a bookmark, filled when it's kept. In
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
            let mark = Image(systemName: on ? "\(Theme.Symbol.keep).fill" : Theme.Symbol.keep)
                .font(.system(size: size, weight: glass ? .medium : .regular))
                .foregroundStyle(on || glass ? Theme.text : Theme.text.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
            if glass {
                mark.glassCircle()
            } else {
                mark.frame(width: 40, height: 40).contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .haptic(.tap, trigger: taps)
        .accessibilityLabel(on ? "Take out of Yours" : "Save to Yours")
        #if os(macOS)
        .help(on ? "Take out of Yours  ⌘D" : "Save to Yours  ⌘D")
        #endif
    }
}

extension View {
    /// A round glass button's face: Liquid Glass where there is it (iOS and macOS 26), frosted
    /// glass before, either way frosted a little white, with a rim that catches the light at the
    /// top left and a soft shadow under it, so it reads as glass on a dark scene.
    @ViewBuilder func glassCircle(_ size: CGFloat = 42) -> some View {
        let face = frame(width: size, height: size).contentShape(Circle())
        let rim = Circle().strokeBorder(
            LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        if #available(iOS 26.0, macOS 26.0, *) {
            face.glassEffect(.regular.tint(.white.opacity(0.14)).interactive(), in: Circle())
                .overlay(rim)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
        } else {
            face.background(.ultraThinMaterial, in: Circle())
                .background(Circle().fill(.white.opacity(0.12)))
                .overlay(rim)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
        }
    }
}
