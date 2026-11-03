import Foundation
import Testing
@testable import EnhancerCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["WALLPAPER_ENHANCER_KEYCHAIN_QA"] == "1"))
func systemKeychainCreatesReplacesAndRemovesOnlyItsOwnTestItem() throws {
    let store = CredentialStore(service: CredentialStore.defaultService + ".test." + UUID().uuidString)
    defer { try? store.remove() }
    #expect(try !store.isConfigured())
    try store.save("not-a-real-openai-key-first")
    #expect(try store.isConfigured())
    #expect(try store.load() == "not-a-real-openai-key-first")
    try store.save("not-a-real-openai-key-replacement")
    #expect(try store.load() == "not-a-real-openai-key-replacement")
    try store.remove()
    #expect(try !store.isConfigured())
    try store.remove()
}
