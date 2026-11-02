import AppKit

/// A compact K-shaped network mark, drawn as a template at the menu bar's size.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let links = NSBezierPath()
            links.lineWidth = 1.8
            links.lineCapStyle = .round
            links.lineJoinStyle = .round
            links.move(to: NSPoint(x: 4, y: 3))
            links.line(to: NSPoint(x: 4, y: 15))
            links.move(to: NSPoint(x: 13.5, y: 14.5))
            links.line(to: NSPoint(x: 4, y: 9))
            links.line(to: NSPoint(x: 13.5, y: 3.5))
            links.stroke()

            for point in [
                NSPoint(x: 4, y: 3), NSPoint(x: 4, y: 15),
                NSPoint(x: 13.5, y: 14.5), NSPoint(x: 13.5, y: 3.5)
            ] {
                NSBezierPath(ovalIn: NSRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "KomariBar"
        return image
    }()
}
