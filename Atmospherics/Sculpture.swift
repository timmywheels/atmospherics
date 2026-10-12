import MetalKit
import SwiftUI

// The soundscape as a sculpture: a soft body of light for each sound, bigger and higher the
// louder it is, merging where sounds are near. On the home screen it's a small form that turns
// and drifts; in Layers it's the same sounds standing on the field, to be moved about. Drawn by
// `SculptureShader` on the GPU.

/// The camera the sculpture is seen through, by the shader and by the labels drawn over it:
/// turned (yaw), tilted (pitch, 0 is side on), in perspective, looking at the middle of the view.
/// The ground is the field's disc, radius 1 at the rim, with height going up.
struct SculptureCamera {
    var yaw: Double
    var pitch: Double
    var size: CGSize
    var distance = 3.4
    /// How far either side of the middle the view reaches, in world units.
    var extent = 1.12

    var focal: Double { max(1, (Double(size.width) / 2 - 18) * distance / extent) }
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.5) }

    func project(_ x: Double, _ y: Double, _ z: Double) -> (point: CGPoint, depth: Double) {
        let x1 = x * cos(yaw) - z * sin(yaw)
        let z1 = x * sin(yaw) + z * cos(yaw)
        let y2 = y * cos(pitch) + z1 * sin(pitch)
        let z2 = -y * sin(pitch) + z1 * cos(pitch)
        let s = focal / (distance + z2)
        return (CGPoint(x: center.x + x1 * s, y: center.y - y2 * s), z2)
    }

    /// How long a world length looks on screen at a depth.
    func scale(atDepth depth: Double) -> Double { focal / (distance + depth) }

    /// The spot at height `h` that's under a point on screen.
    func ground(under p: CGPoint, height h: Double) -> (x: Double, z: Double)? {
        let a = (p.x - center.x) / focal, b = (center.y - p.y) / focal
        let denominator = b * cos(pitch) - sin(pitch)
        guard abs(denominator) > 1e-4 else { return nil }
        let z1 = (h * cos(pitch) - b * (distance - h * sin(pitch))) / denominator
        let z2 = -h * sin(pitch) + z1 * cos(pitch)
        let x1 = a * (distance + z2)
        return (x1 * cos(yaw) + z1 * sin(yaw), -x1 * sin(yaw) + z1 * cos(yaw))
    }
}

/// How sounds become bodies.
enum SculptureStyle {
    /// A compact form that drifts and breathes, for the home screen.
    case home
    /// Each sound standing where it is on the field, for Layers.
    case layers

    /// Where a sound's body is and how big, at a moment.
    func body(of orb: Orb, at time: Double) -> (center: SIMD3<Double>, radius: Double) {
        let v = orb.volume
        let x = (orb.x - 0.5) * 2, z = (orb.y - 0.5) * 2
        switch self {
        case .layers:
            // Quiet sounds sit low on the ground; loud ones are bigger and rise.
            let r = 0.06 + 0.17 * v
            return (SIMD3(x, r * 0.45 + 0.26 * pow(v, 1.1), z), r)
        case .home:
            let seed = Double(SoundKind.allCases.firstIndex(of: orb.kind) ?? 0)
            let drift = SIMD3(sin(time * 0.23 + seed * 1.7), sin(time * 0.19 + seed * 2.3) * 0.6,
                              cos(time * 0.21 + seed * 1.1)) * 0.04
            let breathe = 1 + 0.035 * sin(time * 0.5 + seed)
            let r = (0.15 + 0.27 * v) * breathe
            return (SIMD3(x * 0.55, 0.3 * v - 0.12, z * 0.55) + drift, r)
        }
    }
}

extension SoundKind {
    /// The sound's light in the sculpture, in linear RGB.
    var sculptureColor: SIMD3<Float> { Self.linear(0.72, 0.15 * chroma, hue) }

    private static func linear(_ l: Double, _ c: Double, _ h: Double) -> SIMD3<Float> {
        let a = c * cos(h * .pi / 180), b = c * sin(h * .pi / 180)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        func clamp(_ x: Double) -> Float { Float(min(1, max(0, x))) }
        return SIMD3(clamp(4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S),
                     clamp(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S),
                     clamp(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S))
    }
}

