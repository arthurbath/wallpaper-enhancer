import AppKit
import EnhancerCore
import SwiftUI

struct DetailView: View {
    @Bindable var store: AppStore
    let job: EnhancementJob
    var body: some View {
        GeometryReader { viewport in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(job.sourceURL.deletingPathExtension().lastPathComponent).font(.title3.weight(.semibold)).lineLimit(2)
                        Text("\(job.metadata.width.formatted()) × \(job.metadata.height.formatted()) → 2,880 × 2,880")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(job.actualCost.map { Pricing.dollars($0) } ?? "~\(Pricing.dollars(store.estimatedCost(for: job)))").font(.title2.weight(.semibold)).monospacedDigit()
                        Text(job.actualCost == nil ? "Estimated API cost" : "Usage-based API cost").font(.caption).foregroundStyle(.secondary)
                        Text("\(store.quality(for: job).title) quality").font(.caption).foregroundStyle(.secondary)
                    }
                }
                SquarePreview(url: store.displayURL(for: job), geometry: job.metadata.geometry,
                              isGuide: job.outputURL == nil && !store.repository.hasReturnedImage(job.id))
                    .frame(maxWidth: min(560, max(240, min(viewport.size.width - 40, viewport.size.height - 230)))).frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    Image(systemName: job.status == .completed ? "checkmark.circle.fill" : "viewfinder")
                        .foregroundStyle(job.status == .completed ? .green : .secondary)
                    Text(job.status == .completed ? "Verified square PNG at \(store.quality(for: job).title.lowercased()) quality" : (job.status == .readyToSave ? "Returned image ready to save" : job.metadata.geometry.summary))
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                if job.status.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("\(job.status.title)…")
                            Spacer()
                            if let start = job.startedAt {
                                let seconds = max(0, Int(timeline.date.timeIntervalSince(start)))
                                Text(String(format: "%d:%02d elapsed", seconds / 60, seconds % 60)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }.font(.callout)
                    }
                }
                if let message = job.message {
                    warning(message)
                }
                if job.isDuplicate, job.status == .queued {
                    warning("This image matches another input or an image already enhanced. Repeating it will use additional credits.")
                }
                ForEach(job.metadata.warnings, id: \.self) { warning($0) }
                HStack(spacing: 12) {
                    if job.status == .readyToSave {
                        Button("Save Again") { store.saveAgain(job) }.buttonStyle(.borderedProminent).disabled(store.isRunning)
                        Text("No additional generation charge").font(.caption).foregroundStyle(.secondary)
                    } else if [.failed, .uncertain].contains(job.status) {
                        Button("Enhance Again…") { confirmRetry() }.disabled(store.isRunning)
                        if FileManager.default.fileExists(atPath: store.repository.imageURL(job.id).path) {
                            Button("Show Returned File") { NSWorkspace.shared.activateFileViewerSelecting([store.repository.imageURL(job.id)]) }
                        }
                    } else if let output = job.outputURL {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                        Button("Enhance Again…") { confirmRetry() }.disabled(store.isRunning)
                    }
                }
            }.padding(20)
        }
        }
    }
    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(text).font(.callout).textSelection(.enabled)
            Spacer(minLength: 0)
        }.padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
    private func confirmRetry() {
        let alert = NSAlert()
        alert.messageText = "Add a Fresh Enhancement?"
        let estimate = Pricing.estimate(geometry: job.metadata.geometry, quality: store.quality)
        alert.informativeText = "A fresh repaint at \(store.quality.title.lowercased()) quality will be added to the queue with an estimated API cost of \(Pricing.dollars(estimate)) USD. It will start only after you choose Enhance and confirm the batch estimate. Any previous request may already have used credits."
        alert.addButton(withTitle: "Add Enhancement")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.enhanceAgain(job) }
    }
}

private struct SquarePreview: View {
    let url: URL
    let geometry: SquareGeometry
    let isGuide: Bool
    @State private var image: NSImage?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(.quaternary.opacity(0.5))
                if let image { Image(nsImage: image).resizable().scaledToFit() }
                else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) }
                if isGuide, !geometry.isSquare {
                    let band = proxy.size.width * geometry.extensionFraction / 2
                    if geometry.width > geometry.height {
                        VStack(spacing: 0) { expansion.frame(height: band); Spacer(minLength: 0); expansion.frame(height: band) }
                    } else {
                        HStack(spacing: 0) { expansion.frame(width: band); Spacer(minLength: 0); expansion.frame(width: band) }
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
        }.aspectRatio(1, contentMode: .fit)
            .task(id: url) { image = NSImage(contentsOf: url) }
    }
    private var expansion: some View {
        ZStack {
            Rectangle().fill(Color.accentColor.opacity(0.10))
            ViewThatFits {
                Label("AI expansion", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary).padding(5)
                Image(systemName: "sparkles").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
