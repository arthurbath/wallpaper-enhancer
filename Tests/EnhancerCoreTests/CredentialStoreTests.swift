import Foundation
import Testing
@testable import EnhancerCore

private final class MemoryCredentials: CredentialBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var reads = 0
    private var rejectWrites = false
    var readCount: Int { lock.withLock { reads } }
    func failWrites() { lock.withLock { rejectWrites = true } }
    func contains(service: String, account: String) -> Bool { lock.withLock { values[service + "|" + account] != nil } }
    func read(service: String, account: String) -> String? {
        lock.withLock { reads += 1; return values[service + "|" + account] }
    }
    func write(_ value: String, service: String, account: String) throws {
        try lock.withLock {
            if rejectWrites { throw EnhancerError.credential("Storage access denied.") }
            values[service + "|" + account] = value
        }
    }
    func remove(service: String, account: String) { lock.withLock { _ = values.removeValue(forKey: service + "|" + account) } }
}

@Test func userKeyCanBeSavedReplacedAndLoadedByProcessingEngine() async throws {
    let backend = MemoryCredentials()
    let store = CredentialStore(backend: backend)
    #expect(try !store.isConfigured())
    try store.save("  sk-dummy-first-key-not-real\n")
    #expect(try store.load() == "sk-dummy-first-key-not-real")
    try store.save("sk-dummy-replacement-not-real")
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let engine = ProcessingEngine(repository: try StateRepository(root: folder), credentials: store)
    #expect(try await engine.credential() == "sk-dummy-replacement-not-real")
}

@Test func settingsPresenceCheckDoesNotReadTheSecret() throws {
    let backend = MemoryCredentials()
    let store = CredentialStore(backend: backend)
    try store.save("sk-dummy-metadata-test-not-real")
    #expect(try store.isConfigured())
    #expect(backend.readCount == 0)
}

@Test func removingUserKeyLeavesOtherCredentialsUntouched() throws {
    let backend = MemoryCredentials()
    let app = CredentialStore(backend: backend)
    let other = CredentialStore(service: "garden.bath.unrelated-tool", backend: backend)
    try other.save("sk-dummy-unrelated-not-real")
    try app.save("sk-dummy-app-key-not-real")
    try app.remove()
    try app.remove()
    #expect(try !app.isConfigured())
    #expect(try other.load() == "sk-dummy-unrelated-not-real")
}

@Test func missingAppKeyDoesNotFallBackToAnotherCredentialOrMakeARequest() async throws {
    let backend = MemoryCredentials()
    try CredentialStore(service: "garden.bath.unrelated-tool", backend: backend).save("sk-dummy-other-not-real")
    let app = CredentialStore(backend: backend)
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let transport = RecordingTransport(result: .init(data: Data(), status: 200))
    let engine = ProcessingEngine(repository: try StateRepository(root: folder), client: .init(transport: transport), credentials: app)
    do { _ = try await engine.credential(); Issue.record("An app-owned key must be configured") }
    catch { #expect(error.localizedDescription.contains("Settings")) }
    #expect(await transport.callCount == 0)
    #expect(try !app.isConfigured())
}

@Test func malformedKeyInputIsRejectedWithoutOverwritingSavedKey() throws {
    let store = CredentialStore(backend: MemoryCredentials())
    try store.save("sk-dummy-existing-not-real")
    for bad in ["", " \n ", "Bearer sk-dummy-not-real", "sk-dummy\nheader", "sk-dummy\tvalue", "sk-dummy\0value", String(repeating: "a", count: 4097)] {
        #expect(throws: EnhancerError.self) { try store.save(bad) }
        #expect(try store.load() == "sk-dummy-existing-not-real")
    }
}

@Test func failedKeyReplacementPreservesThePreviousCredential() throws {
    let backend = MemoryCredentials()
    let store = CredentialStore(backend: backend)
    try store.save("sk-dummy-existing-not-real")
    backend.failWrites()
    #expect(throws: EnhancerError.self) { try store.save("sk-dummy-new-not-real") }
    #expect(try store.load() == "sk-dummy-existing-not-real")
}

@Test func credentialIsAbsentFromQueueAndPerformanceDiagnostics() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = CredentialStore(backend: MemoryCredentials())
    let secret = "sk-dummy-storage-boundary-not-real"
    try store.save(secret)
    let repository = try StateRepository(root: folder)
    try repository.save(SavedState())
    try repository.recordDiagnostic(outcome: "saved", receipt: nil)
    for file in [repository.stateURL, repository.diagnosticsURL] {
        #expect(try !String(contentsOf: file, encoding: .utf8).contains(secret))
    }
}
