// Prints what each place sounds like: right now (live weather), and across seasons and hours.
// Build and run from the repo root:
//   swiftc -parse-as-library -o /tmp/inspect Atmospherics/Sound.swift Atmospherics/Places.swift \
//     Atmospherics/Weather.swift Atmospherics/Ecology.swift Shared/Color+OKLCH.swift design/soundscapes/inspect.swift
//   /tmp/inspect [live|seasons]
import Foundation

@main
struct Inspect {
    static func line(_ name: String, _ c: Conditions, _ place: Place?, _ now: Date) -> String {
        let mix = Soundscape.compose(c, place: place, now: now, playableOnly: false)
            .map { "\($0.0.short) \(Int(($0.1 * 100).rounded()))" }.joined(separator: " · ")
        let pad = name.padding(toLength: 14, withPad: " ", startingAt: 0)
        return "\(pad) \(c.mixName(at: now).padding(toLength: 18, withPad: " ", startingAt: 0)) \(mix)"
    }

    static func main() async {
        let mode = CommandLine.arguments.dropFirst().first ?? "live"
        if mode == "live" {
            let places = Place.all
            guard let all = try? await WeatherService().conditions(for: places) else { print("weather failed"); return }
            for (p, c) in zip(places, all) {
                let t = c.localTime()
                print(line(p.name, c, p, Date()) + "   [\(String(format: "%02d:%02d", t.hour, t.minute)) \(Int(c.temperatureC))°C]")
            }
            return
        }
        // What-ifs: one place across the year and the day.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        func at(_ month: Int, _ hour: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: month, day: 15, hour: hour, minute: 20))!
        }
        let names = CommandLine.arguments.count > 2 ? Array(CommandLine.arguments.dropFirst(2)) : ["Providence", "Waterford", "Tokyo", "Sydney", "Manaus", "Rome"]
        let scenes: [(String, Int, Int, Double, Int, Double)] = [
            // label, month, hour, temp °C, weather code, precip mm
            ("Jan night snow", 1, 2, -6, 73, 0),
            ("Apr dawn", 4, 6, 8, 1, 0),
            ("Apr night", 4, 22, 9, 0, 0),
            ("Jul afternoon", 7, 15, 30, 1, 0),
            ("Jul night", 7, 23, 21, 0, 0),
            ("Aug night rain", 8, 23, 20, 61, 0.4),
            ("Oct morning", 10, 9, 11, 3, 0),
            ("Oct mild night", 10, 23, 16, 0, 0),
            ("Oct cold night", 10, 23, 7, 0, 0),
            ("Oct fog dawn", 10, 7, 12, 45, 0),
        ]
        for name in names {
            guard let p = Place.all.first(where: { $0.name == name }) else { continue }
            print("\n\(p.name) (\(p.climate?.rawValue ?? "derived"))")
            for (label, month, hour, temp, code, precip) in scenes {
                // Southern places: the same calendar month, so seasons flip.
                let c = Conditions(place: p.name, temperatureC: temp, precipitationMM: precip, windKMH: 10,
                                   pressureHPA: 1013, code: code, isDay: (7...18).contains(hour),
                                   latitude: p.latitude, utcOffset: 0, sunrise: 6 * 60 + 30, sunset: 18 * 60 + 30,
                                   snowDepth: code == 73 ? 0.2 : 0)
                print("  " + line(label, c, p, at(month, hour)))
            }
        }
    }
}
