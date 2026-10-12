import SwiftUI

/// The whole screen takes on the colors of what's playing: a deep wash of the loudest sounds'
/// hues pooled behind everything, so a scene fills the room instead of sitting in a widget.
/// When the scene changes, the colors drift to their new places.
struct SceneWash: View {
    let orbs: [Orb]

    /// Where the loudest, second and third colors pool, as fractions of the screen.
    private static let spots: [(x: Double, y: Double, reach: Double, strength: Double)] = [
        (0.5, 0.4, 0.85, 1), (0.06, 0.88, 0.7, 0.8), (0.95, 0.06, 0.62, 0.65),
    ]

    var body: some View {
        var seen = Set<SoundKind>()
        let lights = orbs.sorted { $0.volume > $1.volume }.filter { $0.volume > 0.03 && seen.insert($0.kind).inserted }.prefix(3)
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(Array(lights.enumerated()), id: \.element.kind) { i, light in
                    let spot = Self.spots[i]
                    let r = side * spot.reach
                    Circle()
                        .fill(RadialGradient(colors: [Color.oklch(0.38, 0.09, light.kind.hue).opacity(spot.strength), .clear],
                                             center: .center, startRadius: 0, endRadius: r))
                        .frame(width: r * 2, height: r * 2)
                        .position(x: proxy.size.width * spot.x, y: proxy.size.height * spot.y)
                        .opacity(min(1, 0.45 + light.volume))
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 1.8), value: lights.map(\.kind))
        .background(Theme.background)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
