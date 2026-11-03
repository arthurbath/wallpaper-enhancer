import AppKit
import EnhancerCore
import SwiftUI

struct QueueView: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Images").font(.headline)
                Text("\(store.jobs.count)").foregroundStyle(.secondary)
                Spacer()
                if store.isImporting { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 16).padding(.vertical, 14)
            List(selection: $store.selectedID) {
                ForEach(store.jobs) { job in
                    HStack(spacing: 10) {
                        ThumbnailView(url: store.displayURL(for: job)).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.sourceURL.lastPathComponent).lineLimit(1)
                            HStack(spacing: 5) {
                                if job.status.isActive { ProgressView().controlSize(.mini) }
                                else { Image(systemName: statusSymbol(job)).foregroundStyle(statusColor(job)) }
                                Text(subtitle(job)).lineLimit(1).foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                    }.padding(.vertical, 4).tag(job.id)
                    .contextMenu {
                        if let url = job.outputURL { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                    }
                }
            }.listStyle(.sidebar)
                .onDeleteCommand { store.removeSelected() }
        }
    }
    private func subtitle(_ job: EnhancementJob) -> String {
        if job.status == .completed { return "Saved · \(job.actualCost.map { Pricing.dollars($0) } ?? "Cost unknown")" }
        if job.status != .queued { return job.status.title }
        if job.isDuplicate { return "Repeat · ~\(Pricing.dollars(store.estimatedCost(for: job)))" }
        if !job.metadata.warnings.isEmpty { return "Review warning · ~\(Pricing.dollars(store.estimatedCost(for: job)))" }
        return "Ready · ~\(Pricing.dollars(store.estimatedCost(for: job)))"
    }
    private func statusSymbol(_ job: EnhancementJob) -> String {
        if job.status == .completed { return "checkmark.circle.fill" }
        if [.failed, .uncertain, .readyToSave].contains(job.status) || job.isDuplicate || !job.metadata.warnings.isEmpty { return "exclamationmark.triangle" }
        return "circle"
    }
    private func statusColor(_ job: EnhancementJob) -> Color {
        if job.status == .completed { return .green }
        if [.failed, .uncertain, .readyToSave].contains(job.status) || job.isDuplicate || !job.metadata.warnings.isEmpty { return .orange }
        return .secondary
    }
}

struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.clipShape(RoundedRectangle(cornerRadius: 5))
            .task(id: url) {
                if let cg = try? ImageInspection.orientedImage(url, maxSide: 96) { image = NSImage(cgImage: cg, size: .zero) }
            }
    }
}
