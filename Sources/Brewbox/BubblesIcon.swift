import AppKit

/// The app's mark: three thin rising bubbles, drawn as a template image so the
/// menu bar tints it like a system icon.
enum BubblesIcon {
    /// Frames in one rise cycle while brew is working.
    static let frameCount = 24

    /// - Parameters:
    ///   - hasUpdates: adds a small filled bubble at the top.
    ///   - frame: animation frame while brew works; nil draws the resting icon.
    static func image(hasUpdates: Bool, frame: Int? = nil, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            // Artwork is laid out on a 24pt grid.
            let scale = rect.width / 24
            let bubbles = frame.map(animatedBubbles) ?? restingBubbles

            for bubble in bubbles {
                let radius = bubble.radius * scale
                let path = NSBezierPath(ovalIn: NSRect(
                    x: bubble.x * scale - radius,
                    y: bubble.y * scale - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                path.lineWidth = 1.6 * scale
                NSColor.black.withAlphaComponent(bubble.alpha).setStroke()
                path.stroke()
            }

            if hasUpdates {
                let radius = 2 * scale
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 18.8 * scale - radius, y: 3.4 * scale - radius,
                                            width: radius * 2, height: radius * 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private struct Bubble {
        var x: CGFloat
        var y: CGFloat
        var radius: CGFloat
        var alpha: CGFloat = 1
    }

    private static let restingBubbles = [
        Bubble(x: 8, y: 16.2, radius: 5),
        Bubble(x: 16.6, y: 9.6, radius: 3.3),
        Bubble(x: 9.4, y: 4.4, radius: 2.1),
    ]

    /// Three bubbles a third of a cycle apart, wobbling as they rise, shrinking,
    /// and fading in at the bottom and out at the top.
    private static func animatedBubbles(frame: Int) -> [Bubble] {
        let phase = CGFloat(frame % frameCount) / CGFloat(frameCount)
        return (0..<3).map { index in
            let t = (phase + CGFloat(index) / 3).truncatingRemainder(dividingBy: 1)
            let alpha = min(1, t / 0.15, (1 - t) / 0.2)
            return Bubble(
                x: 12 + sin(t * .pi * 2 + CGFloat(index) * 2.1) * 4,
                y: 22 - t * 20,
                radius: 3.6 - t * 1.9,
                alpha: max(0, alpha)
            )
        }
    }
}
