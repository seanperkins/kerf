import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Raster image helpers (ImageIO): decode any format macOS reads, re-encode as PNG.
public enum RasterCodec {
    public static let fileExtensions = ["png", "jpg", "jpeg", "bmp", "tif", "tiff", "gif", "webp", "heic"]

    public static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0 else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    public static func png(from image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Any readable image → PNG (nil when ImageIO cannot decode it).
    public static func png(fromEncoded data: Data) -> Data? {
        cgImage(from: data).flatMap(png(from:))
    }

    /// Pixel size and, when the file records it, the physical size in inches (from its DPI).
    public static func info(of data: Data) -> (pixels: (width: Int, height: Int), inches: (width: Double, height: Double)?)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        var inches: (Double, Double)?
        if let dx = props[kCGImagePropertyDPIWidth] as? Double, let dy = props[kCGImagePropertyDPIHeight] as? Double,
           dx > 0, dy > 0, abs(dx - 72) > 0.5 || abs(dy - 72) > 0.5 {
            inches = (Double(w) / dx, Double(h) / dy)
        }
        return ((w, h), inches)
    }
}
