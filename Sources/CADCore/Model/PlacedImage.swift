import Foundation

/// A raster image placed on the design as a tracing/reference picture. It never produces
/// toolpaths. The pixels are stored PNG-encoded inside the document.
public struct PlacedImage: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Layer whose visibility/lock applies (nil or a deleted layer = always shown).
    public var layerID: UUID?
    /// PNG data of the full source image.
    public var png: Data
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Where the FULL (uncropped) image sits, in the material frame (document units).
    public var rect: Rect2
    /// Visible part of the image as fractions of its width/height, (0,0) = bottom-left.
    public var crop: Rect2
    /// 1 = opaque, lower values fade the picture so vectors drawn over it stay readable.
    public var opacity: Double
    public var isVisible: Bool
    public var isLocked: Bool

    public init(id: UUID = UUID(), name: String, layerID: UUID? = nil, png: Data, pixelWidth: Int, pixelHeight: Int,
                rect: Rect2, crop: Rect2 = PlacedImage.fullCrop, opacity: Double = 0.6,
                isVisible: Bool = true, isLocked: Bool = false) {
        self.id = id; self.name = name; self.layerID = layerID; self.png = png
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.rect = rect; self.crop = crop
        self.opacity = opacity; self.isVisible = isVisible; self.isLocked = isLocked
    }

    public static let fullCrop = Rect2(x: 0, y: 0, width: 1, height: 1)

    /// The visible (cropped) area in the material frame.
    public var visibleRect: Rect2 {
        let c = PlacedImage.clampCrop(crop)
        return Rect2(x: rect.min.x + c.min.x * rect.width, y: rect.min.y + c.min.y * rect.height,
                     width: c.width * rect.width, height: c.height * rect.height)
    }

    /// The crop in pixel coordinates with a TOP-left origin (CGImage cropping convention).
    public var cropPixelRect: (x: Int, y: Int, width: Int, height: Int) {
        let c = PlacedImage.clampCrop(crop)
        let x0 = Int((c.min.x * Double(pixelWidth)).rounded()), x1 = Int((c.max.x * Double(pixelWidth)).rounded())
        let yTop = Int(((1 - c.max.y) * Double(pixelHeight)).rounded())
        let yBottom = Int(((1 - c.min.y) * Double(pixelHeight)).rounded())
        return (x0, yTop, max(1, x1 - x0), max(1, yBottom - yTop))
    }

    /// Crop limited to the unit square with a non-zero size.
    public static func clampCrop(_ c: Rect2) -> Rect2 {
        let x0 = min(max(c.min.x, 0), 0.99), y0 = min(max(c.min.y, 0), 0.99)
        let x1 = min(max(c.max.x, x0 + 0.01), 1), y1 = min(max(c.max.y, y0 + 0.01), 1)
        return Rect2(min: Vec2(x0, y0), max: Vec2(x1, y1))
    }

    /// Initial placement: the file's physical size when it records a DPI, otherwise scaled to
    /// fit 90% of the material; centred on the material either way.
    public static func defaultRect(pixels: (width: Int, height: Int), physicalInches: (width: Double, height: Double)?,
                                   job: JobSetup, units: LengthUnit) -> Rect2 {
        let aspect = Double(max(pixels.height, 1)) / Double(max(pixels.width, 1))
        var w: Double, h: Double
        if let p = physicalInches {
            w = LengthUnit.inch.convert(p.width, to: units)
            h = LengthUnit.inch.convert(p.height, to: units)
        } else {
            w = job.width * 0.9
            h = w * aspect
            if h > job.height * 0.9 { h = job.height * 0.9; w = h / aspect }
        }
        let c = job.materialBounds.center
        return Rect2(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }
}

extension Document {
    /// Placed raster images (stored optionally so older files decode unchanged).
    public var placedImages: [PlacedImage] {
        get { images ?? [] }
        set { images = newValue.isEmpty ? nil : newValue }
    }

    public func placedImage(id: UUID) -> PlacedImage? { images?.first { $0.id == id } }
}
