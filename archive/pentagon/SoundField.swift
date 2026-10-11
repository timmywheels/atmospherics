import SwiftUI

/// Seconds since launch. Shaders need small time values; Float loses precision on epoch seconds.
let appStart = Date()

/// The pentagon you drag dots around. A Metal shader paints the living color field;
/// a Canvas on top draws the wavy outline, mesh, labels and dot cores.
struct SoundField: View {
    @Environment(Mixer.self) private var mixer

    @State private var activeDot: Int?
    @State private var dragPoint: CGPoint?   // raw finger position in unit space, unclamped
    @State private var gestureStarted = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let radius = min(size.width, size.height) / 2 * 0.8
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            TimelineView(.animation(minimumInterval: 1 / 60, paused: !mixer.isPlaying)) { timeline in
                let time = timeline.date.timeIntervalSince(appStart)
                let shape = WavyPentagon(levels: mixer.layoutLevels, playing: mixer.isPlaying, time: time)

                ZStack {
                    Rectangle()
                        .colorEffect(ShaderLibrary.soundField(
                            .float2(size),
                            .float(radius),
                            .float(time),
                            .floatArray(mixer.layoutLevels),
                            .floatArray(mixer.flatDots),
                            .float(mixer.isPlaying ? 1 : 0)
                        ))
                        .mask {
                            Canvas { ctx, _ in
                                ctx.fill(shape.path(scale: 1, center: center, radius: radius), with: .color(.white))
                            }
                        }

                    Canvas { ctx, _ in
                        drawOverlay(in: &ctx, shape: shape, center: center, radius: radius, time: time)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(center: center, radius: radius))
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: mixer.dots.count)
        .accessibilityElement()
        .accessibilityLabel("Sound field")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Gesture

    private var isRemoving: Bool {
        guard activeDot != nil, let p = dragPoint, mixer.canRemoveDot else { return false }
        return Field.distanceOutside(p) > 0.22
    }

    private func dragGesture(center: CGPoint, radius: CGFloat) -> some Gesture {
        func unit(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - center.x) / radius, y: (p.y - center.y) / radius)
        }
        return DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !gestureStarted {
                    gestureStarted = true
                    activeDot = mixer.nearestDot(to: unit(g.startLocation), within: 40 / radius)
                }
                guard let i = activeDot else { return }
                let p = unit(g.location)
                dragPoint = p
                mixer.moveDot(i, to: p)
            }
            .onEnded { g in
                if let i = activeDot {
                    if isRemoving { withAnimation(.snappy) { mixer.removeDot(i) } }
                } else if hypot(g.translation.width, g.translation.height) < 10,
                          Field.isInside(unit(g.location)) {
                    mixer.addDot(at: unit(g.location))
                }
                activeDot = nil
                dragPoint = nil
                gestureStarted = false
            }
    }

    // MARK: Overlay

    private func drawOverlay(in ctx: inout GraphicsContext, shape: WavyPentagon,
                             center: CGPoint, radius: CGFloat, time: Double) {
        func pt(_ u: CGPoint) -> CGPoint {
            CGPoint(x: center.x + u.x * radius, y: center.y + u.y * radius)
        }
        let outline = shape.path(scale: 1, center: center, radius: radius)

        // Soft halo in the mix color, then a crisp hairline.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            layer.stroke(outline, with: .color(mixer.overallColor.opacity(mixer.isPlaying ? 0.75 : 0.35)), lineWidth: 5)
        }

        // Faint mesh.
        var mesh = Path()
        for scale in [0.66, 0.33] as [CGFloat] {
            mesh.addPath(shape.path(scale: scale, center: center, radius: radius, phase: Double(scale) * 3))
        }
        for v in Field.vertices {
            mesh.move(to: center)
            mesh.addLine(to: pt(v))
        }
        ctx.stroke(mesh, with: .color(.white.opacity(0.07)), lineWidth: 0.75)
        ctx.stroke(outline, with: .color(.white.opacity(0.55)), lineWidth: 1)

        // Corner nodes sized by level, and tracked labels.
        for (color, v) in zip(Field.layout, Field.vertices) {
            let level = CGFloat(mixer.level(color))
            let c = pt(v)
            let r = 2.5 + 3.5 * level
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(color.tint))
            ctx.draw(
                Text(color.name.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(color.tint.opacity(0.45 + 0.55 * Double(level))),
                at: pt(CGPoint(x: v.x * 1.2, y: v.y * 1.15))
            )
        }

        // Dot cores. The shader draws their glow and rings.
        for (i, dot) in mixer.dots.enumerated() {
            let removing = i == activeDot && isRemoving
            let p = removing ? pt(dragPoint!) : pt(dot)
            let tint = mixer.mixColor(at: dot)
            let r: CGFloat = i == activeDot ? 10 : 7
            let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))

            if removing {
                ctx.fill(disc, with: .color(.white.opacity(0.3)))
                ctx.draw(Text(Image(systemName: "xmark")).font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white), at: CGPoint(x: p.x, y: p.y - 22))
            } else {
                ctx.fill(disc, with: .color(.white))
                ctx.stroke(disc.insetBy(-3), with: .color(tint.opacity(0.9)), lineWidth: 1.5)
            }
        }
    }

    private var accessibilitySummary: String {
        Field.layout
            .map { ($0, mixer.level($0)) }
            .filter { $0.1 > 0.05 }
            .sorted { $0.1 > $1.1 }
            .map { "\($0.0.name) \(Int($0.1 * 100)) percent" }
            .joined(separator: ", ")
    }
}

private extension Path {
    func insetBy(_ amount: CGFloat) -> Path {
        let b = boundingRect.insetBy(dx: amount, dy: amount)
        return Path(ellipseIn: b)
    }
}

/// Pentagon whose edges wobble like a waveform; louder edges wobble more.
/// Corners stay pinned so the shape always reads as a pentagon.
struct WavyPentagon {
    let levels: [Float]   // Field.layout order
    let playing: Bool
    let time: Double

    func path(scale: CGFloat, center: CGPoint, radius: CGFloat, phase: Double = 0) -> Path {
        let verts = Field.vertices
        let samples = 64
        let t = time + phase
        var path = Path()
        for e in verts.indices {
            let next = (e + 1) % verts.count
            let a = verts[e], b = verts[next]
            let energy = CGFloat(levels[e] + levels[next]) / 2
            let amp = (0.004 + 0.05 * energy * (playing ? 1 : 0)) * scale
            // Outward normal of a clockwise edge (screen space, y down).
            let len = hypot(b.x - a.x, b.y - a.y)
            let normal = CGPoint(x: (b.y - a.y) / len, y: -(b.x - a.x) / len)
            let speed = 3.0 + Double(e) * 0.4

            for k in 0..<samples {
                let s = Double(k) / Double(samples)
                let wave = 0.7 * sin(s * .pi * 4 + t * speed) + 0.3 * sin(s * .pi * 9 - t * speed * 1.6)
                let d = amp * CGFloat(sin(s * .pi) * wave)
                let ux = (a.x + (b.x - a.x) * s) * scale + normal.x * d
                let uy = (a.y + (b.y - a.y) * s) * scale + normal.y * d
                let p = CGPoint(x: center.x + ux * radius, y: center.y + uy * radius)
                e == 0 && k == 0 ? path.move(to: p) : path.addLine(to: p)
            }
        }
        path.closeSubpath()
        return path
    }
}
