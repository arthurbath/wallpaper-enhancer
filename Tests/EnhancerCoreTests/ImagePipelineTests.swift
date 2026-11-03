import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import EnhancerCore

func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

func solidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@Test func guideContainsBalancedTransparentBands() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("landscape.png")
    try ImagePreparation.png(solidImage(width: 800, height: 400)).write(to: source)
    let metadata = try ImageInspection.inspect(source)
    let guide = try ImagePreparation.squareGuide(sourceURL: source, metadata: metadata, side: 300)
    let imageSource = CGImageSourceCreateWithData(guide as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
    #expect(image.width == 300 && image.height == 300)
    var bytes = [UInt8](repeating: 0, count: 300 * 300 * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: 300, height: 300, bitsPerComponent: 8,
            bytesPerRow: 1200, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 300, height: 300))
    }
    #expect(bytes[(10 * 300 + 150) * 4 + 3] == 0)
    #expect(bytes[(150 * 300 + 150) * 4 + 3] == 255)
    #expect(bytes[(290 * 300 + 150) * 4 + 3] == 0)
    #expect(metadata.warnings.count >= 1)
}

@Test func exifRotationChangesFramingDimensions() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("rotated.jpg")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, solidImage(width: 600, height: 300), [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let metadata = try ImageInspection.inspect(url)
    #expect(metadata.width == 300 && metadata.height == 600)
    let decoded = try ImageInspection.orientedImage(url)
    #expect(decoded.width == 300 && decoded.height == 600)
}

@Test func changedSourceIsRejectedBeforeGeneration() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("source.png")
    try ImagePreparation.png(solidImage(width: 320, height: 240)).write(to: url)
    let metadata = try ImageInspection.inspect(url)
    try ImagePreparation.png(solidImage(width: 640, height: 480)).write(to: url)
    #expect(throws: EnhancerError.self) { try ImagePreparation.squareGuide(sourceURL: url, metadata: metadata) }
}

@Test func outputMustBeOpaquePNGAtRequestedSize() throws {
    let valid = try ImagePreparation.png(solidImage(width: 2880, height: 2880))
    try ImagePreparation.validateOutput(valid)
    let wrong = try ImagePreparation.png(solidImage(width: 1024, height: 1024))
    #expect(throws: EnhancerError.self) { try ImagePreparation.validateOutput(wrong) }
    #expect(throws: EnhancerError.self) { try ImagePreparation.validateOutput(Data("not an image".utf8)) }
}

@Test func duplicateBytesHaveIdenticalContentHashes() throws {
    let data = try ImagePreparation.png(solidImage(width: 120, height: 120))
    #expect(FileDigest.sha256(data) == FileDigest.sha256(Data(data)))
    #expect(FileDigest.sha256(data).count == 64)
}
