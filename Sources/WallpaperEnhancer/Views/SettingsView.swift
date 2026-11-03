import AppKit
import EnhancerCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore
    @State private var keyDraft = ""
    @State private var keyMessage: String?
    @State private var keyError = false

    var body: some View {
        Form {
            Section("OpenAI API Key") {
                Label(store.hasAPIKey ? "API key saved on this Mac" : "No API key saved",
                      systemImage: store.hasAPIKey ? "checkmark.shield" : "key")
                SecureField(store.hasAPIKey ? "Enter a replacement API key" : "Paste your OpenAI API key", text: $keyDraft)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .disabled(store.isRunning)
                    .accessibilityLabel("OpenAI API Key")
                    .onSubmit { saveKey() }
                HStack {
                    Button("Save Key", action: saveKey).disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isRunning)
                    Button("Remove Key") {
                        do {
                            try store.removeAPIKey()
                            keyDraft = ""
                            keyMessage = "API key removed."
                            keyError = false
                        } catch { showError(error) }
                    }.disabled(!store.hasAPIKey || store.isRunning)
                    Spacer()
                    Link("Get an API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                }
                if let message = keyMessage ?? store.credentialIssue {
                    Text(message).font(.callout).foregroundStyle(keyError || store.credentialIssue != nil ? Color.orange : .secondary)
                }
                Text("Your key is stored securely in this Mac's Keychain and sent only to OpenAI when you enhance images. Usage is billed to your OpenAI API account. Saving a key does not make an API request.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Enhancement") {
                LabeledContent("Output", value: "2,880 × 2,880 PNG")
                QualityPicker(store: store)
                LabeledContent("Estimated Cost per Image", value: "~\(store.batchPlan.perImageEstimate) USD")
                Text("Maximum is the highest available quality. The main window updates the batch estimate before you confirm enhancement.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Model", value: EnhancementConfiguration.model)
                Text("Your API project must have access to this image model. Nonsquare images use balanced cropping and AI expansion around the original center.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Destination") {
                Text(store.destination.path).textSelection(.enabled)
                Button("Choose Output Folder…", action: store.chooseDestination).disabled(store.isRunning)
            }
            Section("Credits and Pricing") {
                Text("Estimates and usage-based costs use standard API rates. Account discounts, credits, and taxes can affect your bill. Importing images does not start a paid request.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Pricing checked", value: EnhancementConfiguration.pricingDate)
                Link("OpenAI API Pricing", destination: URL(string: EnhancementConfiguration.pricingURL)!)
            }
        }.formStyle(.grouped).padding().frame(width: 580, height: 800)
            .onAppear { store.refreshCredentialStatus() }
            .onDisappear { keyDraft = "" }
    }
    private func saveKey() {
        guard !store.isRunning else { return }
        do {
            try store.saveAPIKey(keyDraft)
            keyDraft = ""
            keyMessage = "API key saved securely. It will be used for the next batch."
            keyError = false
        } catch { showError(error) }
    }
    private func showError(_ error: Error) {
        keyError = true
        keyMessage = SafeErrorText.redact(error.localizedDescription, credential: keyDraft)
    }
}
