import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("用法：swift make-icon.swift 输出文件.png\n", stderr)
    exit(1)
}

let side = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("无法创建图标画布。\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true

let tile = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210)
let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.19, alpha: 1),
    NSColor(calibratedRed: 0.17, green: 0.14, blue: 0.30, alpha: 1)
])!
background.draw(in: tile, angle: 40)

let screen = NSBezierPath(roundedRect: NSRect(x: 198, y: 304, width: 628, height: 440), xRadius: 72, yRadius: 72)
NSColor(calibratedRed: 0.38, green: 0.38, blue: 0.58, alpha: 0.28).setFill()
screen.fill()
NSColor(calibratedRed: 0.72, green: 0.72, blue: 0.92, alpha: 0.85).setStroke()
screen.lineWidth = 24
screen.stroke()

let barColors = [
    NSColor(calibratedRed: 0.62, green: 0.56, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.40, green: 0.64, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.35, green: 0.88, blue: 0.77, alpha: 1)
]
let heights: [CGFloat] = [110, 184, 268]
for index in 0..<3 {
    barColors[index].setFill()
    let rect = NSRect(x: 306 + CGFloat(index) * 146, y: 388, width: 100, height: heights[index])
    NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()
}

NSColor(calibratedRed: 0.72, green: 0.72, blue: 0.92, alpha: 0.85).setStroke()
let stand = NSBezierPath()
stand.move(to: NSPoint(x: 512, y: 292))
stand.line(to: NSPoint(x: 512, y: 220))
stand.move(to: NSPoint(x: 398, y: 214))
stand.line(to: NSPoint(x: 626, y: 214))
stand.lineCapStyle = .round
stand.lineWidth = 26
stand.stroke()

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("无法编码图标。\n", stderr)
    exit(1)
}
do {
    let destination = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: destination, options: .atomic)
} catch {
    fputs("无法保存图标。\n", stderr)
    exit(1)
}
