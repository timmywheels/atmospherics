import Combine
import Sparkle
import SwiftUI

/// Updates for the copy downloaded from GitHub, by Sparkle (the open-source updater most Mac apps
/// outside the App Store use): once a day it reads the feed attached to the latest release, and
/// when there's a newer version it offers to install it and relaunch. Builds from Xcode leave it
/// off, so a development copy never offers to replace itself with a release.
@MainActor
final class Updates: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false

    init() {
        #if DEBUG
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        #else
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        #endif
    }

    func check() { controller.checkForUpdates(nil) }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }
}

/// "Check for Updates…" in the app menu, available while Sparkle can check.
struct CheckForUpdatesButton: View {
    @ObservedObject var updates: Updates

    var body: some View {
        Button("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") { updates.check() }
            .disabled(!updates.canCheck)
    }
}
