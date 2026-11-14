// SPDX-License-Identifier: MIT
// Copyright (c) 2026 ryuya
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: swift scripts/export-localized-screenshots.swift en-US iphone artifacts/captures
// The input is xcresulttool's exported attachments and manifest; no UI content is synthesized.
let args = CommandLine.arguments
guard args.count == 4, ["iphone", "ipad", "duo"].contains(args[2]),
      args[1].range(of: #"^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"#, options: .regularExpression) != nil else {
    fatalError("Usage: export-localized-screenshots.swift <locale> <iphone|ipad|duo> <attachments-directory>")
}
let locale = args[1], device = args[2], captures = URL(fileURLWithPath: args[3], isDirectory: true)
let records = try JSONSerialization.jsonObject(with: Data(contentsOf: captures.appendingPathComponent("manifest.json"))) as! [[String: Any]]
let output = URL(fileURLWithPath: "store/screenshots/\(locale)/\(device)", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var exported = Set<String>()
for record in records {
    for attachment in record["attachments"] as! [[String: Any]] {
        let name = attachment["suggestedHumanReadableName"] as! String
        guard name.hasPrefix("store-") else { continue }
        let input = captures.appendingPathComponent(attachment["exportedFileName"] as! String)
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Cannot read capture") }
        let width = device == "ipad" ? (image.width > image.height ? 2752 : 2064) : image.width
        let height = device == "ipad" ? (image.width > image.height ? 2064 : 2752) : image.height
        guard abs(Double(width) / Double(height) - Double(image.width) / Double(image.height)) < 0.001 else { fatalError("Capture aspect ratio does not match the store dimensions") }
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let filename = name.components(separatedBy: "_")[0] + ".png"
        guard exported.insert(filename).inserted else { fatalError("Duplicate capture name: \(filename)") }
        let target = output.appendingPathComponent(filename)
        let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write PNG") }
        print("\(target.path): \(width)×\(height)")
    }
}
guard exported.count == 3 else { fatalError("Expected three store captures") }
