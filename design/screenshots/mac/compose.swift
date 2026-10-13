import AppKit
import CoreGraphics
import Foundation

// Frames Mac App Store screenshots (2880x1800): a headline and subline on the left, on the app's
// night background, and the window (captured at 2x into raw/) on the right with a soft glow.
// Usage: swift compose.swift  (reads raw/, writes framed/ and upload/)

let W: CGFloat = 2880, H: CGFloat = 1800
let shots: [(file: String, title: String, sub: String, glow: NSColor, height: CGFloat, trimTop: CGFloat)] = [
    ("1-listen", "Teleport\nby sound", "A snowy night in the mountains, at your desk.", NSColor(srgbRed: 0.3, green: 0.7, blue: 0.75, alpha: 1), 1520, 0),
    ("2-teleport", "Take me\nanywhere", "Build a scene in a sentence, or say it.", NSColor(srgbRed: 0.3, green: 0.5, blue: 0.85, alpha: 1), 1520, 0),
    ("3-layers", "Every sound,\nyour level", "Tap or drag across a layer to set it.", NSColor(srgbRed: 0.35, green: 0.65, blue: 0.5, alpha: 1), 1520, 0),
    ("4-menubar", "Always in your\nmenu bar", "Scenes, volume, sleep timer and play, a click away.", NSColor(srgbRed: 0.3, green: 0.6, blue: 0.7, alpha: 1), 1300, 64),
]

for dir in ["framed", "upload"] { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }

for shot in shots {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: "raw/\(shot.file).png")),
          let source = NSBitmapImageRep(data: data)?.cgImage else {
        print("missing raw/\(shot.file).png"); continue
    }
    // The capture without anything above the window's own top edge.
    let window = source.cropping(to: CGRect(x: 0, y: Int(shot.trimTop), width: source.width,
                                            height: source.height - Int(shot.trimTop)))!

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Background (CG origin bottom-left).
    ctx.setFillColor(NSColor(srgbRed: 0x0c / 255, green: 0x0e / 255, blue: 0x13 / 255, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // The window, right of center, a little smaller than the canvas is tall.
    let scale = shot.height / CGFloat(window.height)
    let ww = CGFloat(window.width) * scale, wh = CGFloat(window.height) * scale
    let frame = CGRect(x: W * 0.69 - ww / 2, y: (H - wh) / 2, width: ww, height: wh)

    // Glow behind it.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [shot.glow.withAlphaComponent(0.32).cgColor, shot.glow.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    let gc = CGPoint(x: frame.midX, y: frame.midY + 120)
    ctx.drawRadialGradient(glow, startCenter: gc, startRadius: 0, endCenter: gc, endRadius: 1250, options: [])

    // Clipped just inside the window's own rounded corners (about 34 px at 2x), which the
    // capture fills with white.
    let radius = 36 * scale
    let inset = frame.insetBy(dx: 1, dy: 1)
    let path = CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(window, in: frame)
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor); ctx.setLineWidth(2.5); ctx.strokePath()

    // Headline and subline, left, centered on the window.
    let para = NSMutableParagraphStyle()
    para.lineSpacing = 6
    let title = NSAttributedString(string: shot.title, attributes: [
        .font: NSFont.systemFont(ofSize: 132, weight: .light),
        .foregroundColor: NSColor(srgbRed: 0.925, green: 0.933, blue: 0.95, alpha: 1),
        .kern: -3.0, .paragraphStyle: para,
    ])
    let sub = NSAttributedString(string: shot.sub, attributes: [
        .font: NSFont.systemFont(ofSize: 50, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.725, green: 0.745, blue: 0.784, alpha: 1),
    ])
    let left: CGFloat = 230
    let textWidth = frame.minX - left - 120
    let titleSize = title.boundingRect(with: CGSize(width: textWidth, height: 1000), options: [.usesLineFragmentOrigin])
    let subSize = sub.boundingRect(with: CGSize(width: textWidth, height: 400), options: [.usesLineFragmentOrigin])
    let gap: CGFloat = 48
    let block = titleSize.height + gap + subSize.height
    let top = H / 2 + block / 2
    title.draw(with: CGRect(x: left, y: top - titleSize.height, width: textWidth, height: titleSize.height),
               options: [.usesLineFragmentOrigin])
    sub.draw(with: CGRect(x: left, y: top - titleSize.height - gap - subSize.height, width: textWidth, height: subSize.height),
             options: [.usesLineFragmentOrigin])

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "framed/\(shot.file).png"))
    // App Store Connect wants no alpha channel: a flattened JPEG.
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95])!
        .write(to: URL(fileURLWithPath: "upload/\(shot.file).jpg"))
    print("framed/\(shot.file).png, upload/\(shot.file).jpg")
}
