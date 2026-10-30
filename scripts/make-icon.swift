// Draws the Brewbox app icon and writes Support/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (or: make icon)
//
// Night-brew look: a deep indigo tile with the same three rising bubbles as the
// menu bar icon, in warm amber. Follows the macOS icon grid: an 824pt rounded
// tile centered on a 1024pt canvas, with a soft drop shadow.

import AppKit

let canvas: CGFloat = 1024
let tileInset: CGFloat = 100
let tileSize = canvas - tileInset * 2
let tileRadius = tileSize * 0.225

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(in context: CGContext) {
    let tile = CGRect(x: tileInset, y: tileInset, width: tileSize, height: tileSize)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tileRadius, yRadius: tileRadius)

    // Drop shadow under the tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x1E1A4A).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Indigo body, lighter at the top.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [color(0x3A3290), color(0x221C5C), color(0x16123D)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: tile, angle: -90)

    // Warm glow rising from the bottom, as if lit by the bubbles.
    NSGradient(colors: [color(0xEF9F27, alpha: 0.14), color(0xEF9F27, alpha: 0)])!
        .draw(fromCenter: CGPoint(x: tile.midX - 70, y: tile.minY + 150), radius: 0,
              toCenter: CGPoint(x: tile.midX - 70, y: tile.minY + 150), radius: 460, options: [])

    // Faint sheen across the top edge.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.12), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: tile.minX, y: tile.maxY - 260, width: tile.width, height: 260), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Bubbles, on a 120-unit grid matching the concept sketch (y grows downward there).
    let unit = tileSize / 120
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: tile.minX + x * unit, y: tile.maxY - y * unit)
    }

    func ring(at center: CGPoint, radius: CGFloat, width: CGFloat, colors: [NSColor]) {
        let outer = NSBezierPath(ovalIn: CGRect(x: center.x - radius - width / 2, y: center.y - radius - width / 2,
                                                width: (radius + width / 2) * 2, height: (radius + width / 2) * 2))
        let inner = NSBezierPath(ovalIn: CGRect(x: center.x - radius + width / 2, y: center.y - radius + width / 2,
                                                width: (radius - width / 2) * 2, height: (radius - width / 2) * 2))
        outer.append(inner.reversed)

        // Soft glow behind each ring.
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = colors[0].withAlphaComponent(0.55)
        glow.shadowBlurRadius = width * 1.6
        glow.shadowOffset = .zero
        glow.set()
        colors[0].setFill()
        outer.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        outer.addClip()
        NSGradient(colors: colors)!
            .draw(in: outer.bounds, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }

    ring(at: point(46, 80), radius: 17 * unit, width: 5.5 * unit, colors: [color(0xEF9F27), color(0xFAC775)])
    ring(at: point(78, 56), radius: 11 * unit, width: 5 * unit, colors: [color(0xEF9F27), color(0xFAC775)])
    ring(at: point(52, 36), radius: 7 * unit, width: 4.5 * unit, colors: [color(0xFAC775), color(0xFAEEDA)])

    // The small filled bubble, as in the menu bar icon when updates are waiting.
    let dotCenter = point(82, 28)
    let dotRadius = 4 * unit
    NSGraphicsContext.saveGraphicsState()
    let dotGlow = NSShadow()
    dotGlow.shadowColor = color(0xFAC775, alpha: 0.7)
    dotGlow.shadowBlurRadius = 18
    dotGlow.shadowOffset = .zero
    dotGlow.set()
    color(0xFAC775).setFill()
    NSBezierPath(ovalIn: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius,
                                width: dotRadius * 2, height: dotRadius * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()

    _ = context
}

func renderPNG(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    drawIcon(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Each size is drawn natively rather than downscaled, so small sizes stay crisp.
for points in [16, 32, 128, 256, 512] {
    try renderPNG(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try renderPNG(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let output = root.appendingPathComponent("Support/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// A large PNG for the README and for review.
try renderPNG(size: 1024).write(to: root.appendingPathComponent("Support/AppIcon.png"))
print("Wrote \(output.path)")
