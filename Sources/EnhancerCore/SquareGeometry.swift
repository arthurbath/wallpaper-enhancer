import Foundation

public struct SquareGeometry: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }
    public var side: Double { (Double(width) + Double(height)) / 2 }
    public var isSquare: Bool { width == height }
    public var cropPerEdge: Double { abs(Double(width) - Double(height)) / 4 }
    public var extensionPerEdge: Double { cropPerEdge }
    public var extensionFraction: Double { 1 - min(Double(width), Double(height)) / side }
    public var scale: Double { Double(EnhancementConfiguration.outputSide) / side }
    public var drawRect: CGRect {
        let w = Double(width) * scale
        let h = Double(height) * scale
        let output = Double(EnhancementConfiguration.outputSide)
        return CGRect(x: (output - w) / 2, y: (output - h) / 2, width: w, height: h)
    }
    public var summary: String {
        if isSquare { return "Square composition preserved" }
        let amount = Int(cropPerEdge.rounded()).formatted()
        return width > height
            ? "Crop \(amount)px from each side. Extend \(amount)px above and below."
            : "Crop \(amount)px above and below. Extend \(amount)px on each side."
    }
}
