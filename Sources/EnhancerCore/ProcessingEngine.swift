import Foundation

public struct CompletedEnhancement: Sendable {
    public let outputURL: URL
    public let outputHash: String
    public let receipt: RecoveryReceipt
}

public actor ProcessingEngine {
    public let repository: StateRepository
    private let client: OpenAIClient
    private let credentials: CredentialStore
    public init(repository: StateRepository, client: OpenAIClient = .init(), credentials: CredentialStore = .init()) {
        self.repository = repository
        self.client = client
        self.credentials = credentials
    }
    public func credential() throws -> String { try credentials.load() }

    public func process(job: EnhancementJob, destination: URL, credential: String,
                        stage: @Sendable (JobStatus) async throws -> Void) async throws -> CompletedEnhancement {
        try await stage(.preparing)
        let guide = try ImagePreparation.squareGuide(sourceURL: job.sourceURL, metadata: job.metadata)
        // Persist the paid-request state before sending any image bytes.
        try await stage(.enhancing)
        let start = Date()
        let quality = job.requestedQuality ?? EnhancementConfiguration.defaultQuality
        let result = try await client.enhance(guide: guide, geometry: job.metadata.geometry, quality: quality, credential: credential,
            requestFile: repository.root.appendingPathComponent("Requests/\(job.id.uuidString).multipart"), clientRequestID: job.id)
        let receipt = RecoveryReceipt(jobID: job.id, sourceHash: job.metadata.sourceHash, usage: result.usage,
            requestID: result.requestID, createdAt: Date(), elapsedSeconds: Date().timeIntervalSince(start),
            returnedQuality: result.returnedQuality, returnedSize: result.returnedSize, requestedQuality: quality)
        do { try repository.cache(data: result.data, receipt: receipt) }
        catch { throw EnhancerError.api("OpenAI completed this request, but the local recovery folder could not be written. Check free disk space. Credits may have been used. Do not retry automatically.", uncertain: true, stopBatch: true) }
        try Self.validate(result.data, receipt: receipt)
        try await stage(.saving)
        return try saveCached(jobID: job.id, destination: destination)
    }

    public func saveCached(jobID: UUID, destination: URL) throws -> CompletedEnhancement {
        guard let receipt = repository.receipt(jobID) else { throw EnhancerError.saving("The saved response receipt is unavailable. No new image request was made.") }
        let data = try Data(contentsOf: repository.imageURL(jobID))
        try Self.validate(data, receipt: receipt)
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        let url = try ResultWriter.save(data, to: destination)
        return CompletedEnhancement(outputURL: url, outputHash: FileDigest.sha256(data), receipt: receipt)
    }

    public func receipt(for id: UUID) -> RecoveryReceipt? { repository.receipt(id) }

    private static func validate(_ data: Data, receipt: RecoveryReceipt) throws {
        try ImagePreparation.validateOutput(data)
        guard receipt.confirmsRequestedOutput else {
            throw EnhancerError.invalidResponse("OpenAI did not confirm the requested size and \(receipt.expectedQuality.title.lowercased()) quality. The returned image and usage receipt have been retained for review.")
        }
    }
}
