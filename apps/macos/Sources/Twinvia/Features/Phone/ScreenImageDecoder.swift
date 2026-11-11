import AppKit
import ImageIO
import TwinviaProtocol

/// Inspect encoded dimensions before decoding so metadata cannot hide an oversized JPEG.
enum ScreenImageDecoder {
    static func decode(_ screen: RemoteScreen) -> NSImage? {
        guard (try? screen.validate()) != nil,
            let data = Data(base64Encoded: screen.jpegBase64),
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(source) == 1,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width == screen.width, height == screen.height,
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }
}
