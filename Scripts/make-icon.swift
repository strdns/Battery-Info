import AppKit
import CoreGraphics
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let files: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

var cache: [Int: Data] = [:]
for (size, name) in files {
    if cache[size] == nil {
        cache[size] = png(draw(size: size))
    }
    try cache[size]!.write(to: output.appendingPathComponent(name))
}

func draw(size: Int) -> CGImage {
    let dimension = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("context")
    }

    let bounds = CGRect(x: 0, y: 0, width: dimension, height: dimension)
    let radius = dimension * 0.223
    context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()

    let colors = [
        CGColor(red: 0.29, green: 0.84, blue: 0.55, alpha: 1),
        CGColor(red: 0.04, green: 0.42, blue: 0.30, alpha: 1)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: dimension * 0.15, y: dimension),
        end: CGPoint(x: dimension * 0.85, y: 0),
        options: []
    )

    let gloss = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.28),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gloss,
        start: CGPoint(x: dimension * 0.5, y: dimension),
        end: CGPoint(x: dimension * 0.5, y: dimension * 0.45),
        options: []
    )

    let body = CGRect(x: dimension * 0.23, y: dimension * 0.35, width: dimension * 0.46, height: dimension * 0.30)
    let line = max(1, dimension * 0.038)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.96))
    context.setLineWidth(line)
    context.addPath(CGPath(roundedRect: body, cornerWidth: dimension * 0.07, cornerHeight: dimension * 0.07, transform: nil))
    context.strokePath()

    let inset = dimension * 0.058
    let innerWidth = body.width - inset * 2
    let fill = CGRect(
        x: body.minX + inset,
        y: body.minY + inset,
        width: innerWidth * 0.68,
        height: body.height - inset * 2
    )
    context.setFillColor(CGColor(gray: 1, alpha: 0.96))
    context.addPath(CGPath(roundedRect: fill, cornerWidth: dimension * 0.04, cornerHeight: dimension * 0.04, transform: nil))
    context.fillPath()

    let nub = CGRect(x: body.maxX + dimension * 0.02, y: dimension * 0.44, width: dimension * 0.04, height: dimension * 0.12)
    context.addPath(CGPath(roundedRect: nub, cornerWidth: dimension * 0.016, cornerHeight: dimension * 0.016, transform: nil))
    context.fillPath()

    guard let image = context.makeImage() else { fatalError("image") }
    return image
}

func png(_ image: CGImage) -> Data {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return data
}
