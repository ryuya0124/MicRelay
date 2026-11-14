// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let side = 1024
let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let teal = CGColor(red: 0.38, green: 0.94, blue: 0.77, alpha: 1)
ctx.setFillColor(CGColor(red: 0.035, green: 0.065, blue: 0.095, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
ctx.setFillColor(CGColor(red: 0.38, green: 0.94, blue: 0.77, alpha: 0.08))
ctx.fillEllipse(in: CGRect(x: 135, y: 135, width: 754, height: 754))
ctx.setStrokeColor(teal); ctx.setLineWidth(49); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 260, y: 440)); ctx.addLine(to: CGPoint(x: 260, y: 555))
ctx.addCurve(to: CGPoint(x: 764, y: 555), control1: CGPoint(x: 260, y: 900), control2: CGPoint(x: 764, y: 900))
ctx.addLine(to: CGPoint(x: 764, y: 440)); ctx.strokePath()
ctx.setFillColor(teal)
for x in [228.0, 716.0] {
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 330, width: 80, height: 200), cornerWidth: 38, cornerHeight: 38, transform: nil))
    ctx.fillPath()
}
ctx.setLineWidth(25); ctx.setLineJoin(.round)
let points: [(Double, Double)] = [(350,490),(392,490),(423,565),(469,375),(520,650),(566,420),(602,490),(674,490)]
for (index, p) in points.enumerated() {
    if index == 0 { ctx.move(to: CGPoint(x: p.0, y: p.1)) } else { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
}
ctx.strokePath()
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: "MicRelay/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Icon PNG export failed") }
