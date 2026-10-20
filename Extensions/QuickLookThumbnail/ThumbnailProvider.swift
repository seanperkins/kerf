import AppKit
import ImageIO
import QuickLookThumbnailing

/// Quick Look / Finder thumbnail for `.kerf` files: draws the design picture Kerf embeds at the
/// start of every saved file (`QuickLookThumbnailData`, compiled in alongside this file by
/// scripts/bundle.sh). Files saved before thumbnails existed get the generic icon.
@objc(KerfThumbnailProvider)
final class KerfThumbnailProvider: QLThumbnailProvider {
    struct NoThumbnail: Error {}

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        guard let png = QuickLookThumbnailData.read(from: request.fileURL),
              let src = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            handler(nil, NoThumbnail())
            return
        }
        // Fit the (square) picture inside the requested size.
        let max = request.maximumSize
        let aspect = CGFloat(image.width) / CGFloat(Swift.max(image.height, 1))
        var size = CGSize(width: max.width, height: max.width / aspect)
        if size.height > max.height { size = CGSize(width: max.height * aspect, height: max.height) }
        handler(QLThumbnailReply(contextSize: size, drawing: { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
            return true
        }), nil)
    }
}
