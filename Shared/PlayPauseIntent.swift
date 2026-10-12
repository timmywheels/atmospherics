import AppIntents

/// Play/pause from the widget or Live Activity. Runs in the app's process (audio intents do),
/// where the app registers a handler at launch.
struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or pause"
    static let description = IntentDescription("Plays or pauses the current Atmospherics soundscape.")

    @MainActor static var handler: (() -> Void)?

    func perform() async throws -> some IntentResult {
        await MainActor.run { Self.handler?() }
        return .result()
    }
}
