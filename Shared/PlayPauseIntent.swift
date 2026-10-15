import AppIntents

/// Play/pause from the widget or Live Activity. Runs in the app's process (audio intents do),
/// where the app registers a handler at launch. The button says what it'll do (`play`), so a
/// tap does what its icon shows even if what's playing changed since it was drawn; without it,
/// it toggles.
struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or pause"
    static let description = IntentDescription("Plays or pauses the current Atmospherics soundscape.")

    @Parameter(title: "Play") var play: Bool?

    init() {}
    init(play: Bool) { self.play = play }

    @MainActor static var handler: ((Bool?) -> Void)?

    func perform() async throws -> some IntentResult {
        let play = play
        await MainActor.run { Self.handler?(play) }
        return .result()
    }
}
