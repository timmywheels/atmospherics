import AppKit
import CoreGraphics
import Foundation

// Frames raw 6.9" screenshots for the App Store: a headline and subline on the
// app's night background, the screen below with rounded corners and a soft glow.
// Usage: swift compose.swift  (reads raw/, writes framed/)

let W: CGFloat = 1320, H: CGFloat = 2868

// Headlines in the app's serif, from its own font file.
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "../../Atmospherics/Fonts/InstrumentSerif-Regular.ttf") as CFURL, .process, nil)
let headline = NSFont(name: "InstrumentSerif-Regular", size: 116)!
let shots: [(file: String, title: String, sub: String, glow: NSColor)] = [
    ("1-cabin", "Teleport\nby sound", "A log cabin in a snowstorm, the fire going.", NSColor(srgbRed: 0.85, green: 0.45, blue: 0.3, alpha: 1)),
    ("2-teleport", "Take me\nanywhere", "Build a scene in a sentence, or say it.", NSColor(srgbRed: 0.75, green: 0.38, blue: 0.3, alpha: 1)),
    ("3-live", "Real weather,\nsomewhere real", "Raining in Sydney right now? You'll hear it.", NSColor(srgbRed: 0.25, green: 0.55, blue: 0.85, alpha: 1)),
    ("4-storm", "Any weather,\nany hour", "A tent in a thunderstorm, the woods close by.", NSColor(srgbRed: 0.25, green: 0.6, blue: 0.75, alpha: 1)),
    ("5-layers", "Every sound,\nyour level", "Tap or drag across a layer to set it.", NSColor(srgbRed: 0.3, green: 0.65, blue: 0.55, alpha: 1)),
    ("6-library", "Mixes for sleep,\nfocus and calm", "With a sleep timer up to 8 hours.", NSColor(srgbRed: 0.5, green: 0.45, blue: 0.85, alpha: 1)),
]

try? FileManager.default.createDirectory(atPath: "framed", withIntermediateDirectories: true)

for shot in shots {
    guard let raw = NSImage(contentsOfFile: "raw/\(shot.file).png"),
          let rawCG = raw.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("missing raw/\(shot.file).png"); continue
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Background (CG origin bottom-left).
    ctx.setFillColor(NSColor(srgbRed: 0x0c / 255, green: 0x0e / 255, blue: 0x13 / 255, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // Screen placement.
    let scale: CGFloat = 0.74
    let sw = W * scale, sh = H * scale
    let screen = CGRect(x: (W - sw) / 2, y: 90, width: sw, height: sh)

    // Glow behind the screen.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [shot.glow.withAlphaComponent(0.35).cgColor, shot.glow.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    let gc = CGPoint(x: W / 2, y: screen.midY + 200)
    ctx.drawRadialGradient(glow, startCenter: gc, startRadius: 0, endCenter: gc, endRadius: 1100, options: [])

    // Screen with rounded corners and a hairline edge.
    let path = CGPath(roundedRect: screen, cornerWidth: 120, cornerHeight: 120, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(rawCG, in: screen)
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor); ctx.setLineWidth(3); ctx.strokePath()

    // Headline and subline, left-aligned to the screen's edge.
    let para = NSMutableParagraphStyle()
    para.lineSpacing = 4
    let title = NSAttributedString(string: shot.title, attributes: [
        .font: headline,
        .foregroundColor: NSColor(srgbRed: 0.925, green: 0.933, blue: 0.95, alpha: 1),
        .kern: -0.6, .paragraphStyle: para,
    ])
    let left = screen.minX
    // The subline at 44 pt, smaller if it would run past the screen's width.
    func subline(_ size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: shot.sub, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.725, green: 0.745, blue: 0.784, alpha: 1),
        ])
    }
    var sub = subline(44)
    if sub.size().width > W - left * 2 { sub = subline(44 * (W - left * 2) / sub.size().width) }
    let titleRect = CGRect(x: left, y: H - 160 - 280, width: W - left * 2, height: 280)
    title.draw(with: titleRect, options: [.usesLineFragmentOrigin])
    sub.draw(at: CGPoint(x: left, y: titleRect.minY - 96))

    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "framed/\(shot.file).png"))
    print("framed/\(shot.file).png")
}
