import Foundation
import Security

public protocol CredentialBackend: Sendable {
    func contains(service: String, account: String) throws -> Bool
    func read(service: String, account: String) throws -> String?
    func write(_ value: String, service: String, account: String) throws
    func remove(service: String, account: String) throws
}

public struct CredentialStore: Sendable {
    public static let defaultService = EnhancementConfiguration.bundleID + ".openai-api-key"
    public static let account = "openai-api-key"
    public let service: String
    private let backend: any CredentialBackend

    public init(service: String = Self.defaultService, backend: any CredentialBackend = SystemCredentialBackend()) {
        self.service = service
        self.backend = backend
    }
    public func isConfigured() throws -> Bool { try backend.contains(service: service, account: Self.account) }
    public func load() throws -> String {
        guard let value = try backend.read(service: service, account: Self.account), !value.isEmpty else {
            throw EnhancerError.credential("Add your OpenAI API key in Wallpaper Enhancer Settings before enhancing images. No image request has been submitted.")
        }
        return value
    }
    public func save(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 4096,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            throw EnhancerError.credential("Paste only the API key, without spaces, line breaks, or an Authorization prefix.")
        }
        try backend.write(value, service: service, account: Self.account)
    }
    public func remove() throws { try backend.remove(service: service, account: Self.account) }
}

public struct SystemCredentialBackend: CredentialBackend {
    public init() {}
    private func query(service: String, account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
         kSecAttrSynchronizable: false]
    }
    public func contains(service: String, account: String) throws -> Bool {
        var query = query(service: service, account: account)
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var attributes: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &attributes)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }
    public func read(service: String, account: String) throws -> String? {
        var query = query(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw EnhancerError.credential("The saved API key could not be decoded. Replace it in Settings.")
        }
        return value
    }
    public func write(_ value: String, service: String, account: String) throws {
        let query = query(service: service, account: account)
        let changes: [CFString: Any] = [kSecValueData: Data(value.utf8), kSecAttrLabel: "Wallpaper Enhancer — OpenAI API Key"]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            changes.forEach { item[$0.key] = $0.value }
            status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(query as CFDictionary, changes as CFDictionary) }
        }
        try check(status)
    }
    public func remove(service: String, account: String) throws {
        let status = SecItemDelete(query(service: service, account: account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw EnhancerError.credential("macOS could not access the saved API key (status \(status)). Unlock your login keychain or allow Wallpaper Enhancer access, then try again.")
        }
    }
}

public enum SafeErrorText {
    public static func redact(_ text: String, credential: String? = nil) -> String {
        var safe = credential.map { text.replacingOccurrences(of: $0, with: "[redacted]") } ?? text
        if let regex = try? NSRegularExpression(pattern: "sk-[A-Za-z0-9_\\-]+") {
            safe = regex.stringByReplacingMatches(in: safe, range: NSRange(safe.startIndex..., in: safe), withTemplate: "[redacted]")
        }
        return String(safe.prefix(700))
    }
}
