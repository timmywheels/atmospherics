import SwiftUI

/// The halo as a still picture, for the widget and Live Activity. `phase` nudges each light
/// a little, so successive widget snapshots drift like the halo in the app.
struct HaloArt: View {
    let lights: [NowPlayingSnapshot.Light]
    var phase: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                ForEach(Array(lights.prefix(4).enumerated()), id: \.offset) { i, light in
                    let angle = Double(i) * 2.1 + 0.4
                    let distance = (1 - light.volume) * side * 0.18
                    let size = side * (0.32 + light.volume * 0.5)
                    let wander = CGPoint(x: sin(phase + Double(i) * 1.9) * side * 0.04,
                                         y: cos(phase * 0.8 + Double(i) * 1.3) * side * 0.035)
                    Circle()
                        .fill(Color.oklch(0.6, 0.14 * light.chroma, light.hue).opacity(0.9))
                        .frame(width: size, height: size)
                        .blur(radius: side * 0.09)
                        .blendMode(.screen)
                        .position(x: center.x + cos(angle) * distance + wander.x,
                                  y: center.y + sin(angle) * distance + wander.y)
                }
            }
            .compositingGroup()
        }
    }
}
