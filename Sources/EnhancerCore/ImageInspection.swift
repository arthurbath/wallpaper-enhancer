import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FileDigest {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func sha256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum ImageInspection {
    public static func inspect(_ url: URL) throws -> ImageMetadata {
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let rawHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              rawWidth > 0, rawHeight > 0 else {
            throw EnhancerError.invalidImage("This file could not be read as an image. Download it locally or choose a supported image file.")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        let width = rotated ? rawHeight : rawWidth
        let height = rotated ? rawWidth : rawHeight
        let byteCount = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        let score = edgeScore(source)
        let geometry = SquareGeometry(width: width, height: height)
        var warnings: [String] = []
        if min(width, height) < 1024 {
            warnings.append("Small source: \(width.formatted()) × \(height.formatted()). Fine detail will need substantial reconstruction, and a convincing result is less certain.")
        }
        if score < 1.5 {
            warnings.append("Very little fine detail was detected. This can indicate blur, although soft focus or minimal artwork may be intentional.")
        }
        if geometry.extensionFraction > 0.35 {
            warnings.append("About \(Int((geometry.extensionFraction * 100).rounded()))% of the square will be newly generated scenery. The central content will remain centered.")
        }
        return ImageMetadata(width: width, height: height, byteCount: byteCount,
                             sourceHash: try FileDigest.sha256(url: url), edgeScore: score, warnings: warnings)
    }

    public static func orientedImage(_ url: URL, maxSide: Int = 6000) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw EnhancerError.invalidImage("The source image could not be decoded. It may be damaged or unavailable locally.")
        }
        return image
    }

    private static func edgeScore(_ source: CGImageSource) -> Double {
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ] as CFDictionary) else { return 0 }
        let w = thumbnail.width
        let h = thumbnail.height
        guard w > 2, h > 2 else { return 0 }
        var pixels = [UInt8](repeating: 0, count: w * h)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return 0 }
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: w, height: h))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var total = 0.0
            for y in 1..<(h - 1) {
                for x in 1..<(w - 1) {
                    let i = y * w + x
                    total += Double(abs(Int(bytes[i]) - Int(bytes[i + 1])) + abs(Int(bytes[i]) - Int(bytes[i + w])))
                }
            }
            return total / Double((w - 2) * (h - 2) * 2)
        }
    }
}

public enum ImageImports {
    public static func files(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls where url.isFileURL {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
                result.append(url) // Surface a missing selection as an import failure, even in a mixed batch.
                continue
            }
            if directory.boolValue {
                if let enumerator = FileManager.default.enumerator(at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let file as URL in enumerator {
                        if isImage(file) { result.append(file) }
                    }
                }
            } else { result.append(url) }
        }
        return result.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
    private static func isImage(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]), values.isRegularFile == true else { return false }
        return values.contentType?.conforms(to: .image) == true
    }
}
