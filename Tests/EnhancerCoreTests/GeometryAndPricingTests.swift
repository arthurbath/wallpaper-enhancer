import Foundation
import Testing
@testable import EnhancerCore

@Test func balancedLandscape() {
    let geometry = SquareGeometry(width: 4000, height: 2000)
    #expect(geometry.side == 3000)
    #expect(geometry.cropPerEdge == 500)
    #expect(geometry.extensionPerEdge == 500)
    #expect(geometry.drawRect == CGRect(x: -480, y: 480, width: 3840, height: 1920))
}

@Test func balancedPortraitAndOddDimensions() {
    let portrait = SquareGeometry(width: 2000, height: 4000)
    #expect(portrait.drawRect == CGRect(x: 480, y: -480, width: 1920, height: 3840))
    let odd = SquareGeometry(width: 4001, height: 2000)
    #expect(odd.side == 3000.5)
    #expect(odd.cropPerEdge == 500.25)
    #expect(abs(odd.drawRect.midX - 1440) < 0.00001)
    #expect(abs(odd.drawRect.midY - 1440) < 0.00001)
}

@Test func squareRequiresNoExpansion() {
    let geometry = SquareGeometry(width: 2400, height: 2400)
    #expect(geometry.isSquare)
    #expect(geometry.extensionFraction == 0)
    #expect(geometry.drawRect == CGRect(x: 0, y: 0, width: 2880, height: 2880))
}

@Test func measuredUsageCalculatesKnownCost() throws {
    let json = Data("""
    {"input_tokens":1814,"input_tokens_details":{"image_tokens":1521,"text_tokens":293},"output_tokens":10542,"output_tokens_details":{"image_tokens":10542,"text_tokens":0},"total_tokens":12356}
    """.utf8)
    let usage = try JSONDecoder().decode(TokenUsage.self, from: json)
    let cost = CostBreakdown(usage: usage)
    #expect(abs(cost.totalUSD - 0.329893) < 0.000000001)
    #expect(abs(cost.outputImageUSD - 0.31626) < 0.000000001)
    #expect(Pricing.dollars(cost.totalUSD) == "$0.33")
}

@Test func estimatesIncludeInputAndExpansionPrompt() {
    let square = Pricing.estimate(geometry: .init(width: 2400, height: 2400))
    let landscape = Pricing.estimate(geometry: .init(width: 4000, height: 2000))
    #expect(square > 0.328)
    #expect(square < 0.35)
    #expect(landscape > square)
    #expect(EnhancementConfiguration.prompt(for: .init(width: 4000, height: 2000)).contains("transparent bands"))
}
