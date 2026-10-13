import AppKit

/// Draws the small calendar glyph with today's date in the menu bar.
/// The image is a template, so macOS tints it for light, dark and highlighted menu bars.
enum MenuBarIcon {
    static func make(day: String, outline: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let textSize = (day as NSString).size(withAttributes: attributes)
        let width = max(19, ceil(textSize.width) + 7)
        let size = NSSize(width: width, height: 16)

        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: 1, y: 1.5, width: width - 2, height: 13)
            let path = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Body area below the header band, used to center the number.
            let band: CGFloat = 3
            let textArea = NSRect(x: body.minX, y: body.minY, width: body.width, height: body.height - band)
            let origin = NSPoint(
                x: textArea.midX - textSize.width / 2,
                y: textArea.midY - textSize.height / 2 + 0.5
            )

            if outline {
                path.lineWidth = 1.2
                path.stroke()
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                NSRect(x: body.minX, y: body.maxY - band, width: body.width, height: band).fill()
                NSGraphicsContext.restoreGraphicsState()
                (day as NSString).draw(at: origin, withAttributes: attributes)
            } else {
                path.fill()
                // Knock the number out of the filled shape.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                (day as NSString).draw(at: origin, withAttributes: attributes)
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