// MARK: - The view

/// The sculpture of a set of sounds. `animated` keeps it drawing (the home form turns and drifts);
/// otherwise it draws only when something changes.
struct SculptureView: View {
    let orbs: [Orb]
    var style: SculptureStyle = .home
    var yaw: Double = 0
    var pitch: Double = 0.55
    var extent: Double = 1.12
    var ground = false
    var animated = true
    /// Brighter for a moment when lightning strikes.
    var exposure: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SculptureLayer(settings: .init(orbs: orbs, style: style, yaw: yaw, pitch: pitch, extent: extent, ground: ground,
                                       animated: animated, still: reduceMotion, exposure: exposure))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// What the renderer needs from SwiftUI.
struct SculptureSettings {
    var orbs: [Orb]
    var style: SculptureStyle
    var yaw: Double
    var pitch: Double
    var extent: Double
    var ground: Bool
    var animated: Bool
    var still: Bool
    var exposure: Double
}

#if os(iOS)
private struct SculptureLayer: UIViewRepresentable {
    let settings: SculptureSettings

    func makeCoordinator() -> SculptureRenderer { SculptureRenderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.configure(view)
        view.isOpaque = false
        view.backgroundColor = .clear
        // Soft light doesn't need every pixel: half the screen's resolution.
        view.contentScaleFactor = max(1, UIScreen.main.scale / 2)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(settings, in: view)
    }

    static func dismantleUIView(_ view: MTKView, coordinator: SculptureRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}
#else
private struct SculptureLayer: NSViewRepresentable {
    let settings: SculptureSettings

    func makeCoordinator() -> SculptureRenderer { SculptureRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.configure(view)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        // Soft light doesn't need every pixel: one drawable pixel per point.
        view.autoResizeDrawable = false
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(settings, in: view)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: SculptureRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}
#endif

// MARK: - The renderer

/// Draws the sculpture with `SculptureShader`. Bodies glide to where they should be, so a new
/// scene grows in rather than jumping.
final class SculptureRenderer: NSObject, MTKViewDelegate {
    private var settings = SculptureSettings(orbs: [], style: .home, yaw: 0, pitch: 0.55, extent: 1.12, ground: false,
                                             animated: true, still: false, exposure: 1)
    private var current: [SoundKind: (center: SIMD3<Double>, radius: Double)] = [:]
    private var lastFrame: CFTimeInterval?
    private var pipeline: MTLRenderPipelineState?
    private var queue: MTLCommandQueue?

    private struct Uniforms {
        var bounds: SIMD4<Float>
        var size: SIMD2<Float>
        var center: SIMD2<Float>
        var focal: Float, distance: Float, yaw: Float, pitch: Float
        var smoothness: Float, glow: Float, ground: Float, time: Float
        var count: Int32, exposure: Float, wobble: Float = 0, pad1: Float = 0
    }

    private struct Blob {
        var sphere: SIMD4<Float>
        var color: SIMD4<Float>
    }

    /// Compiled once for the app (the system compiles the shader the first time it's needed).
    private static var compiled: [ObjectIdentifier: MTLRenderPipelineState] = [:]

    func configure(_ view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 30
        view.delegate = self
        queue = device.makeCommandQueue()
        pipeline = Self.pipeline(for: device, format: view.colorPixelFormat)
    }

