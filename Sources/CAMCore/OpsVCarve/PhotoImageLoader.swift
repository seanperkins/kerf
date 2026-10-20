import CoreGraphics
import Foundation
import ImageIO

/// Loads a bitmap (PNG, JPEG, TIFF, HEIC… anything ImageIO reads) as a downsampled 8-bit
/// greyscale `GrayImage` for PhotoVCarve.
public enum PhotoImageLoader {
    public enum LoadError: Error, Equatable {
        case unreadable
    }

    /// - Parameter maxDimension: the longer side is scaled down to at most this many pixels.
    public static func load(_ url: URL, maxDimension: Int = 800) throws -> GrayImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw LoadError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LoadError.unreadable
        }
        return try gray(image)
    }

    /// Renders a CGImage into an 8-bit grey buffer (transparent areas become white).
    public static func gray(_ image: CGImage) throws -> GrayImage {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { throw LoadError.unreadable }
        var bytes = [UInt8](repeating: 255, count: w * h)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw LoadError.unreadable }
        // CGContext memory starts at the top row, matching GrayImage's row order.
        return GrayImage(width: w, height: h, pixels: Data(bytes))
    }
}
