import AppKit
import ImageIO

/// Turns any picture into the small square PNG stored as a job icon.
enum JobIconImage {
    static let pixelSize = 256
    /// Larger pictures are refused instead of decoded; some formats would need gigabytes of memory.
    static let maximumPixelCount = 100_000_000

    /// Reads PNG, JPEG, HEIC, TIFF, GIF and more, respects the photo orientation,
    /// crops the center square and scales it down. Returns `nil` for unreadable or oversized files.
    static func makeIconData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return makeIconData(from: source)
    }

    static func makeIconData(from url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        // Reading through ImageIO avoids loading the whole file into memory.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return makeIconData(from: source)
    }

    private static func makeIconData(from source: CGImageSource) -> Data? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              Double(width) * Double(height) <= Double(maximumPixelCount)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize * 3,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let side = min(image.width, image.height)
        let square = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        guard let cropped = image.cropping(to: square),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelSize,
                  height: pixelSize,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        guard let output = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
    }
}
