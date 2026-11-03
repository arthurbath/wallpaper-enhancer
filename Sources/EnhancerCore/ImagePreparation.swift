import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImagePreparation {
    public static func squareGuide(sourceURL: URL, metadata: ImageMetadata, side: Int = EnhancementConfiguration.outputSide) throws -> Data {
        guard try FileDigest.sha256(url: sourceURL) == metadata.sourceHash else { throw EnhancerError.sourceChanged }
        let image = try ImageInspection.orientedImage(sourceURL)
        guard try FileDigest.sha256(url: sourceURL) == metadata.sourceHash else { throw EnhancerError.sourceChanged }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw EnhancerError.invalidImage("There was not enough memory to prepare this image.")
        }
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        let factor = Double(side) / Double(EnhancementConfiguration.outputSide)
        let r = metadata.geometry.drawRect
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: r.minX * factor, y: r.minY * factor, width: r.width * factor, height: r.height * factor))
        guard let output = context.makeImage() else { throw EnhancerError.invalidImage("The image could not be prepared.") }
        return try png(output)
    }

    public static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw EnhancerError.invalidImage("The PNG image could not be created.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw EnhancerError.invalidImage("The PNG image could not be encoded.") }
        return data as Data
    }

    public static func validateOutput(_ data: Data) throws {
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw EnhancerError.invalidResponse("OpenAI returned a file that could not be decoded as a PNG. The returned file has been retained for review.")
        }
        let side = EnhancementConfiguration.outputSide
        guard width == side, height == side else {
            throw EnhancerError.invalidResponse("OpenAI returned \(width.formatted()) × \(height.formatted()) instead of 2,880 × 2,880. The returned file has been retained. It was not resized or submitted again.")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw EnhancerError.invalidResponse("The returned PNG could not be fully decoded. It has been retained for review.")
        }
        let alpha = image.alphaInfo
        if [.first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly].contains(alpha) {
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            let opaque = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                              bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
                let pixels = buffer.bindMemory(to: UInt8.self)
                return stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 }
            }
            guard opaque else { throw EnhancerError.invalidResponse("The returned wallpaper contains transparent areas. It has been retained for review instead of being accepted as a completed wallpaper.") }
        }
    }
}
