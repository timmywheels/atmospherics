import Foundation

/// What's playing, shared from the app to the widget through the app group.
struct NowPlayingSnapshot: Codable, Equatable {
    struct Light: Codable, Equatable {
        var hue: Double
        var chroma: Double
        var volume: Double
    }

    var title: String
    var place: String
    var temperature: String
    var isPlaying: Bool
    var lights: [Light]   // loudest first

    static let appGroup = "group.com.timwheeler.atmospherics"
    private static let key = "nowPlaying"

    static let placeholder = NowPlayingSnapshot(
        title: "Light Rain", place: "Atmospherics", temperature: "", isPlaying: false,
        lights: [.init(hue: 55, chroma: 1, volume: 0.7), .init(hue: 235, chroma: 1, volume: 0.55),
                 .init(hue: 175, chroma: 1, volume: 0.3)])

    static func load() -> NowPlayingSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data) else { return .placeholder }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}
