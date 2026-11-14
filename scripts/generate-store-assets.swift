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
func saveRGB(_ image: CGImage, width: Int, height: Int, to path: String) throws {
    let ctx = context(width, height); ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    try write(ctx.makeImage()!, path)
}
// Native screenshots only. iPad captures are scaled uniformly to Apple's 13-inch dimensions.
for device in ["iphone", "ipad"] {
    let root = "artifacts/store-\(device)-captures"
    let records = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: root + "/manifest.json"))) as! [[String: Any]]
    for record in records {
        for item in record["attachments"] as! [[String: Any]] {
            let name = item["suggestedHumanReadableName"] as! String
            guard name.hasPrefix("store-") else { continue }
            let path = root + "/" + (item["exportedFileName"] as! String)
            let source = load(path)
            let rep = load(path)
            let width = device == "ipad" ? 2752 : rep.width
            let height = device == "ipad" ? 2064 : rep.height
            try saveRGB(source, width: width, height: height, to: "store/screenshots/ja/\(device)/" + name.components(separatedBy: "_").first! + ".png")
        }
    }
}
for (name, path) in [("01-outer", "artifacts/duo-native-closed-final.png"), ("02-inner", "artifacts/duo-native-landscape.png")] {
    let rep = load(path)
    try saveRGB(load(path), width: rep.width, height: rep.height, to: "store/screenshots/ja/duo/\(name).png")
}
// Own artwork matching the icon, with the app name only.
let header = context(3840, 1646)
header.setFillColor(CGColor(red: 0.035, green: 0.065, blue: 0.095, alpha: 1))
header.fill(CGRect(x: 0, y: 0, width: 3840, height: 1646))
header.draw(load("MicRelay/Assets.xcassets/AppIcon.appiconset/AppIcon.png"), in: CGRect(x: 440, y: 423, width: 800, height: 800))
let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 240, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)]
let title = CTLineCreateWithAttributedString(NSAttributedString(string: "MicRelay", attributes: attrs))
header.textPosition = CGPoint(x: 1360, y: 720)
CTLineDraw(title, header)
try write(header.makeImage()!, "store/header/MicRelay-header.png")
