import SwiftUI

/// Atmospherics for the Mac: one window with the halo, Teleport, Layers and the Library, and a
/// menu bar control to play, travel and set a timer without it. The sound keeps playing when the
/// window is closed.
@main
struct AtmosphericsMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var mixer: Mixer
    @State private var navigation = MacNavigation()
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    init() {
        let mixer = Mixer()
        _mixer = State(initialValue: mixer)
        AppDelegate.mixer = mixer
        // Follow the weather for as long as the app runs, with or without the window open.
        Task { @MainActor in
            while !Task.isCancelled {
                await mixer.refreshWeather()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    var body: some Scene {
        Window("Atmospherics", id: MacNavigation.mainWindow) {
            MacWindow()
                .environment(mixer)
                .environment(navigation)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 480, height: 760)
        .windowResizability(.contentMinSize)
        .commands { MacCommands(mixer: mixer, navigation: navigation) }

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarPanel()
                .environment(mixer)
                .environment(navigation)
        } label: {
            MenuBarIcon()
                .environment(mixer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettings()
        }

        #if DEBUG
        // The menu bar panel in a window, to look at while working on it (launch with -previewPanel).
        Window("Menu Bar Panel", id: "panelPreview") {
            MenuBarPanel()
                .environment(mixer)
                .environment(navigation)
        }
        .windowResizability(.contentSize)
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var mixer: Mixer?

    /// Closing the window doesn't stop the sound: it keeps playing, with the menu bar to control it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // After the Mac sleeps, the weather may be hours old.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { _ in
            Task { @MainActor in await AppDelegate.mixer?.refreshWeather() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Skipped if the weather is fresh.
        Task { @MainActor in await Self.mixer?.refreshWeather() }
    }

    /// Right-click the Dock icon to play, pause or travel without opening the window.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let mixer = Self.mixer else { return nil }
        let menu = NSMenu()
        menu.addItem(ActionItem(mixer.isPlaying ? "Pause" : "Play") { mixer.togglePlayback() })
        menu.addItem(ActionItem("Travel Somewhere New") { mixer.requestTravel(forward: true) })
        if mixer.previous != nil {
            menu.addItem(ActionItem("Go Back") { mixer.requestTravel(forward: false) })
        }
        return menu
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}

/// Where the window is: four parts, named along the top.
@Observable
final class MacNavigation {
    static let mainWindow = "main"

    enum Tab: String, CaseIterable, Identifiable {
        case listen = "Listen", teleport = "Teleport", layers = "Layers", library = "Library"

        var id: Self { self }
        var key: KeyEquivalent { KeyEquivalent(Character("\(Self.allCases.firstIndex(of: self)! + 1)")) }
    }

    var tab: Tab = .listen
    /// Set to ask the window for the save prompt (from the menu bar or the Playback menu).
    var saving = false
    /// Set to ask the window to confirm a reset (from Layers or the Playback menu).
    var resetting = false
}
