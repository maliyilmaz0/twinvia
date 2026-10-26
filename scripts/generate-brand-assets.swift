#!/usr/bin/env swift
import AppKit
import Foundation

// Canonical geometry for Twinvia. All vector and raster variants derive from this path.
private enum Segment {
    case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close
}

private let outline: [Segment] = [
    .move(CGPoint(x: 24, y: 36)), .line(CGPoint(x: 76, y: 36)),
    .curve(CGPoint(x: 108, y: 36), CGPoint(x: 124, y: 58), CGPoint(x: 124, y: 90)),
    .line(CGPoint(x: 124, y: 220)), .line(CGPoint(x: 108, y: 220)),
    .curve(CGPoint(x: 84, y: 220), CGPoint(x: 72, y: 208), CGPoint(x: 72, y: 184)),
    .line(CGPoint(x: 72, y: 120)),
    .curve(CGPoint(x: 72, y: 104), CGPoint(x: 64, y: 96), CGPoint(x: 48, y: 96)),
    .line(CGPoint(x: 36, y: 96)),
    .curve(CGPoint(x: 20, y: 96), CGPoint(x: 12, y: 84), CGPoint(x: 12, y: 68)),
    .line(CGPoint(x: 12, y: 48)),
    .curve(CGPoint(x: 12, y: 40), CGPoint(x: 16, y: 36), CGPoint(x: 24, y: 36)), .close,
]

private func pair(_ point: CGPoint) -> String { "\(Int(point.x)) \(Int(point.y))" }
private var svgPath: String {
    outline.map { part in
        switch part {
        case .move(let point): return "M \(pair(point))"
        case .line(let point): return "L \(pair(point))"
        case .curve(let a, let b, let end): return "C \(pair(a)) \(pair(b)) \(pair(end))"
        case .close: return "Z"
        }
    }.joined(separator: " ")
}

@MainActor
private func shape() -> NSBezierPath {
    let path = NSBezierPath()
    for part in outline {
        switch part {
        case .move(let point): path.move(to: point)
        case .line(let point): path.line(to: point)
        case .curve(let a, let b, let end): path.curve(to: end, controlPoint1: a, controlPoint2: b)
        case .close: path.close()
        }
    }
    return path
}

@MainActor
private func png(size: Int, appIcon: Bool) throws -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let coordinates = AffineTransform(scale: CGFloat(size) / 256)
    (coordinates as NSAffineTransform).concat()
    if appIcon {
        NSColor(srgbRed: 16 / 255, green: 18 / 255, blue: 34 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 256, height: 256), xRadius: 56, yRadius: 56).fill()
    }
    var flip = AffineTransform()
    flip.translate(x: 0, y: 256)
    flip.scale(x: 1, y: -1)
    (flip as NSAffineTransform).concat()
    if appIcon {
        var inset = AffineTransform()
        inset.translate(x: 38.4, y: 38.4)
        inset.scale(0.7)
        (inset as NSAffineTransform).concat()
    }
    let left = shape()
    let right = shape()
    var mirror = AffineTransform()
    mirror.translate(x: 256, y: 0)
    mirror.scale(x: -1, y: 1)
    right.transform(using: mirror)
    (appIcon ? NSColor(srgbRed: 190 / 255, green: 173 / 255, blue: 255 / 255, alpha: 1) : .black).setFill()
    left.fill()
    (appIcon ? NSColor(srgbRed: 202 / 255, green: 245 / 255, blue: 154 / 255, alpha: 1) : .black).setFill()
    right.fill()
    return bitmap.representation(using: .png, properties: [:])!
}

