import Foundation
import Testing
@testable import EnhancerCore

@Test func writerPreservesCollisionsAndReusesIdenticalContent() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let data = Data("a generated image".utf8)
    let collision = folder.appendingPathComponent(FileDigest.sha256(data) + ".png")
    let existing = Data("an unrelated existing file".utf8)
    try existing.write(to: collision)
    let output = try ResultWriter.save(data, to: folder)
    #expect(output != collision)
    #expect(try Data(contentsOf: collision) == existing)
    #expect(try Data(contentsOf: output) == data)
    let cleanFolder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: cleanFolder) }
    let first = try ResultWriter.save(data, to: cleanFolder)
    let second = try ResultWriter.save(data, to: cleanFolder)
    #expect(first == second)
    #expect(try FileManager.default.contentsOfDirectory(at: cleanFolder, includingPropertiesForKeys: nil).count == 1)
}

@Test func interruptedRequestIsNeverAutomaticallyResubmitted() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder)
    let metadata = ImageMetadata(width: 2400, height: 2400, byteCount: 100, sourceHash: "source", edgeScore: 10, warnings: [])
    var job = EnhancementJob(sourceURL: folder.appendingPathComponent("source.png"), metadata: metadata, isDuplicate: false)
    job.status = .enhancing
    var state = SavedState()
    state.jobs = [job]
    try repository.save(state)
    let session = try repository.beginSession()
    #expect(session.state.jobs.isEmpty)
    #expect(session.interruptedRequests == 1)
    #expect(try repository.beginSession().interruptedRequests == 0)
}

@Test func cachedResponseCanBeSavedAfterDestinationFailureWithoutAPICall() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let repository = try StateRepository(root: folder.appendingPathComponent("state"))
    let id = UUID()
    let data = try ImagePreparation.png(solidImage(width: 2880, height: 2880))
    let receipt = RecoveryReceipt(jobID: id, sourceHash: "source", usage: nil, requestID: "request", createdAt: Date(), elapsedSeconds: 1,
                                  returnedQuality: "xhigh", returnedSize: "2880x2880")
    try repository.cache(data: data, receipt: receipt)
    let transport = RecordingTransport(result: .init(data: Data(), status: 500))
    let engine = ProcessingEngine(repository: repository, client: .init(transport: transport))
    do { _ = try await engine.saveCached(jobID: id, destination: folder.appendingPathComponent("missing")); Issue.record("An unavailable folder should fail") }
    catch { #expect(FileManager.default.fileExists(atPath: repository.imageURL(id).path)) }
    let output = try await engine.saveCached(jobID: id, destination: folder)
    #expect(try Data(contentsOf: output.outputURL) == data)
    #expect(await transport.callCount == 0)
}

actor RecordingTransport: ImageTransport {
    let result: HTTPResult
    let failure: URLError.Code?
    var callCount = 0
    var body = Data()
    var request: URLRequest?
    init(result: HTTPResult, failure: URLError.Code? = nil) { self.result = result; self.failure = failure }
    func upload(request: URLRequest, file: URL) async throws -> HTTPResult {
        callCount += 1
        self.request = request
        body = try Data(contentsOf: file)
        if let failure { throw URLError(failure) }
        return result
    }
}

@Test func requestUsesExactSettingsAndDoesNotWriteCredentialToBody() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let payload = Data("{\"data\":[{\"b64_json\":\"cGl4ZWxz\"}],\"quality\":\"xhigh\",\"size\":\"2880x2880\"}".utf8)
    let transport = RecordingTransport(result: .init(data: payload, status: 200))
    let requestFile = folder.appendingPathComponent("request")
    _ = try await OpenAIClient(transport: transport).enhance(guide: Data("guide".utf8), geometry: .init(width: 4000, height: 2000),
        credential: "test-token", requestFile: requestFile, clientRequestID: UUID())
    let body = String(decoding: await transport.body, as: UTF8.self)
    #expect(body.contains("gpt-image-2.5-sunburst"))
    #expect(body.contains("xhigh"))
    #expect(body.contains("2880x2880"))
    #expect(body.contains("transparent bands"))
    #expect(!body.contains("test-token"))
    #expect(!FileManager.default.fileExists(atPath: requestFile.path))
    #expect(await transport.request?.url?.absoluteString == "https://api.openai.com/v1/images/edits")
}

@Test func timeoutRemainsUncertainAndIsNotRetried() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let transport = RecordingTransport(result: .init(data: Data(), status: 500), failure: .timedOut)
    do {
        _ = try await OpenAIClient(transport: transport).enhance(guide: Data(), geometry: .init(width: 1, height: 1),
            credential: "test-token", requestFile: folder.appendingPathComponent("request"), clientRequestID: UUID())
        Issue.record("Expected timeout")
    } catch let error as EnhancerError { #expect(error.uncertain) }
    #expect(await transport.callCount == 1)
}

@Test func errorTextRedactsCredentials() {
    #expect(SafeErrorText.redact("Invalid token test-token", credential: "test-token") == "Invalid token [redacted]")
}

@Test func duplicateInputsRemainEligibleWithWarningsForExplicitBatchConfirmation() {
    let url = URL(fileURLWithPath: "/tmp/source.png")
    let metadata = ImageMetadata(width: 2000, height: 2000, byteCount: 100, sourceHash: "same", edgeScore: 10, warnings: [])
    let first = EnhancementJob(sourceURL: url, metadata: metadata, isDuplicate: false)
    #expect(DuplicateDetection.matches("same", jobs: [first]))
    let repeated = EnhancementJob(sourceURL: url, metadata: metadata, isDuplicate: true)
    #expect(repeated.isDuplicate)
    #expect(repeated.canEnhance)
    var completed = first
    completed.status = .completed
    completed.outputHash = "result"
    #expect(DuplicateDetection.matches("same", jobs: [completed]))
    #expect(DuplicateDetection.matches("result", jobs: [completed]))
    #expect(!DuplicateDetection.matches("result", jobs: []))
    #expect(!DuplicateDetection.matches("different", jobs: [completed]))
}

@Test func missingInputInMixedSelectionIsReportedInsteadOfSilentlySkipped() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let missing = folder.appendingPathComponent("missing.jpg")
    let valid = folder.appendingPathComponent("valid.png")
    try ImagePreparation.png(solidImage(width: 120, height: 120)).write(to: valid)
    let files = ImageImports.files(from: [valid, missing])
    #expect(files.count == 2)
    #expect(files.contains(missing))
    #expect(throws: EnhancerError.self) { try ImageInspection.inspect(missing) }
}

@Test func concurrentIdenticalOutputsArePublishedWithoutOverwriting() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let data = Data(repeating: 42, count: 1024 * 1024)
    let outputs = try await withThrowingTaskGroup(of: URL.self) { group in
        for _ in 0..<8 { group.addTask { try ResultWriter.save(data, to: folder) } }
        var urls: [URL] = []
        for try await url in group { urls.append(url) }
        return urls
    }
    #expect(Set(outputs).count == 1)
    #expect(try Data(contentsOf: outputs[0]) == data)
    #expect(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).count == 1)
}
