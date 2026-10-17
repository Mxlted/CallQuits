#!/usr/bin/env swift
import AppKit

// Original, deterministic vector artwork: a red close control above a power mark.
// Draw every resolution separately so the small Finder icons stay crisp.
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func render(pixels: Int, filename: String) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("No drawing context") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let base = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(25, 32, 38).withAlphaComponent(0.16)
    tileShadow.shadowBlurRadius = 20
    tileShadow.shadowOffset = NSSize(width: 0, height: -10)
    tileShadow.set()
    color(237, 235, 229).setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(255, 254, 250), ending: color(225, 229, 226))!.draw(in: base, angle: -75)
    color(255, 255, 255).withAlphaComponent(0.85).setStroke()
    base.lineWidth = 3
    base.stroke()

    // A single dark window, with the red control in its familiar top-left corner.
    let window = NSBezierPath(roundedRect: NSRect(x: 196, y: 226, width: 632, height: 574), xRadius: 82, yRadius: 82)
    NSGraphicsContext.saveGraphicsState()
    let windowShadow = NSShadow()
    windowShadow.shadowColor = color(25, 38, 42).withAlphaComponent(0.28)
    windowShadow.shadowBlurRadius = 40
    windowShadow.shadowOffset = NSSize(width: 0, height: -20)
    windowShadow.set()
    color(28, 42, 48).setFill()
    window.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(57, 76, 83), ending: color(25, 39, 45))!.draw(in: window, angle: -90)
    color(255, 255, 255).withAlphaComponent(0.16).setStroke()
    window.lineWidth = 3
    window.stroke()

    let separator = NSBezierPath()
    separator.move(to: NSPoint(x: 198, y: 650))
    separator.line(to: NSPoint(x: 826, y: 650))
    separator.lineWidth = pixels <= 32 ? 8 : 3
    color(211, 230, 229).withAlphaComponent(0.18).setStroke()
    separator.stroke()

    for x: CGFloat in [420, 484] {
        color(201, 217, 216).withAlphaComponent(0.28).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 14, y: 716, width: 28, height: 28)).fill()
    }

    let close = NSBezierPath(ovalIn: NSRect(x: 240, y: 666, width: 128, height: 128))
    NSGradient(starting: color(255, 126, 102), ending: color(244, 76, 75))!.draw(in: close, angle: -90)
    if pixels > 32 {
        color(255, 224, 207).withAlphaComponent(0.5).setStroke()
        close.lineWidth = 2
        close.stroke()
    }
    let cross = NSBezierPath()
    cross.move(to: NSPoint(x: 285, y: 711))
    cross.line(to: NSPoint(x: 323, y: 749))
    cross.move(to: NSPoint(x: 285, y: 749))
    cross.line(to: NSPoint(x: 323, y: 711))
    cross.lineWidth = pixels <= 32 ? 16 : 14
    cross.lineCapStyle = .round
    color(104, 29, 34).setStroke()
    cross.stroke()

    // The power mark makes the promise legible: closing the window quits the app.
    let power = NSBezierPath()
    power.appendArc(withCenter: NSPoint(x: 512, y: 446), radius: 110,
                    startAngle: 134, endAngle: 406, clockwise: false)
    power.lineWidth = pixels <= 32 ? 44 : 38
    power.lineCapStyle = .round
    color(242, 249, 243).setStroke()
    power.stroke()
    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: 512, y: 470))
    stem.line(to: NSPoint(x: 512, y: 584))
    stem.lineWidth = power.lineWidth
    stem.lineCapStyle = .round
    stem.stroke()

    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
    try png.write(to: output.appendingPathComponent(filename))
}

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size, filename: "icon_\(size)x\(size).png")
    try render(pixels: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}
print(output.path)
