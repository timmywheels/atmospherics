import SwiftUI

/// The menus: the window's parts under View, and a Playback menu with everything the iPhone app
/// does with gestures (travel, weather, time of day, the sleep timer, saving).
struct MacCommands: Commands {
    let mixer: Mixer
    let navigation: MacNavigation

    var body: some Commands {
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
        Button("Where To…") {
            openWindow(id: MacNavigation.mainWindow)
            navigation.choosing = true
        }
        .keyboardShortcut("k")
        Divider()
        ForEach(MacNavigation.Tab.allCases) { tab in
            Button(tab.rawValue) {
                navigation.tab = tab
                openWindow(id: MacNavigation.mainWindow)
            }
            .keyboardShortcut(tab.key, modifiers: .command)
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
        Divider()
        Button("Travel Somewhere New") { mixer.requestTravel(forward: true) }
            .keyboardShortcut(.rightArrow, modifiers: .command)
        Button("Go Back") { mixer.requestTravel(forward: false) }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(mixer.previous == nil)
        Button(mixer.activePreset != nil ? "Back to \(mixer.presetReturnName)" : "Go Home") {
            mixer.activePreset != nil ? mixer.leavePreset() : mixer.goHome()
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])
        .disabled(mixer.activePreset == nil && mixer.mode == .match)
        Divider()
        Picker("Sleep Timer", selection: Binding(get: { mixer.timer }, set: { mixer.setTimer($0) })) {
            ForEach(Mixer.Timer.allCases, id: \.self) { t in
                Text(t == .off ? "No Timer" : "Stop After \(t.label)").tag(t)
            }
        }
        if mixer.mode == .atmosphere, mixer.activePreset == nil, let a = mixer.atmosphere {
            // An atmosphere's own weather and time, from those that suit it.
            Picker("Weather", selection: Binding(get: { a.sky }, set: { mixer.setAtmosphereSky($0) })) {
                ForEach(a.setting.info.skies, id: \.self) { Text($0.name).tag($0) }
            }
            Picker("Time of Day", selection: Binding(get: { a.time }, set: { mixer.setAtmosphereTime($0) })) {
                ForEach(a.setting.info.times, id: \.self) { Text($0.name).tag($0) }
            }
        } else {
            Picker("Weather", selection: Binding(get: { mixer.skyOverride }, set: { mixer.setSky($0) })) {
                ForEach(Mixer.SkyOverride.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Time of Day", selection: Binding(get: { mixer.timeOverride }, set: { mixer.setTime($0) })) {
                ForEach(Mixer.TimeOverride.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Button("Back to Live Weather") { withAnimation(.smooth) { mixer.clearOverrides() } }
                .disabled(!mixer.isImagining)
        }
        Divider()
        Button("Save This Mix…") {
            openWindow(id: MacNavigation.mainWindow)
            navigation.saving = true
        }
        .keyboardShortcut("s")
        Button("Reset \(mixer.currentPlaceName.capitalizedFirst) to Default") {
            withAnimation(.smooth) { mixer.resetCurrentPlace() }
        }
        .disabled(!mixer.currentPlaceIsTweaked)
    }
}

/// Settings: the temperature unit, and whether to keep a control in the menu bar.
struct MacSettings: View {
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
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
        .preferredColorScheme(.dark)
    }
}
