import Foundation

public enum EnhancementQuality: String, CaseIterable, Codable, Sendable {
    case low, medium, high, xhigh, max

    public var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra-high"
        case .max: return "Maximum"
        }
    }
    public var selectionTitle: String { self == .max ? "Maximum (Highest)" : title }
}

public enum EnhancementConfiguration {
    public static let bundleID = "garden.bath.wallpaper-enhancer"
    public static let model = "gpt-image-2.5-sunburst"
    public static let defaultQuality = EnhancementQuality.xhigh
    public static let outputSide = 2880
    public static let pricingDate = "2026 Nov 2"
    public static let pricingURL = "https://developers.openai.com/api/docs/pricing#image-generation"

    public static func prompt(for geometry: SquareGeometry) -> String {
        let framing = geometry.isSquare
            ? "Preserve the square framing, camera position, perspective, and placement of the main subjects."
            : """
            The supplied square guide already contains the required centered crop. Its transparent bands mark missing scenery that you must reconstruct naturally. Fill those bands seamlessly, preserving the scale, placement, and center of the retained scene. Do not zoom, shift the subject, restore cropped edges, or crop the square again. The guide's retained content occupies \(Int((1 - geometry.extensionFraction) * 100))% of the square area. The final image must have a completely opaque photographic background with no blank or transparent bands.
            """
        return """
        Reconstruct and repaint this image as a clean, richly detailed, high-quality wallpaper. Preserve its visual medium: Photographs should remain photographic, and existing illustrations or artwork should retain their original character. Preserve the original scene's identity, major forms, viewpoint, lighting, color palette, and atmosphere. \(framing)

        Replace low-resolution mush, blur, digital noise, and compression artifacts with convincing newly reconstructed photographic detail. It is acceptable to invent plausible fine details instead of copying every small feature exactly. Reconstruct natural material texture, irregular surfaces, foliage, water, and other existing features as appropriate to this particular scene. Preserve physically plausible reflections, refraction, depth, and intentional softness. Keep naturally smooth regions smooth.

        Make the result substantially cleaner and more detailed when enlarged on a large monitor. For photographic sources, maintain natural photographic texture and realistic contrast without turning them into illustrations. Avoid crunchy sharpening halos, waxy denoising, artificial HDR, oversaturation, or repetitive invented patterns. Do not add unrelated subjects, people, text, logos, watermarks, borders, or new focal points. Return one completely filled square image.
        """
    }
}

public enum EnhancerError: Error, LocalizedError, Sendable {
    case invalidImage(String)
    case sourceChanged
    case credential(String)
    case api(String, uncertain: Bool, stopBatch: Bool)
    case invalidResponse(String)
    case saving(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImage(let reason), .credential(let reason), .invalidResponse(let reason), .saving(let reason): return reason
        case .sourceChanged: return "This source changed after it was added. Remove it and add the current file before enhancing."
        case .api(let reason, _, _): return reason
        }
    }
    public var uncertain: Bool {
        if case .api(_, let value, _) = self { return value }
        return false
    }
    public var stopsBatch: Bool {
        switch self {
        case .credential: return true
        case .api(_, _, let value): return value
        default: return false
        }
    }
}
