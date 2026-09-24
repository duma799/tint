import Foundation

#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

/// Decodes images with macOS's own ImageIO: JPEG, PNG, HEIC (the format of the
/// built-in wallpapers), WebP, TIFF, BMP, GIF — everything Preview opens.
public enum ImageLoader {
    /// The image's pixels, shrunk so the longer side is at most `maxSide`.
    public static func pixels(path: String, maxSide: Int) throws -> [Rgb] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw PaletteError.unreadable("no such image: \(path)")
        }

        #if canImport(ImageIO)
        guard let image = thumbnail(path: path, maxSide: maxSide) else {
            throw PaletteError.unreadable("can't read \((path as NSString).lastPathComponent): not an image macOS can open")
        }
        return try rgbPixels(of: image)
        #else
        throw PaletteError.unreadable("reading images needs macOS (ImageIO)")
        #endif
    }

    #if canImport(ImageIO)
    /// A downscaled copy made while decoding — ImageIO never decodes the full
    /// 6K image, which keeps this fast and light.
    public static func thumbnail(path: String, maxSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Draws the image into an 8-bit sRGB buffer and reads it back.
    static func rgbPixels(of image: CGImage) throws -> [Rgb] {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { throw PaletteError.empty }

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw PaletteError.unreadable("couldn't draw the image") }

        var pixels = [Rgb]()
        pixels.reserveCapacity(width * height)
        for i in stride(from: 0, to: buffer.count, by: 4) {
            pixels.append(Rgb(buffer[i], buffer[i + 1], buffer[i + 2]))
        }
        return pixels
    }
    #endif
}