@MainActor
private func generate(root: URL) throws {
    func write(_ data: Data, _ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
    }
    func text(_ value: String, _ relative: String) throws { try write(Data(value.utf8), relative) }
    let mark =
        "<path fill=\"#BEADFF\" d=\"\(svgPath)\"/><path fill=\"#CAF59A\" transform=\"translate(256 0) scale(-1 1)\" d=\"\(svgPath)\"/>"
    try text(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" role=\"img\" aria-label=\"Twinvia\">\(mark)</svg>\n",
        "assets/brand/mark.svg")
    try text(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" role=\"img\" aria-label=\"Twinvia\"><rect width=\"256\" height=\"256\" rx=\"56\" fill=\"#101222\"/><g transform=\"translate(38.4 38.4) scale(.7)\">\(mark)</g></svg>\n",
        "assets/brand/app-icon.svg")
    try text(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1400 360\" role=\"img\" aria-label=\"Twinvia. Two devices. One flow.\"><rect width=\"1400\" height=\"360\" rx=\"28\" fill=\"#F5F3FF\"/><g transform=\"translate(70 52)\">\(mark)</g><g fill=\"#101222\" font-family=\"-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif\"><text x=\"390\" y=\"188\" font-size=\"100\" font-weight=\"700\">Twinvia</text><text x=\"396\" y=\"252\" font-size=\"34\" fill=\"#5F6178\">Two devices. One flow.</text></g></svg>\n",
        "assets/brand/banner.svg")
    var icons: [[String: String]] = []
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try write(
                png(size: points * scale, appIcon: true),
                "apps/macos/Sources/Androfest/Assets.xcassets/AppIcon.appiconset/\(name)")
            icons.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
        }
    }
    let info: [String: Any] = ["author": "xcode", "version": 1]
    try write(
        JSONSerialization.data(
            withJSONObject: ["images": icons, "info": info], options: [.prettyPrinted, .sortedKeys]),
        "apps/macos/Sources/Androfest/Assets.xcassets/AppIcon.appiconset/Contents.json")
    try write(
        JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys]),
        "apps/macos/Sources/Androfest/Assets.xcassets/Contents.json")
    var tray: [[String: String]] = []
    for scale in 1...3 {
        let name = "tray@\(scale)x.png"
        try write(
            png(size: 18 * scale, appIcon: false),
            "apps/macos/Sources/Androfest/Assets.xcassets/TrayMark.imageset/\(name)")
        tray.append(["idiom": "universal", "scale": "\(scale)x", "filename": name])
    }
    try write(
        JSONSerialization.data(
            withJSONObject: ["images": tray, "info": info, "properties": ["template-rendering-intent": "template"]],
            options: [.prettyPrinted, .sortedKeys]),
        "apps/macos/Sources/Androfest/Assets.xcassets/TrayMark.imageset/Contents.json")
    let colored =
        "<path android:fillColor=\"#BEADFF\" android:pathData=\"\(svgPath)\"/><group android:translateX=\"256\" android:scaleX=\"-1\"><path android:fillColor=\"#CAF59A\" android:pathData=\"\(svgPath)\"/></group>"
    let mono =
        "<path android:fillColor=\"#FFFFFFFF\" android:pathData=\"\(svgPath)\"/><group android:translateX=\"256\" android:scaleX=\"-1\"><path android:fillColor=\"#FFFFFFFF\" android:pathData=\"\(svgPath)\"/></group>"
    for (name, content) in [("twinvia_foreground", colored), ("twinvia_monochrome", mono)] {
        try text(
            "<vector xmlns:android=\"http://schemas.android.com/apk/res/android\" android:width=\"108dp\" android:height=\"108dp\" android:viewportWidth=\"480\" android:viewportHeight=\"480\"><group android:translateX=\"112\" android:translateY=\"112\">\(content)</group></vector>\n",
            "apps/android/app/src/main/res/drawable/\(name).xml")
    }
    try text(
        "<vector xmlns:android=\"http://schemas.android.com/apk/res/android\" android:width=\"24dp\" android:height=\"24dp\" android:viewportWidth=\"256\" android:viewportHeight=\"256\">\(mono)</vector>\n",
        "apps/android/app/src/main/res/drawable/ic_launcher.xml")
    try text(
        "<adaptive-icon xmlns:android=\"http://schemas.android.com/apk/res/android\"><background android:drawable=\"@color/twinvia_background\"/><foreground android:drawable=\"@drawable/twinvia_foreground\"/><monochrome android:drawable=\"@drawable/twinvia_monochrome\"/></adaptive-icon>\n",
        "apps/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml")
    try text(
        "<resources><color name=\"twinvia_background\">#101222</color></resources>\n",
        "apps/android/app/src/main/res/values/colors.xml")
    print("Twinvia vector, adaptive, menu-bar, and macOS app-icon assets generated.")
}

let root = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
try MainActor.assumeIsolated { try generate(root: root) }
