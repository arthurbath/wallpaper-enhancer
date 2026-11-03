import Foundation
import Testing
@testable import EnhancerCore

private func sampleJob(in folder: URL) -> EnhancementJob {
    let metadata = ImageMetadata(width: 2400, height: 2400, byteCount: 100, sourceHash: "source", edgeScore: 10, warnings: [])
    return EnhancementJob(sourceURL: folder.appendingPathComponent("original.png"), metadata: metadata, isDuplicate: false)
}
private func sampleReceipt(_ id: UUID) -> RecoveryReceipt {
    RecoveryReceipt(jobID: id, sourceHash: "private-source-hash", usage: nil, requestID: "request-id", createdAt: Date(), elapsedSeconds: 12,
                    returnedQuality: EnhancementConfiguration.defaultQuality.rawValue, returnedSize: "2880x2880")
}

@Test func freshSessionClearsLegacyHistoryAndCachesButPreservesPreferencesAndUserFiles() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder.appendingPathComponent("app-state"))
    var completed = sampleJob(in: folder)
    completed.status = .completed
    completed.outputURL = folder.appendingPathComponent("delivered.png")
    try Data("original".utf8).write(to: completed.sourceURL)
    try Data("delivered".utf8).write(to: completed.outputURL!)
    var state = SavedState()
    state.jobs = [sampleJob(in: folder), completed]
    state.destinationPath = folder.path
    state.destinationBookmark = Data("saved-bookmark".utf8)
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
    legacy["history"] = [["old": "no longer retained"]]
    try JSONSerialization.data(withJSONObject: legacy).write(to: repository.stateURL)
    try FileManager.default.createDirectory(at: repository.root.appendingPathComponent("Receipts"), withIntermediateDirectories: true)
    for path in ["Previews/old.png", "Requests/old.multipart", "Receipts/old.json"] {
        try Data(repeating: 1, count: 1024).write(to: repository.root.appendingPathComponent(path))
    }
    try repository.cache(data: Data("completed recovery copy".utf8), receipt: sampleReceipt(completed.id))
    let session = try repository.beginSession()
    #expect(session.state.jobs.isEmpty)
    #expect(session.state.destinationPath == state.destinationPath)
    #expect(session.state.destinationBookmark == state.destinationBookmark)
    for name in ["Recovery", "Previews", "Requests", "Receipts"] {
        #expect(try FileManager.default.contentsOfDirectory(atPath: repository.root.appendingPathComponent(name).path).isEmpty)
    }
    let saved = try String(contentsOf: repository.stateURL, encoding: .utf8)
    #expect(!saved.contains("history"))
    #expect(!saved.contains("original.png"))
    #expect(try Data(contentsOf: completed.sourceURL) == Data("original".utf8))
    #expect(try Data(contentsOf: completed.outputURL!) == Data("delivered".utf8))
}

@Test func unsavedResponseSurvivesRestartAndSavesWithoutGenerationThenIsPurged() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder.appendingPathComponent("app-state"))
    var job = sampleJob(in: folder)
    job.status = .saving
    let image = try ImagePreparation.png(solidImage(width: 2880, height: 2880))
    try repository.cache(data: image, receipt: sampleReceipt(job.id))
    var state = SavedState()
    state.jobs = [job]
    try repository.save(state)
    var reopened = try repository.beginSession().state
    #expect(reopened.jobs.count == 1)
    #expect(reopened.jobs[0].status == .readyToSave)
    #expect(!reopened.jobs[0].canEnhance)
    let transport = RecordingTransport(result: .init(data: Data(), status: 500))
    let engine = ProcessingEngine(repository: repository, client: .init(transport: transport))
    let saved = try await engine.saveCached(jobID: job.id, destination: folder)
    #expect(await transport.callCount == 0)
    reopened.jobs[0].status = .completed
    reopened.jobs[0].outputURL = saved.outputURL
    try repository.save(reopened)
    // Simulate a crash after recording delivery but before deleting temporary data.
    let fresh = try repository.beginSession()
    #expect(fresh.state.jobs.isEmpty)
    #expect(!repository.hasReturnedImage(job.id))
    #expect(repository.receipt(job.id) == nil)
    #expect(try Data(contentsOf: saved.outputURL) == image)
}

@Test func orphanedPaidResponseIsRecoveredWithoutQueueMetadata() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder)
    let id = UUID()
    try repository.cache(data: ImagePreparation.png(solidImage(width: 2880, height: 2880)), receipt: sampleReceipt(id))
    let recovered = try repository.beginSession()
    #expect(recovered.state.jobs.map(\.id) == [id])
    #expect(recovered.state.jobs[0].status == .readyToSave)
    #expect(repository.hasReturnedImage(id))
}

@Test func invalidUnsavedResponseIsRetainedForReviewUntilExplicitDiscard() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder)
    let id = UUID()
    try repository.cache(data: Data("invalid response".utf8), receipt: sampleReceipt(id))
    let recovered = try repository.beginSession()
    #expect(recovered.state.jobs[0].status == .failed)
    #expect(repository.hasReturnedImage(id))
    try repository.purgeArtifacts(for: id)
    #expect(try repository.beginSession().state.jobs.isEmpty)
}

@Test func repeatedDeliveriesDoNotAccumulateImagesReceiptsOrQueueHistory() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder)
    var state = SavedState()
    for _ in 0..<120 {
        var job = sampleJob(in: folder)
        job.status = .completed
        state.jobs.append(job)
        let receipt = sampleReceipt(job.id)
        try repository.cache(data: Data(repeating: 3, count: 1024), receipt: receipt)
        try Data("guide".utf8).write(to: repository.previewURL(job.id))
        try repository.save(state)
        try repository.purgeArtifacts(for: job.id)
        try repository.recordDiagnostic(outcome: "saved", receipt: receipt)
        try repository.save(state)
    }
    #expect(try repository.load().jobs.isEmpty)
    for name in ["Recovery", "Previews", "Requests"] {
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(name).path).isEmpty)
    }
    let data = try Data(contentsOf: repository.diagnosticsURL)
    let records = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    #expect(records.count == 100)
    #expect(data.count <= 65_536)
    let log = String(decoding: data, as: UTF8.self)
    #expect(!log.contains("private-source-hash"))
    #expect(!log.contains("original.png"))
    #expect(!log.contains(folder.path))
}

@Test func quittingDiscardsUnprocessedQueueAndPreviews() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder)
    let job = sampleJob(in: folder)
    var state = SavedState()
    state.jobs = [job]
    state.destinationPath = "/saved/output/folder"
    try Data("guide".utf8).write(to: repository.previewURL(job.id))
    try repository.endSession(state)
    #expect(try repository.load().jobs.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: repository.previewURL(job.id).path))
    #expect(try repository.beginSession().state.destinationPath == state.destinationPath)
}