    private static func pipeline(for device: MTLDevice, format: MTLPixelFormat) -> MTLRenderPipelineState? {
        let key = ObjectIdentifier(device)
        if let cached = compiled[key] { return cached }
        do {
            let library = try device.makeLibrary(source: SculptureShader.source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "sculptureVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "sculptureFragment")
            descriptor.colorAttachments[0].pixelFormat = format
            let state = try device.makeRenderPipelineState(descriptor: descriptor)
            compiled[key] = state
            return state
        } catch {
            print("Sculpture shader failed: \(error)")
            return nil
        }
    }

    func update(_ settings: SculptureSettings, in view: MTKView) {
        let snap = !settings.animated
        self.settings = settings
        view.isPaused = !settings.animated
        view.enableSetNeedsDisplay = !settings.animated
        if snap { current = [:] }
        #if os(iOS)
        view.setNeedsDisplay()
        #else
        view.needsDisplay = true
        #endif
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        #if os(macOS)
        let wanted = CGSize(width: view.bounds.width.rounded(), height: view.bounds.height.rounded())
        if view.drawableSize != wanted, wanted.width > 0, wanted.height > 0 { view.drawableSize = wanted }
        #endif
        guard let pipeline, let queue, view.bounds.width > 1, view.bounds.height > 1,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        let now = CACurrentMediaTime()
        let time = settings.still ? 0 : now
        step(to: settings.orbs, at: time, now: now)

        var blobs: [Blob] = current.sorted { $0.value.radius > $1.value.radius }.prefix(12).map { kind, body in
            let c = kind.sculptureColor
            return Blob(sphere: SIMD4(Float(body.center.x), Float(body.center.y), Float(body.center.z), Float(body.radius)),
                        color: SIMD4(c, 1))
        }
        // A sphere around them all and their glow, so the shader only works where they are.
        var middle = SIMD3<Double>(0, 0, 0)
        for b in blobs { middle += SIMD3(Double(b.sphere.x), Double(b.sphere.y), Double(b.sphere.z)) }
        if !blobs.isEmpty { middle /= Double(blobs.count) }
        let reach = blobs.map { b -> Double in
            let d = SIMD3(Double(b.sphere.x), Double(b.sphere.y), Double(b.sphere.z)) - middle
            return (d * d).sum().squareRoot() + Double(b.sphere.w)
        }.max() ?? 0

        let turning = settings.style == .home && !settings.still ? now * 0.06 : 0
        let camera = SculptureCamera(yaw: settings.yaw + turning, pitch: settings.pitch, size: view.bounds.size,
                                     extent: settings.extent)
        let scale = Double(view.drawableSize.width / view.bounds.width)
        var uniforms = Uniforms(
            bounds: SIMD4(Float(middle.x), Float(middle.y), Float(middle.z), Float(reach + 0.45)),
            size: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            center: SIMD2(Float(camera.center.x * scale), Float(camera.center.y * scale)),
            focal: Float(camera.focal * scale), distance: Float(camera.distance),
            yaw: Float(camera.yaw), pitch: Float(camera.pitch),
            smoothness: settings.style == .home ? 0.32 : 0.16, glow: settings.style == .home ? 0.7 : 0.45,
            ground: settings.ground ? 1 : 0, time: Float(time.truncatingRemainder(dividingBy: 10_000)),
            count: Int32(blobs.count), exposure: Float(settings.exposure),
            wobble: settings.style == .home && !settings.still ? 1 : 0)

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        if blobs.isEmpty { blobs = [Blob(sphere: .zero, color: .zero)] }
        encoder.setFragmentBytes(&blobs, length: MemoryLayout<Blob>.stride * blobs.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Moves each body toward where its sound puts it; new sounds grow in, gone ones shrink away.
    private func step(to orbs: [Orb], at time: Double, now: CFTimeInterval) {
        var targets: [SoundKind: (center: SIMD3<Double>, radius: Double)] = [:]
        for orb in orbs where orb.volume > 0.02 {
            let body = settings.style.body(of: orb, at: time)
            if let existing = targets[orb.kind], existing.radius >= body.radius { continue }
            targets[orb.kind] = body
        }
        let dt = min(0.1, now - (lastFrame ?? now))
        lastFrame = now
        // The first frame, and anything not animated, shows things where they are.
        guard settings.animated, !current.isEmpty else {
            current = targets
            return
        }
        let ease = 1 - exp(-dt * 4)
        for (kind, target) in targets {
            let from = current[kind] ?? (target.center, 0)
            current[kind] = (from.center + (target.center - from.center) * ease, from.radius + (target.radius - from.radius) * ease)
        }
        for (kind, body) in current where targets[kind] == nil {
            let r = body.radius * (1 - ease)
            current[kind] = r < 0.004 ? nil : (body.center, r)
        }
    }
}
