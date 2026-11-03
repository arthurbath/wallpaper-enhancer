import AppKit
import EnhancerCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var dropTargeted = false
    var body: some View {
        VStack(spacing: 0) {
            if !store.hasAPIKey {
                HStack(spacing: 12) {
                    Image(systemName: "key").foregroundStyle(.secondary)
                    Text("Add your OpenAI API key in Settings to enhance images.").font(.callout)
                    Spacer()
                    SettingsLink { Text("Add API Key…") }
                }.padding(12).background(.quaternary.opacity(0.35))
                Divider()
            }
            if let notice = store.notice {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(notice).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss")
                }.padding(12).background(.orange.opacity(0.09))
                Divider()
            }
            if store.jobs.isEmpty {
                EmptyQueueView(quality: store.quality, chooseImages: store.chooseImages)
            } else {
                HSplitView {
                    QueueView(store: store).frame(minWidth: 260, idealWidth: 290, maxWidth: 360)
                    Group {
                        if let job = store.selected { DetailView(store: store, job: job) }
                        else { ContentUnavailableView("Select an Image", systemImage: "photo", description: Text("Review its framing, estimate, and enhancement result.")) }
                    }.frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            DestinationView(store: store)
            Divider()
            BatchFooterView(store: store)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else { return }
                    Task { @MainActor in store.addURLs([url]) }
                }
            }
            return !providers.isEmpty
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: store.chooseImages) { Label("Add Images", systemImage: "plus") }.help("Add Images (⌘O)")
            }
            ToolbarItem {
                Button(action: store.clearFinished) { Label("Clear Finished", systemImage: "checkmark.circle") }
                    .disabled(store.isRunning || !store.jobs.contains { $0.status == .completed })
            }
        }
        .sheet(isPresented: $store.showingImportIssues) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Some Images Could Not Be Added").font(.title2.bold())
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(store.importIssues.enumerated()), id: \.offset) { _, issue in Text(issue).textSelection(.enabled) }
                    }
                }.frame(maxHeight: 280)
                HStack { Spacer(); Button("Done") { store.showingImportIssues = false; store.importIssues = [] }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 560)
        }
    }
}

private struct EmptyQueueView: View {
    let quality: EnhancementQuality
    let chooseImages: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 64, weight: .light)).foregroundStyle(.teal)
                Image(systemName: "sparkles").font(.system(size: 24)).foregroundStyle(.teal).offset(x: 16, y: -10)
            }.padding(.bottom, 8)
            VStack(spacing: 8) {
                Text("Give Your Wallpapers More Detail").font(.system(size: 25, weight: .semibold))
                Text("Drop images or a folder here, or choose images to begin.")
                    .font(.body).foregroundStyle(.secondary)
            }
            Button("Choose Images…", action: chooseImages).buttonStyle(.borderedProminent).controlSize(.large)
            Text("Square PNG · 2,880 × 2,880 · \(quality.title) quality")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            Text("Review the estimated cost before enhancing.")
                .font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

private struct DestinationView: View {
    @Bindable var store: AppStore
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text("Save to").foregroundStyle(.secondary)
            Text(store.destination.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: 16)
            Button("Choose…", action: store.chooseDestination).disabled(store.isRunning)
            Button { NSWorkspace.shared.open(store.destination) } label: { Image(systemName: "arrow.up.forward.square") }
                .help("Open Output Folder")
        }.font(.callout).padding(.horizontal, 20).padding(.vertical, 12)
    }
}

private struct BatchFooterView: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                QualityPicker(store: store).frame(width: 250)
                Text("~\(store.batchPlan.perImageEstimate) USD per image")
                    .font(.callout).monospacedDigit()
                Spacer()
                Text("2,880 × 2,880 PNG").font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    if store.isRunning {
                        Text("\(store.batchFinishedCount) of \(store.batchTotalCount) images finished").font(.headline)
                        ProgressView(value: Double(store.batchFinishedCount), total: Double(max(1, store.batchTotalCount))).frame(width: 220)
                    } else if store.isImporting {
                        HStack { ProgressView().controlSize(.small); Text("Reading images…") }
                    } else {
                        Text("\(store.readyJobs.count) ready · Estimated batch total: \(Pricing.dollars(store.estimatedTotal)) USD").font(.headline).monospacedDigit()
                    }
                    Text("Includes image input, prompt, and image output costs. Actual usage may vary.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !store.lastBatchJobIDs.isEmpty {
                        Text("Latest batch: \(Pricing.dollars(store.lastBatchCost)) in usage-based API costs\(store.lastBatchUnknownCosts > 0 ? " · Some costs unknown" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if store.isRunning {
                    Button(store.stopRequested ? "Stopping After Current…" : "Stop After Current") { store.stopRequested = true }
                        .disabled(store.stopRequested)
                } else {
                    Button { store.confirmEnhancement() } label: { Label("Enhance \(store.readyJobs.count > 0 ? "\(store.readyJobs.count)" : "Images")", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(store.readyJobs.isEmpty || store.isImporting || !store.hasAPIKey)
                        .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }.padding(20)
    }
}

struct QualityPicker: View {
    @Bindable var store: AppStore
    var body: some View {
        Picker("Quality", selection: $store.quality) {
            ForEach(EnhancementQuality.allCases, id: \.self) { quality in
                Text(quality.selectionTitle).tag(quality)
            }
        }.disabled(store.isRunning)
            .help("Choose the quality for the next batch. Maximum is the highest available setting.")
    }
}
