import AppKit
import SwiftUI

@main struct WallpaperEnhancerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup("Wallpaper Enhancer", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 920, minHeight: 680)
                .onAppear {
                    delegate.store = store
                    store.launch()
                }
        }
        .defaultSize(width: 1120, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Images…") { store.chooseImages() }.keyboardShortcut("o")
                Button("Choose Output Folder…") { store.chooseDestination() }.disabled(store.isRunning)
            }
            CommandMenu("Enhancement") {
                Button("Enhance Ready Images…") { store.confirmEnhancement() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(store.readyJobs.isEmpty || store.isRunning || store.isImporting || !store.hasAPIKey)
                Button("Stop After Current") { store.stopRequested = true }.disabled(!store.isRunning)
                Divider()
                Button("Clear Finished Images") { store.clearFinished() }.disabled(store.isRunning)
            }
        }
        Settings { SettingsView(store: store) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) { store?.endSession() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "An Image Is Being Processed"
        alert.informativeText = "Let the current image finish saving before quitting. Interrupting an API request can still use credits. The ordinary queue clears when the app closes, while unsaved returned results remain recoverable."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Finish Current and Quit")
        if alert.runModal() == .alertSecondButtonReturn {
            store.stopRequested = true
            store.quitWhenFinished = true
            return .terminateLater
        }
        return .terminateCancel
    }
}
