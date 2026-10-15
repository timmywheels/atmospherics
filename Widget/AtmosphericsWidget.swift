import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct AtmosphericsWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        SoundscapeLiveActivity()
    }
}

// MARK: Home screen widget

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot
    let phase: Double
}

/// Widgets can't animate continuously, so the timeline holds a snapshot every few minutes,
/// each with the lights nudged slightly; iOS cross-fades between them, so the halo drifts.
struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: .placeholder, phase: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(NowPlayingEntry(date: .now, snapshot: .load(), phase: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let snapshot = NowPlayingSnapshot.load()
        let entries = (0..<12).map { i in
            NowPlayingEntry(date: .now.addingTimeInterval(Double(i) * 5 * 60), snapshot: snapshot, phase: Double(i) * 0.9)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowPlaying", provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .foregroundStyle(Color(hex: 0xeceef2))
                .environment(\.colorScheme, .dark)
                .containerBackground(Color(hex: 0x0c0e13), for: .widget)
        }
        .configurationDisplayName("Atmospherics")
        .description("What's playing, with play and pause.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .systemMedium:
            HStack(spacing: 14) {
                HaloArt(lights: s.lights, phase: entry.phase)
                    .frame(width: 120)
                    .contentTransition(.opacity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(placeLine(s))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(s.title)
                        .font(.system(size: 22, weight: .light))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    PlayButton(isPlaying: s.isPlaying, size: 38)
                }
                Spacer(minLength: 0)
            }
        default:
            ZStack(alignment: .bottomLeading) {
                HaloArt(lights: s.lights, phase: entry.phase)
                    .padding(-10)
                    .contentTransition(.opacity)
                // Shade the bottom so the title reads over the glow.
                LinearGradient(colors: [.clear, Color(hex: 0x0c0e13).opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    .padding(-16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title)
                        .font(.system(size: 15, weight: .light))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(placeLine(s))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                PlayButton(isPlaying: s.isPlaying, size: 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }

    private func placeLine(_ s: NowPlayingSnapshot) -> String {
        s.temperature.isEmpty ? s.place.uppercased() : "\(s.place.uppercased()) \(s.temperature)"
    }
}

struct PlayButton: View {
    let isPlaying: Bool
    let size: CGFloat

    var body: some View {
        Button(intent: PlayPauseIntent(play: !isPlaying)) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0c0e13))
                .frame(width: size, height: size)
                .background(Circle().fill(Color(hex: 0xeceef2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

// MARK: Live Activity

struct SoundscapeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SoundscapeActivity.self) { context in
            HStack(spacing: 14) {
                Breathing(hues: context.state.hues)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.place.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(context.state.title)
                        .font(.system(size: 20, weight: .light))
                        .lineLimit(1)
                }
                Spacer()
                PlayButton(isPlaying: context.state.isPlaying, size: 40)
            }
            .padding(16)
            .foregroundStyle(Color(hex: 0xeceef2))
            .environment(\.colorScheme, .dark)
            .activityBackgroundTint(Color(hex: 0x0c0e13))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Breathing(hues: context.state.hues).frame(width: 44, height: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.title).font(.system(size: 17, weight: .light)).lineLimit(1)
                        Text(context.state.place.uppercased())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlayButton(isPlaying: context.state.isPlaying, size: 36)
                }
            } compactLeading: {
                Breathing(hues: context.state.hues).frame(width: 18, height: 18)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(Color.oklch(0.8, 0.12, context.state.hues.first ?? 200))
            } minimal: {
                Breathing(hues: context.state.hues).frame(width: 18, height: 18)
            }
            .keylineTint(Color.oklch(0.8, 0.12, context.state.hues.first ?? 200))
        }
    }
}

/// A small glow of the mix's colors. Live Activities can't run custom animation loops, so it
/// uses a repeating symbol-style pulse the system is allowed to play.
struct Breathing: View {
    let hues: [Double]

    var body: some View {
        HaloArt(lights: hues.prefix(3).enumerated().map { i, h in
            .init(hue: h, chroma: 1, volume: [0.75, 0.5, 0.35][i])
        })
        .overlay {
            Image(systemName: "circle.fill")
                .resizable()
                .foregroundStyle(.white.opacity(0.001))
                .symbolEffect(.pulse, options: .repeating)
        }
    }
}
