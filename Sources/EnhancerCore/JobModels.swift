import Foundation

public struct ImageMetadata: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let byteCount: Int
    public let sourceHash: String
    public let edgeScore: Double
    public let warnings: [String]
    public var geometry: SquareGeometry { .init(width: width, height: height) }
}

public enum JobStatus: String, Codable, Sendable {
    case queued, preparing, enhancing, saving, completed, failed, uncertain, readyToSave
    public var title: String {
        switch self {
        case .queued: return "Ready"
        case .preparing: return "Preparing"
        case .enhancing: return "Enhancing"
        case .saving: return "Saving"
        case .completed: return "Saved"
        case .failed: return "Needs attention"
        case .uncertain: return "Outcome uncertain"
        case .readyToSave: return "Ready to save"
        }
    }
    public var isActive: Bool { [.preparing, .enhancing, .saving].contains(self) }
}

public struct EnhancementJob: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let metadata: ImageMetadata
    public var isDuplicate: Bool
    public var status: JobStatus
    public var message: String?
    public var outputURL: URL?
    public var outputHash: String?
    public var actualCost: Double?
    public var startedAt: Date?
    public var completedAt: Date?
    public var requestID: String?
    public var requestedQuality: EnhancementQuality?
    public init(id: UUID = UUID(), sourceURL: URL, metadata: ImageMetadata, isDuplicate: Bool) {
        self.id = id; self.sourceURL = sourceURL; self.metadata = metadata
        self.isDuplicate = isDuplicate; status = .queued
    }
    public var canEnhance: Bool { status == .queued && outputURL == nil && completedAt == nil }
}

public struct SavedState: Codable, Sendable {
    public var jobs: [EnhancementJob] = []
    public var destinationBookmark: Data?
    public var destinationPath: String?
    // Optional so state from earlier versions decodes without a migration.
    public var selectedQuality: EnhancementQuality?
    public var quality: EnhancementQuality { selectedQuality ?? EnhancementConfiguration.defaultQuality }
    public init() {}
}

public enum DuplicateDetection {
    public static func matches(_ hash: String, jobs: [EnhancementJob]) -> Bool {
        jobs.contains { $0.metadata.sourceHash == hash || $0.outputHash == hash }
    }
}

public struct RecoveryReceipt: Codable, Sendable {
    public let jobID: UUID
    public let sourceHash: String
    public let usage: TokenUsage?
    public let requestID: String?
    public let createdAt: Date
    public let elapsedSeconds: Double
    public let returnedQuality: String?
    public let returnedSize: String?
    public let requestedQuality: EnhancementQuality?
    public var expectedQuality: EnhancementQuality { requestedQuality ?? EnhancementConfiguration.defaultQuality }
    public var confirmsRequestedOutput: Bool {
        returnedQuality == expectedQuality.rawValue && returnedSize == "2880x2880"
    }
    public var cost: Double? { usage.map { CostBreakdown(usage: $0).totalUSD } }
    public init(jobID: UUID, sourceHash: String, usage: TokenUsage?, requestID: String?, createdAt: Date, elapsedSeconds: Double, returnedQuality: String? = nil, returnedSize: String? = nil, requestedQuality: EnhancementQuality? = nil) {
        self.jobID = jobID; self.sourceHash = sourceHash; self.usage = usage
        self.requestID = requestID; self.createdAt = createdAt; self.elapsedSeconds = elapsedSeconds
        self.returnedQuality = returnedQuality; self.returnedSize = returnedSize
        self.requestedQuality = requestedQuality
    }
}
