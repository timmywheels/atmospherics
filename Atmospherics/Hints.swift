import SwiftUI

/// A few words in a frosted capsule, for a moment: the first-run hints, the weather you just
/// switched to, a mix just added to Favorites.
struct HintBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.label(11))
            .foregroundStyle(Theme.text)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .transition(.opacity.combined(with: .offset(y: 8)))
            .allowsHitTesting(false)
    }
}

extension View {
    /// Shows the mixer's passing word on what you just did ("Added to Favorites…") along the
    /// bottom, `bottom` points up.
    func notices(above bottom: CGFloat) -> some View { modifier(Notices(bottom: bottom)) }
}

private struct Notices: ViewModifier {
    @Environment(Mixer.self) private var mixer
    let bottom: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack {
                if let notice = mixer.notice { HintBubble(text: notice) }
            }
            .padding(.bottom, bottom)
            .animation(.smooth(duration: 0.3), value: mixer.notice)
        }
    }
}
