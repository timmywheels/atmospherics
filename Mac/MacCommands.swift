import SwiftUI

/// The menus: the window's parts under View, and a Playback menu with everything the iPhone app
/// does with gestures (travel, weather, time of day, the sleep timer, saving).
struct MacCommands: Commands {
    let mixer: Mixer
    let navigation: MacNavigation
    let updates: Updates

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(updates: updates)
        }

        // One window, so no New Window.
        CommandGroup(replacing: .newItem) {}

        CommandGroup(before: .toolbar) {
            TabCommands(navigation: navigation)
        }

        CommandMenu("Playback") {
            PlaybackCommands(mixer: mixer, navigation: navigation)
        }
    }
}

/// Menu items as views, so their titles and checkmarks follow the mixer as it changes.
private struct TabCommands: View {
    let navigation: MacNavigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(MacNavigation.Tab.allCases) { tab in
            Button(tab.rawValue) {
                navigation.tab = tab
                openWindow(id: MacNavigation.mainWindow)
            }
            // Teleport's ⌘K is in the Playback menu.
            .keyboardShortcut(tab == .teleport ? nil : KeyboardShortcut(tab.key, modifiers: .command))
        }
        Divider()
    }
}

private struct PlaybackCommands: View {
    let mixer: Mixer
    let navigation: MacNavigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(mixer.isPlaying ? "Pause" : "Play") { mixer.togglePlayback() }
            .keyboardShortcut(.space, modifiers: [])
        // The app's own volume, apart from the Mac's, as in Music.
        Button("Louder") { mixer.volume = min(1, mixer.volume + 0.1) }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(mixer.volume >= 1)
        Button("Softer") { mixer.volume = max(0, mixer.volume - 0.1) }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(mixer.volume <= 0)
        Divider()
        Button("Travel Somewhere New") { mixer.requestTravel(forward: true) }
            .keyboardShortcut(.rightArrow, modifiers: .command)
        Button("Go Back") { mixer.requestTravel(forward: false) }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(mixer.previous == nil)
        Menu("Go To") {
            ForEach(Array(Mixer.Lens.allCases.enumerated()), id: \.element) { i, lens in
                Button(lens.rawValue) { mixer.choose(lens) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
            }
        }
        Button("Where You Are") { withAnimation(.smooth(duration: 0.35)) { mixer.goHome() } }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(!mixer.awayFromPlaces && mixer.mode == .match)
        if mixer.awayFromPlaces {
            Button("Back to \(mixer.lastPlaceName)") { mixer.backToPlace() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }
        Button("Teleport…") {
            navigation.tab = .teleport
            openWindow(id: MacNavigation.mainWindow)
        }
        .keyboardShortcut("k")
        Divider()
        Picker("Sleep Timer", selection: Binding(get: { mixer.timer }, set: { mixer.setTimer($0) })) {
            ForEach(Mixer.Timer.allCases, id: \.self) { t in
                Text(t == .off ? "No Timer" : "Stop After \(t.label)").tag(t)
            }
        }
        if mixer.mode == .atmosphere, mixer.activePreset == nil, let a = mixer.atmosphere {
            // A scene's other skies and times: each another scene, to go to. (A real place is
            // always its real weather.)
            Picker("Other Skies", selection: Binding(get: { a.sky }, set: { mixer.setAtmosphereSky($0) })) {
                ForEach(a.setting.info.skies, id: \.self) { Text($0.name).tag($0) }
            }
            Picker("Time of Day", selection: Binding(get: { a.time }, set: { mixer.setAtmosphereTime($0) })) {
                ForEach(a.setting.info.times, id: \.self) { Text($0.name).tag($0) }
            }
        }
        Divider()
        Button("Save This Mix…") {
            openWindow(id: MacNavigation.mainWindow)
            navigation.saving = true
        }
        .keyboardShortcut("s")
        Button(mixer.mode == .atmosphere ? "Reset Scene to Default…" : "Reset \(mixer.currentPlaceName.capitalizedFirst) to Default…") {
            openWindow(id: MacNavigation.mainWindow)
            navigation.resetting = true
        }
        .disabled(!mixer.currentPlaceIsTweaked)
    }
}

/// Settings: the temperature unit, and whether to keep a control in the menu bar.
struct MacSettings: View {
    @EnvironmentObject private var updates: Updates
    @AppStorage("tempUnit") private var tempUnit = "auto"
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some View {
        Form {
            Picker("Temperature", selection: $tempUnit) {
                Text("Automatic").tag("auto")
                Text("Fahrenheit (°F)").tag("f")
                Text("Celsius (°C)").tag("c")
            }
            Toggle("Show in the menu bar", isOn: $showInMenuBar)
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updates.checksAutomatically }, set: { updates.checksAutomatically = $0 }))
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
        .preferredColorScheme(.dark)
    }
}
