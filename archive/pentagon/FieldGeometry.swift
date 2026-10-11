import CoreGraphics
import Foundation

/// The sound field is a regular pentagon in unit space: center (0,0), corners at radius 1.
/// Each corner is one noise color; a dot's distance to each corner sets that noise's level.
enum Field {
    /// Clockwise from the top. Neighbors are chosen so adjacent noises blend pleasantly.
    static let layout: [NoiseColor] = [.white, .blue, .green, .brown, .pink]

    static let vertices: [CGPoint] = layout.indices.map { i in
        let angle = -Double.pi / 2 + Double(i) * 2 * .pi / Double(layout.count)
        return CGPoint(x: cos(angle), y: sin(angle))
    }

    static func vertex(for color: NoiseColor) -> CGPoint {
        vertices[layout.firstIndex(of: color)!]
    }

    /// How strongly each corner pulls on a point. Sums to 1.
    static func weights(at p: CGPoint) -> [NoiseColor: Double] {
        var raw: [NoiseColor: Double] = [:]
        for (color, v) in zip(layout, vertices) {
            let dx = Double(p.x - v.x), dy = Double(p.y - v.y)
            raw[color] = exp(-(dx * dx + dy * dy) / 0.5)   // Gaussian falloff, sigma 0.5
        }
        let total = raw.values.reduce(0, +)
        return raw.mapValues { $0 / total }
    }

    // MARK: Containment

    /// Dots live slightly inside the outline so they never sit on the wavy edge.
    private static let inset: CGFloat = 0.9

    static func isInside(_ p: CGPoint, scale: CGFloat = 1) -> Bool {
        let poly = vertices.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            // Clockwise in screen space (y down): inside is where cross >= 0.
            if (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) < 0 { return false }
        }
        return true
    }

    static func clamp(_ p: CGPoint) -> CGPoint {
        if isInside(p, scale: inset) { return p }
        let poly = vertices.map { CGPoint(x: $0.x * inset, y: $0.y * inset) }
        var best = p, bestDistance = CGFloat.infinity
        for i in poly.indices {
            let q = nearest(on: poly[i], poly[(i + 1) % poly.count], to: p)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < bestDistance { best = q; bestDistance = d }
        }
        return best
    }

    /// Distance past the outline, 0 when inside.
    static func distanceOutside(_ p: CGPoint) -> CGFloat {
        let q = clamp(p)
        return hypot(q.x - p.x, q.y - p.y)
    }

    private static func nearest(on a: CGPoint, _ b: CGPoint, to p: CGPoint) -> CGPoint {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / (ab.x * ab.x + ab.y * ab.y)))
        return CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
    }
}
