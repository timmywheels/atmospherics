import SwiftUI

/// A card in the colors of a set of sounds, for the Library's mixes and Teleport's ideas: a
/// small line at the top, the name at the bottom, and under it either a line of text or the
/// sounds themselves on one line. Outlined when it's what's playing.
struct ColorCard: View {
    let hues: [Double]
    let top: String
    let title: String
    var subtitle: String? = nil
    /// The sounds to show under the title, loudest first, instead of a subtitle.
    var sounds: [Orb]? = nil
    var badge: String? = nil
    var outlined = false
    var minHeight: CGFloat = 132
    /// Room kept clear at the bottom right, for a control laid over the card.
    var trailingRoom: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(top)
                    .font(Theme.label(11, .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(Theme.label(10, .medium))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 9)
                        .background(Capsule().fill(.black.opacity(0.3)))
                }
            }
            Spacer(minLength: 18)
            Group {
                Text(title)
                    .font(Theme.body(21))
                    .lineLimit(1)
                if let sounds {
                    LayerStrip(orbs: sounds, color: .white.opacity(0.68))
                        .padding(.top, 6)
                } else if let subtitle {
                    Text(subtitle)
                        .font(Theme.label(10.5))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .padding(.top, 4)
                }
            }
            .padding(.trailing, trailingRoom)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background { CardWash(hues: hues) }
        .clipShape(shape)
        .overlay { if outlined { shape.strokeBorder(.white.opacity(0.6), lineWidth: 1.2) } }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

/// The colors of a card: its loudest sound's hue, glowing, over a deeper second and third.
struct CardWash: View {
    let hues: [Double]

    var body: some View {
        let first = hues.first ?? 250
        let second = hues.count > 1 ? hues[1] : first
        let third = hues.count > 2 ? hues[2] : second
        ZStack {
            LinearGradient(colors: [.oklch(0.4, 0.085, first), .oklch(0.27, 0.06, second)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.oklch(0.62, 0.12, first).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.8, y: 0.25), startRadius: 0, endRadius: 150)
            RadialGradient(colors: [.oklch(0.55, 0.11, third).opacity(0.35), .clear],
                           center: UnitPoint(x: 0.15, y: 1), startRadius: 0, endRadius: 130)
        }
        .animation(.smooth(duration: 0.4), value: hues)
    }
}
