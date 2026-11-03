import Foundation
import Testing
@testable import EnhancerCore

@Test func qualityEstimatesMatchOfficialCalculatorAndIncludeInputs() {
    let geometry = SquareGeometry(width: 2400, height: 2400)
    let outputCosts: [EnhancementQuality: Double] = [
        .low: 0.01977, .medium: 0.04449, .high: 0.17790, .xhigh: 0.31626, .max: 0.71157
    ]
    var previous = 0.0
    for quality in EnhancementQuality.allCases {
        let output = Double(Pricing.outputTokens(quality: quality)) * 30 / 1_000_000
        #expect(abs(output - outputCosts[quality]!) < 0.000000001)
        let estimate = Pricing.estimate(geometry: geometry, quality: quality)
        #expect(estimate > output + 0.012168)
        #expect(estimate > previous)
        previous = estimate
    }
    #expect(Pricing.dollars(previous) == "$0.73")
    #expect(Pricing.estimate(geometry: geometry) == Pricing.estimate(geometry: geometry, quality: .xhigh))
}

@Test func batchEstimateCapturesOnlyReadyImagesAndTheirConfirmedQuality() {
    let metadata = ImageMetadata(width: 2400, height: 2400, byteCount: 100, sourceHash: "source", edgeScore: 10, warnings: [])
    var ready = EnhancementJob(sourceURL: URL(fileURLWithPath: "/tmp/source.png"), metadata: metadata, isDuplicate: false)
    var completed = ready
    completed.status = .completed
    var uncertain = ready
    uncertain.status = .uncertain
    var cached = ready
    cached.status = .readyToSave
    let reviewed = EnhancementBatch(jobs: [ready, completed, uncertain, cached, ready], quality: .max)
    ready.status = .completed
    let changed = EnhancementBatch(jobs: [ready], quality: .low)
    #expect(changed.jobs.isEmpty)
    #expect(reviewed.jobs.count == 2)
    #expect(reviewed.jobs.allSatisfy { $0.requestedQuality == .max })
    #expect(reviewed.quality == .max)
    #expect(abs(reviewed.estimatedTotal - 2 * Pricing.estimate(geometry: metadata.geometry, quality: .max)) < 0.000000001)
    #expect(reviewed.perImageEstimate == "$0.73")
}

@Test func legacyPreferencesDefaultToExtraHighAndNewPreferenceSurvivesSessionCleanup() throws {
    let legacy = try JSONDecoder().decode(SavedState.self, from: Data("{\"jobs\":[],\"destinationPath\":\"/saved/output\"}".utf8))
    #expect(legacy.quality == .xhigh)
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder)
    var state = legacy
    state.selectedQuality = .max
    try repository.save(state)
    let reopened = try repository.beginSession().state
    #expect(reopened.quality == .max)
    #expect(reopened.destinationPath == legacy.destinationPath)
}

@Test(arguments: EnhancementQuality.allCases)
func selectedQualityReachesRequestAndVerifiedReceipt(quality: EnhancementQuality) async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder.appendingPathComponent("state"))
    let source = folder.appendingPathComponent("source.png")
    try ImagePreparation.png(solidImage(width: 400, height: 400)).write(to: source)
    var job = EnhancementJob(sourceURL: source, metadata: try ImageInspection.inspect(source), isDuplicate: false)
    job.requestedQuality = quality
    let image = try ImagePreparation.png(solidImage(width: 2880, height: 2880))
    let payload = try JSONSerialization.data(withJSONObject: [
        "data": [["b64_json": image.base64EncodedString()]],
        "quality": quality.rawValue, "size": "2880x2880"
    ])
    let transport = RecordingTransport(result: .init(data: payload, status: 200))
    let engine = ProcessingEngine(repository: repository, client: .init(transport: transport))
    let result = try await engine.process(job: job, destination: folder, credential: "dummy-quality-key") { _ in }
    #expect(result.receipt.requestedQuality == quality)
    #expect(result.receipt.confirmsRequestedOutput)
    #expect(try Data(contentsOf: result.outputURL) == image)
    let body = String(decoding: await transport.body, as: UTF8.self)
    #expect(body.contains("name=\"quality\"\r\n\r\n\(quality.rawValue)\r\n"))
    #expect(body.contains("name=\"background\"\r\n\r\nopaque\r\n"))
    #expect(!body.contains("dummy-quality-key"))
    #expect(await transport.callCount == 1)
}

@Test func maximumResultRecoversAfterPreferenceChangeAndRejectsLowerReturnedQuality() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder.appendingPathComponent("state"))
    let image = try ImagePreparation.png(solidImage(width: 2880, height: 2880))
    let goodID = UUID()
    let wrongID = UUID()
    for (id, returned) in [(goodID, "max"), (wrongID, "xhigh")] {
        try repository.cache(data: image, receipt: RecoveryReceipt(jobID: id, sourceHash: "source", usage: nil,
            requestID: nil, createdAt: Date(), elapsedSeconds: 1, returnedQuality: returned,
            returnedSize: "2880x2880", requestedQuality: .max))
    }
    var preferences = SavedState()
    preferences.selectedQuality = .low
    try repository.save(preferences)
    let reopened = try repository.beginSession().state
    #expect(reopened.quality == .low)
    #expect(reopened.jobs.first { $0.id == goodID }?.status == .readyToSave)
    #expect(reopened.jobs.first { $0.id == goodID }?.requestedQuality == .max)
    #expect(reopened.jobs.first { $0.id == wrongID }?.status == .failed)
    let transport = RecordingTransport(result: .init(data: Data(), status: 500))
    let engine = ProcessingEngine(repository: repository, client: .init(transport: transport))
    _ = try await engine.saveCached(jobID: goodID, destination: folder)
    await #expect(throws: EnhancerError.self) { try await engine.saveCached(jobID: wrongID, destination: folder) }
    #expect(repository.hasReturnedImage(wrongID))
    #expect(await transport.callCount == 0)
}
