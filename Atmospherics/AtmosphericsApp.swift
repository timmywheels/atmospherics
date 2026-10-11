import SwiftUI

@main
struct AtmosphericsApp: App {
    @State private var mixer = Mixer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(mixer)
                .task {
                    // Keep following the weather while the app runs, including in the background while playing.
                    while !Task.isCancelled {
                        await mixer.refreshWeather()
                        try? await Task.sleep(for: .seconds(30 * 60))
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await mixer.refreshWeather() } }
        }
    }
}
