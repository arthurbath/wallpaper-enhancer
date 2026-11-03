import Foundation

public struct TokenUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let inputDetails: Details
    public let outputTokens: Int
    public let outputDetails: Details?
    public let totalTokens: Int
    public struct Details: Codable, Equatable, Sendable {
        public let imageTokens: Int
        public let textTokens: Int
        enum CodingKeys: String, CodingKey { case imageTokens = "image_tokens", textTokens = "text_tokens" }
        public init(imageTokens: Int, textTokens: Int) { self.imageTokens = imageTokens; self.textTokens = textTokens }
    }
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens", inputDetails = "input_tokens_details"
        case outputTokens = "output_tokens", outputDetails = "output_tokens_details", totalTokens = "total_tokens"
    }
    public init(inputTokens: Int, inputDetails: Details, outputTokens: Int, outputDetails: Details?, totalTokens: Int) {
        self.inputTokens = inputTokens; self.inputDetails = inputDetails; self.outputTokens = outputTokens
        self.outputDetails = outputDetails; self.totalTokens = totalTokens
    }
}

public struct CostBreakdown: Codable, Equatable, Sendable {
    public let inputImageUSD: Double
    public let inputTextUSD: Double
    public let outputImageUSD: Double
    public var totalUSD: Double { inputImageUSD + inputTextUSD + outputImageUSD }
    public init(usage: TokenUsage) {
        inputImageUSD = Double(usage.inputDetails.imageTokens) * 8 / 1_000_000
        inputTextUSD = Double(usage.inputDetails.textTokens) * 5 / 1_000_000
        outputImageUSD = Double(usage.outputDetails?.imageTokens ?? usage.outputTokens) * 30 / 1_000_000
    }
}

public enum Pricing {
    // Official GPT Image 2.5 calculator at 2880x2880, checked 2026 Nov 2.
    // https://developers.openai.com/api/docs/guides/image-generation#gpt-image-25-and-gpt-image-2-output-tokens
    // Extra-high also matches the paid validation measured on 2026 Oct 31.
    public static func outputTokens(quality: EnhancementQuality) -> Int {
        switch quality {
        case .low: return 659
        case .medium: return 1483
        case .high: return 5930
        case .xhigh: return 10542
        case .max: return 23719
        }
    }
    public static let estimatedInputImageTokens = 1521
    public static func estimate(geometry: SquareGeometry, quality: EnhancementQuality = EnhancementConfiguration.defaultQuality) -> Double {
        let promptTokens = Int(ceil(Double(EnhancementConfiguration.prompt(for: geometry).utf8.count) / 3))
        return Double(outputTokens(quality: quality)) * 30 / 1_000_000
            + Double(estimatedInputImageTokens) * 8 / 1_000_000
            + Double(promptTokens) * 5 / 1_000_000
    }
    public static func dollars(_ amount: Double, precise: Bool = false) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(precise ? 6 : 2)))
    }
}

/// Captures the exact ready images and quality reviewed before a paid batch starts.
public struct EnhancementBatch: Sendable {
    public let jobs: [EnhancementJob]
    public let quality: EnhancementQuality
    public var estimatedTotal: Double { jobs.reduce(0) { $0 + estimate(for: $1) } }
    public var perImageEstimate: String {
        let estimates = jobs.map { estimate(for: $0) }
        let minimum = estimates.min() ?? Pricing.estimate(geometry: .init(width: 2880, height: 2880), quality: quality)
        let maximum = estimates.max() ?? Pricing.estimate(geometry: .init(width: 4000, height: 2000), quality: quality)
        let low = Pricing.dollars(minimum)
        let high = Pricing.dollars(maximum)
        return low == high ? low : "\(low)-\(high)"
    }
    public init(jobs: [EnhancementJob], quality: EnhancementQuality) {
        self.quality = quality
        self.jobs = jobs.filter(\.canEnhance).map { job in
            var snapshot = job
            snapshot.requestedQuality = quality
            return snapshot
        }
    }
    public func estimate(for job: EnhancementJob) -> Double {
        Pricing.estimate(geometry: job.metadata.geometry, quality: quality)
    }
}
