import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the Atmospherics icon: the Now Playing halo, exactly as the app draws it
// (same layout rule, colors and screen blending), scaled up to fill the icon.
let size = 1024
let S = CGFloat(size)
let out = CommandLine.arguments[1]

func oklch(_ l: Double, _ c: Double, _ h: Double, _ alpha: CGFloat = 1) -> CGColor {
    let a = c * cos(h * .pi / 180), b = c * sin(h * .pi / 180)
    let l_ = l + 0.3963377774 * a + 0.2158037573 * b
    let m_ = l - 0.1055613458 * a - 0.0638541728 * b
    let s_ = l - 0.0894841775 * a - 1.2914855480 * b
    let L = l_ * l_ * l_, M = m_ * m_ * m_, Sv = s_ * s_ * s_
    func enc(_ x: Double) -> CGFloat {
        let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        return CGFloat(min(1, max(0, v)))
    }
    return CGColor(srgbRed: enc(4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * Sv),
                   green: enc(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * Sv),
                   blue: enc(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * Sv),
                   alpha: alpha)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func makeContext() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// The "Attic Rain" mix: brown, rain, wind, thunder, loudest first — as in the app.
// In the app each light sits (1 - v) * 70 pt from center at angle i * 2.1 + 0.4,
// with diameter 90 + v * 200 pt and an 18 pt blur. k scales those points to the icon.
let orbs: [(hue: Double, v: CGFloat)] = [(55, 0.72), (235, 0.57), (175, 0.37), (290, 0.12)]
let k: CGFloat = 2.9
// Center the halo's bounding box on the icon (the app centers its origin point instead).
let center: CGPoint = {
    var minX = CGFloat.infinity, maxX = -CGFloat.infinity, minY = CGFloat.infinity, maxY = -CGFloat.infinity
    for (i, orb) in orbs.enumerated() {
        let angle = CGFloat(i) * 2.1 + 0.4
        let d = (1 - orb.v) * 70 * k, r = (90 + orb.v * 200) * k / 2
        let x = cos(angle) * d, y = -sin(angle) * d
        minX = min(minX, x - r); maxX = max(maxX, x + r); minY = min(minY, y - r); maxY = max(maxY, y + r)
    }
    return CGPoint(x: S / 2 - (minX + maxX) / 2, y: S / 2 - (minY + maxY) / 2)
}()

let glow = makeContext()
glow.setBlendMode(.screen)
for (i, orb) in orbs.enumerated() {
    let angle = CGFloat(i) * 2.1 + 0.4
    let d = (1 - orb.v) * 70 * k
    let r = (90 + orb.v * 200) * k / 2
    // CG's y axis points up; flip so the layout matches the app.
    let p = CGPoint(x: center.x + cos(angle) * d, y: center.y - sin(angle) * d)
    glow.setFillColor(oklch(0.6, 0.14, orb.hue))
    glow.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}
let ci = CIContext(options: [.workingColorSpace: cs])
let blurred = CIImage(cgImage: glow.makeImage()!)
    .clampedToExtent()
    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18 * k * 1.2])
    .cropped(to: CGRect(x: 0, y: 0, width: S, height: S))
let glowImage = ci.createCGImage(blurred, from: blurred.extent, format: .RGBA8, colorSpace: cs)!

let ctx = makeContext()
ctx.setFillColor(CGColor(srgbRed: 0x0c / 255, green: 0x0e / 255, blue: 0x13 / 255, alpha: 1))   // app background
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
ctx.setBlendMode(.screen)
ctx.draw(glowImage, in: CGRect(x: 0, y: 0, width: S, height: S))

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
