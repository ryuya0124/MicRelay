// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya

import AppKit
let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()
let bg = NSColor(srgbRed: 0.035, green: 0.065, blue: 0.095, alpha: 1)
bg.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
let teal = NSColor(srgbRed: 0.38, green: 0.94, blue: 0.77, alpha: 1)
teal.withAlphaComponent(0.08).setFill()
NSBezierPath(ovalIn: NSRect(x: 135, y: 135, width: 754, height: 754)).fill()
teal.setStroke()
let arch = NSBezierPath()
arch.move(to: NSPoint(x: 260, y: 440))
arch.line(to: NSPoint(x: 260, y: 555))
arch.curve(to: NSPoint(x: 764, y: 555), controlPoint1: NSPoint(x: 260, y: 900), controlPoint2: NSPoint(x: 764, y: 900))
arch.line(to: NSPoint(x: 764, y: 440))
arch.lineWidth = 49
arch.lineCapStyle = .round
arch.stroke()
teal.setFill()
for x: CGFloat in [228, 716] {
    NSBezierPath(roundedRect: NSRect(x: x, y: 330, width: 80, height: 200), xRadius: 38, yRadius: 38).fill()
}
let wave = NSBezierPath()
let coords: [(CGFloat, CGFloat)] = [(350,490),(392,490),(423,565),(469,375),(520,650),(566,420),(602,490),(674,490)]
for (i, point) in coords.enumerated() {
    if i == 0 { wave.move(to: NSPoint(x: point.0,y: point.1)) }
    else { wave.line(to: NSPoint(x: point.0,y: point.1)) }
}
wave.lineWidth = 25
wave.lineJoinStyle = .round
wave.lineCapStyle = .round
wave.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "MicRelay/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
