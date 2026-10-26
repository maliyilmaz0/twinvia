import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum PairingQRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
            let image = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
