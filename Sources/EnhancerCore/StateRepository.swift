import Foundation

public struct SessionStart: Sendable {
    public let state: SavedState
    public let interruptedRequests: Int
}

public struct StateRepository: Sendable {
    public let root: URL
    public init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(EnhancementConfiguration.bundleID, isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        for folder in ["Recovery", "Requests", "Previews"] {
            try FileManager.default.createDirectory(at: self.root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }
    public var stateURL: URL { root.appendingPathComponent("state.json") }
    public var diagnosticsURL: URL { root.appendingPathComponent("diagnostics.json") }
    public func imageURL(_ id: UUID) -> URL { root.appendingPathComponent("Recovery/\(id.uuidString).png") }
    public func receiptURL(_ id: UUID) -> URL { root.appendingPathComponent("Recovery/\(id.uuidString).json") }
    public func previewURL(_ id: UUID) -> URL { root.appendingPathComponent("Previews/\(id.uuidString).png") }
    public func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stateURL))
    }
    public func save(_ state: SavedState) throws {
        var durable = state
        // Ordinary queue rows and completed history belong only to the running session.
        // A completed row is a short-lived delivery marker until its recovery copy is removed.
        durable.jobs = state.jobs.filter { $0.status.isActive || hasReturnedImage($0.id) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(durable).write(to: stateURL, options: .atomic)
    }
    public func cache(data: Data, receipt: RecoveryReceipt) throws {
        try data.write(to: imageURL(receipt.jobID), options: .atomic)
        try JSONEncoder().encode(receipt).write(to: receiptURL(receipt.jobID), options: .atomic)
    }
    public func receipt(_ id: UUID) -> RecoveryReceipt? {
        guard let data = try? Data(contentsOf: receiptURL(id)) else { return nil }
        return try? JSONDecoder().decode(RecoveryReceipt.self, from: data)
    }
    public func hasReturnedImage(_ id: UUID) -> Bool { FileManager.default.fileExists(atPath: imageURL(id).path) }

    public func purgeArtifacts(for id: UUID) throws {
        for url in [imageURL(id), receiptURL(id), previewURL(id), root.appendingPathComponent("Requests/\(id.uuidString).multipart")] {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    public func beginSession() throws -> SessionStart {
        let old = try load()
        var fresh = SavedState()
        fresh.destinationPath = old.destinationPath
        fresh.destinationBookmark = old.destinationBookmark
        fresh.selectedQuality = old.selectedQuality
        let delivered = Set(old.jobs.filter { $0.status == .completed }.map(\.id))
        for id in delivered { try purgeArtifacts(for: id) }

        // Recover only responses that have not been deposited. A crash between caching
        // bytes and saving state must not cause a paid result to disappear.
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "png" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !delivered.contains(id) else { continue }
            let data = try Data(contentsOf: file)
            let receipt = receipt(id)
            var job: EnhancementJob
            if let original = old.jobs.first(where: { $0.id == id }) {
                job = original
            } else {
                let metadata = (try? ImageInspection.inspect(file)) ?? ImageMetadata(width: 2880, height: 2880,
                    byteCount: data.count, sourceHash: FileDigest.sha256(data), edgeScore: 0, warnings: [])
                job = EnhancementJob(id: id, sourceURL: file, metadata: metadata, isDuplicate: false)
            }
            job.actualCost = receipt?.cost
            job.requestID = receipt?.requestID
            job.outputURL = nil
            job.completedAt = nil
            job.requestedQuality = receipt?.expectedQuality
            do {
                try ImagePreparation.validateOutput(data)
                guard receipt?.confirmsRequestedOutput == true else {
                    throw EnhancerError.invalidResponse("The saved response has incomplete size or quality information.")
                }
                job.status = .readyToSave
                job.message = "This returned image has not been saved to your output folder. Save it without another generation charge, or press Delete to discard it."
            } catch {
                job.status = .failed
                job.message = "An unsaved returned file needs review. No new request was made. Reveal the file or press Delete to discard it."
            }
            fresh.jobs.append(job)
        }
        let retainedIDs = Set(fresh.jobs.map(\.id))
        let interrupted = old.jobs.filter { [.enhancing, .saving].contains($0.status) && !retainedIDs.contains($0.id) }.count
        try clearDirectory("Previews")
        try clearDirectory("Requests")
        try clearDirectory("Receipts")
        let retainedNames = Set(retainedIDs.flatMap { ["\($0.uuidString).png", "\($0.uuidString).json"] })
        try clearDirectory("Recovery", keeping: retainedNames)
        try trimDiagnostics()
        try save(fresh)
        return SessionStart(state: fresh, interruptedRequests: interrupted)
    }

    public func endSession(_ state: SavedState) throws {
        try save(state)
        try clearDirectory("Previews")
        try clearDirectory("Requests")
    }

    private func clearDirectory(_ name: String, keeping names: Set<String> = []) throws {
        let directory = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where !names.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func recordDiagnostic(outcome: String, receipt: RecoveryReceipt?) throws {
        var records = diagnosticRecords()
        records.append(.init(date: Date(), outcome: String(outcome.prefix(40)), elapsedSeconds: receipt?.elapsedSeconds,
            costUSD: receipt?.cost, requestID: receipt?.requestID.map { String($0.prefix(128)) }))
        try writeDiagnostics(records)
    }
    private func diagnosticRecords() -> [PerformanceRecord] {
        guard let data = try? Data(contentsOf: diagnosticsURL) else { return [] }
        return (try? JSONDecoder().decode([PerformanceRecord].self, from: data)) ?? []
    }
    private func trimDiagnostics() throws {
        if FileManager.default.fileExists(atPath: diagnosticsURL.path) { try writeDiagnostics(diagnosticRecords()) }
    }
    private func writeDiagnostics(_ records: [PerformanceRecord]) throws {
        var kept = Array(records.suffix(100))
        let encoder = JSONEncoder()
        var data = try encoder.encode(kept)
        while data.count > 65_536, !kept.isEmpty {
            kept.removeFirst()
            data = try encoder.encode(kept)
        }
        try data.write(to: diagnosticsURL, options: .atomic)
    }
}

private struct PerformanceRecord: Codable {
    let date: Date
    let outcome: String
    let elapsedSeconds: Double?
    let costUSD: Double?
    let requestID: String?
}
