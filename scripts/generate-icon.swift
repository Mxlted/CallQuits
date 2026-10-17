#!/usr/bin/env swift
import AppKit

// Deterministic, original vector artwork. No downloaded assets or dependencies.
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

    let base = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 200, yRadius: 200)
    NSGradient(starting: color(39, 45, 62), ending: color(16, 20, 32))!.draw(in: base, angle: -90)
    color(255, 255, 255).withAlphaComponent(0.1).setStroke()
    base.lineWidth = 2
    base.stroke()

    // A quiet window outline gives the close control its familiar context.
    let window = NSBezierPath(roundedRect: NSRect(x: 231, y: 239, width: 562, height: 546), xRadius: 78, yRadius: 78)
    color(179, 189, 213).withAlphaComponent(0.18).setFill()
    window.fill()
    color(218, 225, 244).withAlphaComponent(0.4).setStroke()
    window.lineWidth = 15
    window.stroke()
    let separator = NSBezierPath()
    separator.move(to: NSPoint(x: 237, y: 639))
    separator.line(to: NSPoint(x: 787, y: 639))
    separator.lineWidth = 13
    color(218, 225, 244).withAlphaComponent(0.25).setStroke()
    separator.stroke()

    let close = NSBezierPath(ovalIn: NSRect(x: 257, y: 346, width: 510, height: 510))
    NSGradient(starting: color(255, 143, 111), ending: color(240, 74, 88))!.draw(in: close, angle: -90)
    let cross = NSBezierPath()
    cross.move(to: NSPoint(x: 427, y: 516))
    cross.line(to: NSPoint(x: 597, y: 686))
    cross.move(to: NSPoint(x: 427, y: 686))
    cross.line(to: NSPoint(x: 597, y: 516))
    cross.lineWidth = 52
    cross.lineCapStyle = .round
    color(255, 250, 246).setStroke()
    cross.stroke()

    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
    try png.write(to: output.appendingPathComponent(filename))
}

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size, filename: "icon_\(size)x\(size).png")
    try render(pixels: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}
print(output.path)
