import Foundation
import EnhancerCore

struct QAManifest: Codable {
    let inputs: [String]
    let outputFolder: String?
    let stateFolder: String
    let resultFile: String
    let budgetUSD: Double
    let autoStart: Bool?
    let quality: EnhancementQuality?
    static func fromArguments() -> QAManifest? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--qa-manifest"), args.indices.contains(index + 1),
              let data = try? Data(contentsOf: URL(fileURLWithPath: args[index + 1])),
              let manifest = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        return manifest
    }
}

extension AppStore {
    func writeQAReport() {
        guard let qa else { return }
        struct Report: Encodable {
            let completedAt: Date
            let requestedModel: String
            let quality: String
            let size: String
            let budgetUSD: Double
            let calculatedTotalUSD: Double
            let unknownCosts: Int
            let jobs: [EnhancementJob]
            let receipts: [RecoveryReceipt]
            let importIssues: [String]
            let notice: String?
        }
        let report = Report(completedAt: Date(), requestedModel: EnhancementConfiguration.model,
            quality: quality.rawValue, size: "2880x2880", budgetUSD: qa.budgetUSD,
            calculatedTotalUSD: state.jobs.compactMap(\.actualCost).reduce(0, +),
            unknownCosts: state.jobs.filter { $0.status == .uncertain && $0.actualCost == nil }.count,
            jobs: state.jobs, receipts: state.jobs.compactMap { sessionReceipts[$0.id] ?? repository.receipt($0.id) }, importIssues: importIssues, notice: notice)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do { try encoder.encode(report).write(to: URL(fileURLWithPath: qa.resultFile), options: .atomic) }
        catch { notice = "The validation report could not be written: \(error.localizedDescription)" }
    }
}
