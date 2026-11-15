// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation
import CoreGraphics
import ImageIO
import CoreText
import UniformTypeIdentifiers
let fm = FileManager.default
func load(_ path: String) -> CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!, 0, nil)!
}
func context(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}
func write(_ image: CGImage, _ path: String) throws {
    try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { throw NSError(domain: "StoreAssets", code: 1) }
}
// Native screenshots are exported separately with export-localized-screenshots.swift.
// Never overwrite them from older captures when rebuilding the artwork below.
// Own artwork matching the icon, with the app name only.
let header = context(3840, 1646)
header.setFillColor(CGColor(red: 0.035, green: 0.065, blue: 0.095, alpha: 1))
header.fill(CGRect(x: 0, y: 0, width: 3840, height: 1646))
header.draw(load(fm.fileExists(atPath: "store/icon-previews/Default.png") ? "store/icon-previews/Default.png" : "MicRelay/Assets.xcassets/AppIcon.appiconset/AppIcon.png"), in: CGRect(x: 1180, y: 573, width: 500, height: 500))
let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 165, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)]
let title = CTLineCreateWithAttributedString(NSAttributedString(string: "MicRelay", attributes: attrs))
header.textPosition = CGPoint(x: 1760, y: 760)
CTLineDraw(title, header)
try write(header.makeImage()!, "store/header/MicRelay-header.png")
let search = context(3840, 2560)
search.setFillColor(CGColor(red: 0.035, green: 0.065, blue: 0.095, alpha: 1))
search.fill(CGRect(x: 0, y: 0, width: 3840, height: 2560))
search.draw(load(fm.fileExists(atPath: "store/icon-previews/Default.png") ? "store/icon-previews/Default.png" : "MicRelay/Assets.xcassets/AppIcon.appiconset/AppIcon.png"), in: CGRect(x: 1180, y: 1030, width: 500, height: 500))
search.textPosition = CGPoint(x: 1760, y: 1210)
CTLineDraw(title, search)
try write(search.makeImage()!, "store/header/MicRelay-search.png")
let previews = context(1080, 800)
previews.setFillColor(CGColor(gray: 0.92, alpha: 1)); previews.fill(CGRect(x: 0, y: 0, width: 1080, height: 800))
for (index, appearance) in ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"].enumerated() {
    let x = (index % 3) * 360 + 20, y = 800 - (index / 3 + 1) * 400 + 50
    previews.draw(load("store/icon-previews/\(appearance).png"), in: CGRect(x: x, y: y, width: 320, height: 320))
    let label = CTLineCreateWithAttributedString(NSAttributedString(string: appearance, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 21, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.15, alpha: 1)]))
    previews.textPosition = CGPoint(x: x + 90, y: y - 30); CTLineDraw(label, previews)
}
try write(previews.makeImage()!, "store/icon-previews/appearances.png")
