import AppKit
import EnhancerCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class AppStore {
    var state: SavedState
    var selectedID: UUID?
    var isImporting = false
    var isRunning = false
    var stopRequested = false
    var notice: String?
    var importIssues: [String] = []
    var showingImportIssues = false
    var quitWhenFinished = false
    var lastBatchJobIDs: [UUID] = []
    var batchFinishedCount = 0
    var batchTotalCount = 0
    let repository: StateRepository
    let engine: ProcessingEngine
    let credentials: CredentialStore
    var hasAPIKey = false
    var credentialIssue: String?
    private var pendingImports: [URL] = []
    private var batchTask: Task<Void, Never>?
    var sessionReceipts: [UUID: RecoveryReceipt] = [:]
    var qa: QAManifest?
    private var qaStarted = false

    init() {
        let manifest = QAManifest.fromArguments()
        qa = manifest
        let loaded: (StateRepository, SavedState, String?)
        do {
            let repo = try StateRepository(root: manifest.map { URL(fileURLWithPath: $0.stateFolder, isDirectory: true) })
            let session = try repo.beginSession()
            loaded = (repo, session.state, session.interruptedRequests > 0
                ? "A previous image request was interrupted and may have used credits. No image was returned and no request was retried."
                : nil)
        } catch {
            // A separate temporary store keeps the window usable if saved state is damaged.
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("WallpaperEnhancer-\(UUID().uuidString)")
            let repo = try! StateRepository(root: fallback)
            loaded = (repo, SavedState(), "The saved queue could not be loaded. Its original files were preserved. This session is using temporary state. \(error.localizedDescription)")
        }
        repository = loaded.0
        let credentialService = manifest.map {
            CredentialStore.defaultService + ".qa." + FileDigest.sha256(Data($0.stateFolder.utf8)).prefix(24)
        } ?? CredentialStore.defaultService
        credentials = CredentialStore(service: credentialService)
        engine = ProcessingEngine(repository: repository, credentials: credentials)
        state = loaded.1
        notice = loaded.2
        if let outputFolder = manifest?.outputFolder {
            state.destinationPath = outputFolder
            state.destinationBookmark = nil
        }
        if let quality = manifest?.quality { state.selectedQuality = quality }
        selectedID = state.jobs.first?.id
        refreshCredentialStatus()
    }

    var jobs: [EnhancementJob] { state.jobs }
    var selected: EnhancementJob? { state.jobs.first { $0.id == selectedID } }
    var readyJobs: [EnhancementJob] { state.jobs.filter(\.canEnhance) }
    var quality: EnhancementQuality {
        get { state.quality }
        set {
            guard !isRunning else { return }
            state.selectedQuality = newValue
            persist()
        }
    }
    var batchPlan: EnhancementBatch { .init(jobs: state.jobs, quality: quality) }
    var estimatedTotal: Double { batchPlan.estimatedTotal }
    func quality(for job: EnhancementJob) -> EnhancementQuality {
        job.status == .queued ? quality : (job.requestedQuality ?? EnhancementConfiguration.defaultQuality)
    }
    func estimatedCost(for job: EnhancementJob) -> Double {
        Pricing.estimate(geometry: job.metadata.geometry, quality: quality(for: job))
    }
    var lastBatchCost: Double { state.jobs.filter { lastBatchJobIDs.contains($0.id) }.compactMap(\.actualCost).reduce(0, +) }
    var lastBatchUnknownCosts: Int { state.jobs.filter { lastBatchJobIDs.contains($0.id) && $0.actualCost == nil && [.completed, .uncertain, .readyToSave].contains($0.status) }.count }
    var destination: URL {
        if let bookmark = state.destinationBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        }
        if let path = state.destinationPath { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func refreshCredentialStatus() {
        do { hasAPIKey = try credentials.isConfigured(); credentialIssue = nil }
        catch { hasAPIKey = false; credentialIssue = SafeErrorText.redact(error.localizedDescription) }
    }

    func saveAPIKey(_ value: String) throws {
        guard !isRunning else { throw EnhancerError.credential("Wait for the current batch to finish before changing the API key.") }
        try credentials.save(value)
        hasAPIKey = true
        credentialIssue = nil
    }

    func removeAPIKey() throws {
        guard !isRunning else { throw EnhancerError.credential("Wait for the current batch to finish before removing the API key.") }
        try credentials.remove()
        hasAPIKey = false
        credentialIssue = nil
    }

    func launch() {
        if let qa, !qaStarted {
            qaStarted = true
            addURLs(qa.inputs.map { URL(fileURLWithPath: $0) })
        }
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "Choose Wallpapers"
        panel.prompt = "Add Images"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { addURLs(panel.urls) }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        if panel.runModal() == .OK, let url = panel.url {
            state.destinationPath = url.path
            state.destinationBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            persist()
        }
    }

    func addURLs(_ urls: [URL]) {
        pendingImports.append(contentsOf: urls)
        guard !isImporting else { return }
        isImporting = true
        Task {
            while !pendingImports.isEmpty {
                let incoming = pendingImports
                pendingImports = []
                let files = await Task.detached { ImageImports.files(from: incoming) }.value
                if files.isEmpty { importIssues.append("No supported image files were found in the selection.") }
                for file in files {
                    do {
                        let metadata = try await Task.detached { try ImageInspection.inspect(file) }.value
                        let duplicate = DuplicateDetection.matches(metadata.sourceHash, jobs: state.jobs)
                        let job = EnhancementJob(sourceURL: file, metadata: metadata, isDuplicate: duplicate)
                        let preview = repository.previewURL(job.id)
                        try await Task.detached {
                            try ImagePreparation.squareGuide(sourceURL: file, metadata: metadata, side: 720).write(to: preview, options: .atomic)
                        }.value
                        state.jobs.append(job)
                        if selectedID == nil { selectedID = job.id }
                        persist()
                    } catch { importIssues.append("\(file.lastPathComponent): \(error.localizedDescription)") }
                }
            }
            isImporting = false
            if !importIssues.isEmpty { showingImportIssues = true }
            if let qa, qa.autoStart != false { startBatch(batchPlan) }
        }
    }

    func confirmEnhancement() {
        guard !readyJobs.isEmpty, !isRunning, !isImporting else { return }
        refreshCredentialStatus()
        guard hasAPIKey else { return }
        let plan = batchPlan
        let alert = NSAlert()
        alert.messageText = "Enhance \(plan.jobs.count) \(plan.jobs.count == 1 ? "Wallpaper" : "Wallpapers")?"
        let warnings = plan.jobs.filter { !$0.metadata.warnings.isEmpty }.count
        let repeats = plan.jobs.filter(\.isDuplicate).count
        var detail = "Quality: \(plan.quality.selectionTitle)\nEstimated cost per image: \(plan.perImageEstimate) USD\nEstimated batch total: \(Pricing.dollars(plan.estimatedTotal)) USD\n\nIncludes image input, prompt, and image output costs. This is an estimate, not a spending limit. Actual usage may vary.\n\nOutput: 2,880 × 2,880 PNG\nSave to: \(destination.path)"
        if warnings > 0 { detail += "\n\n\(warnings) \(warnings == 1 ? "image has" : "images have") source-quality or framing warnings. Enhancement is still allowed." }
        if repeats > 0 { detail += "\n\n\(repeats) \(repeats == 1 ? "duplicate will" : "duplicates will") receive a fresh paid enhancement." }
        alert.informativeText = detail
        alert.addButton(withTitle: warnings > 0 ? "Enhance Anyway" : "Enhance")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { startBatch(plan) }
    }

    private func startBatch(_ plan: EnhancementBatch) {
        guard !plan.jobs.isEmpty, !isRunning,
              plan.jobs.allSatisfy({ job in state.jobs.contains { $0.id == job.id && $0.canEnhance } }) else { return }
        let batch = plan.jobs
        let folder = destination
        if let qa, (plan.estimatedTotal > qa.budgetUSD || qa.budgetUSD > 3 || qa.budgetUSD <= 0) {
            notice = "The validation request exceeds its approved budget. No paid requests were made."
            writeQAReport()
            return
        }
        for job in batch {
            if let index = state.jobs.firstIndex(where: { $0.id == job.id }) {
                state.jobs[index].requestedQuality = plan.quality
            }
        }
        isRunning = true
        stopRequested = false
        lastBatchJobIDs = batch.map(\.id)
        batchFinishedCount = 0
        batchTotalCount = batch.count
        notice = nil
        batchTask = Task {
            do {
                let credential = try await engine.credential()
                for job in batch {
                    if stopRequested { break }
                    if let qa, lastBatchCost + plan.estimate(for: job) > qa.budgetUSD { notice = "Validation stopped at its approved API budget."; break }
                    do {
                        let result = try await engine.process(job: job, destination: folder, credential: credential) { [weak self] status in
                            try await self?.updateStatus(job.id, status)
                        }
                        complete(job, result)
                    } catch {
                        await recordFailure(job.id, error: error)
                        if (error as? EnhancerError)?.stopsBatch == true { break }
                    }
                    batchFinishedCount += 1
                }
            } catch { notice = error.localizedDescription }
            isRunning = false
            stopRequested = false
            persist()
            writeQAReport()
            if quitWhenFinished { NSApplication.shared.reply(toApplicationShouldTerminate: true) }
        }
    }

    private func updateStatus(_ id: UUID, _ status: JobStatus) throws {
        guard let i = state.jobs.firstIndex(where: { $0.id == id }) else { return }
        state.jobs[i].status = status
        state.jobs[i].message = nil
        if status == .preparing { state.jobs[i].startedAt = Date() }
        if !persist(), [.preparing, .enhancing].contains(status) {
            throw EnhancerError.invalidImage("The queue could not be saved safely, so no API request was started. Check free disk space and try again.")
        }
    }

    private func complete(_ job: EnhancementJob, _ result: CompletedEnhancement) {
        guard let i = state.jobs.firstIndex(where: { $0.id == job.id }) else { return }
        state.jobs[i].status = .completed
        state.jobs[i].outputURL = result.outputURL
        state.jobs[i].outputHash = result.outputHash
        state.jobs[i].actualCost = result.receipt.cost
        state.jobs[i].requestID = result.receipt.requestID
        state.jobs[i].completedAt = Date()
        state.jobs[i].message = nil
        sessionReceipts[job.id] = result.receipt
        // Persist the delivery marker before removing the only recovery copy.
        if persist() {
            do { try repository.purgeArtifacts(for: job.id) }
            catch { notice = "The image was saved, but temporary files could not be cleared. Cleanup will be attempted when the app reopens." }
            try? repository.recordDiagnostic(outcome: "saved", receipt: result.receipt)
            persist()
        }
    }

    private func recordFailure(_ id: UUID, error: Error) async {
        guard let i = state.jobs.firstIndex(where: { $0.id == id }) else { return }
        let receipt = await engine.receipt(for: id)
        sessionReceipts[id] = receipt
        let enhancerError = error as? EnhancerError
        state.jobs[i].message = SafeErrorText.redact(error.localizedDescription)
        state.jobs[i].actualCost = receipt?.cost
        state.jobs[i].requestID = receipt?.requestID
        if case .saving = enhancerError { state.jobs[i].status = .readyToSave }
        else { state.jobs[i].status = enhancerError?.uncertain == true ? .uncertain : .failed }
        try? repository.recordDiagnostic(outcome: state.jobs[i].status.rawValue, receipt: receipt)
        persist()
    }

    func saveAgain(_ job: EnhancementJob) {
        guard !isRunning else { return }
        isRunning = true
        lastBatchJobIDs = [job.id]
        batchFinishedCount = 0
        batchTotalCount = 1
        Task {
            do { complete(job, try await engine.saveCached(jobID: job.id, destination: destination)) }
            catch { await recordFailure(job.id, error: error) }
            batchFinishedCount = 1
            isRunning = false
            persist()
            writeQAReport()
            if quitWhenFinished { NSApplication.shared.reply(toApplicationShouldTerminate: true) }
        }
    }

    func enhanceAgain(_ job: EnhancementJob) {
        guard !isRunning, !isImporting else { return }
        let source = FileManager.default.fileExists(atPath: job.sourceURL.path) ? job.sourceURL : (job.outputURL ?? job.sourceURL)
        selectedID = nil
        addURLs([source])
    }

    func clearFinished() {
        guard !isRunning else { return }
        let ids = state.jobs.filter { $0.status == .completed }.map(\.id)
        state.jobs.removeAll { ids.contains($0.id) }
        lastBatchJobIDs = []
        batchFinishedCount = 0
        batchTotalCount = 0
        for id in ids { try? FileManager.default.removeItem(at: repository.previewURL(id)) }
        if !state.jobs.contains(where: { $0.id == selectedID }) { selectedID = state.jobs.first?.id }
        persist()
    }

    func removeSelected() {
        guard !isRunning, let id = selectedID,
              let index = state.jobs.firstIndex(where: { $0.id == id }) else { return }
        if state.jobs[index].status != .completed, repository.hasReturnedImage(id) {
            let alert = NSAlert()
            alert.messageText = "Discard Unsaved Returned Image?"
            alert.informativeText = "This returned image has not been saved to your output folder. Removing it will discard the app's recovery copy. Any credits already used cannot be recovered."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Discard Image")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        do { try repository.purgeArtifacts(for: id) }
        catch { notice = "The temporary image could not be removed. Check folder access and try again."; return }
        state.jobs.remove(at: index)
        sessionReceipts[id] = nil
        selectedID = state.jobs.isEmpty ? nil : state.jobs[min(index, state.jobs.count - 1)].id
        if lastBatchJobIDs.contains(id) {
            lastBatchJobIDs = []
            batchFinishedCount = 0
            batchTotalCount = 0
        }
        // Source images and files already deposited in the output folder are never removed.
        persist()
    }

    func displayURL(for job: EnhancementJob) -> URL {
        if let output = job.outputURL { return output }
        if repository.hasReturnedImage(job.id) { return repository.imageURL(job.id) }
        return repository.previewURL(job.id)
    }

    func endSession() {
        do { try repository.endSession(state) }
        catch { try? repository.recordDiagnostic(outcome: "session-cleanup-failed", receipt: nil) }
    }

    @discardableResult func persist() -> Bool {
        do { try repository.save(state); return true }
        catch { notice = "The queue could not be saved. Check free disk space. Existing outputs remain in their folder."; return false }
    }
}
