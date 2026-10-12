import ActivityKit

/// The Live Activity shown on the lock screen and in the Dynamic Island while playing.
struct SoundscapeActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var place: String
        var isPlaying: Bool
        var hues: [Double]
    }
}
