import CoreLocation
import Foundation

/// Current conditions at one place.
struct Conditions: Equatable {
    var place: String
    var temperatureC: Double
    var precipitationMM: Double     // per hour
    var windKMH: Double             // sustained, or gusts if stronger
    var pressureHPA: Double
    var code: Int                   // WMO weather code
    var isDay: Bool

    var isThunder: Bool { (95...99).contains(code) }
    var isSnow: Bool { (71...77).contains(code) || code == 85 || code == 86 }
    var isFog: Bool { code == 45 || code == 48 }
    var isRaining: Bool { precipitationMM > 0.05 || (51...67).contains(code) || (80...82).contains(code) || isThunder }

    var temperature: String {
        Measurement(value: temperatureC, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// A short name for the mix this weather makes, e.g. "Light Rain".
    var mixName: String {
        if isThunder { return "Thunderstorm" }
        if isSnow { return "Snowfall" }
        if isRaining { return precipitationMM > 2.5 ? "Heavy Rain" : "Light Rain" }
        if isFog { return "Fog Bank" }
        if windKMH > 30 { return isDay ? "Gusty Day" : "Windy Night" }
        if code >= 2 { return isDay ? "Overcast" : "Cloudy Night" }
        return isDay ? "Clear Sky" : "Clear Night"
    }

    /// What the sound is following, e.g. "the rain".
    var subject: String {
        if isThunder { return "the storm" }
        if isSnow { return "the snow" }
        if isRaining { return "the rain" }
        if isFog { return "the fog" }
        if windKMH > 30 { return "the wind" }
        return isDay ? "the open sky" : "a quiet night"
    }
}

enum WeatherError: LocalizedError {
    case badResponse
    var errorDescription: String? { "The weather service didn't answer." }
}

/// Fetches current conditions from Open-Meteo (free, no API key, worldwide).
struct WeatherService {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    func conditions(at coordinate: CLLocationCoordinate2D, place: String) async throws -> Conditions {
        var result = try await openMeteo([(coordinate.latitude, coordinate.longitude)])[0]
        result.place = place
        return result
    }

    /// Conditions at each place, in order, from one request.
    func conditions(for places: [Place]) async throws -> [Conditions] {
        var all = try await openMeteo(places.map { ($0.latitude, $0.longitude) })
        for i in all.indices { all[i].place = places[i].name }
        return all
    }

    // MARK: Open-Meteo

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let precipitation: Double
            let weather_code: Int
            let wind_speed_10m: Double
            let wind_gusts_10m: Double?
            let pressure_msl: Double
            let is_day: Int
        }
        let current: Current
    }

    private func openMeteo(_ points: [(Double, Double)]) async throws -> [Conditions] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: points.map { String(format: "%.2f", $0.0) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: points.map { String(format: "%.2f", $0.1) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "temperature_2m,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,pressure_msl,is_day"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.badResponse }
        // One point returns an object; several return an array.
        let decoded: [OpenMeteoResponse] = points.count == 1
            ? [try JSONDecoder().decode(OpenMeteoResponse.self, from: data)]
            : try JSONDecoder().decode([OpenMeteoResponse].self, from: data)
        return decoded.map { r in
            let c = r.current
            return Conditions(place: "", temperatureC: c.temperature_2m, precipitationMM: c.precipitation,
                              windKMH: max(c.wind_speed_10m, (c.wind_gusts_10m ?? 0) * 0.7),
                              pressureHPA: c.pressure_msl, code: c.weather_code, isDay: c.is_day == 1)
        }
    }
}

/// Turns conditions into a field of sounds.
enum WeatherMix {
    static func orbs(for c: Conditions, place: Place? = nil) -> [(SoundKind, Double)] {
        var mix: [(SoundKind, Double)] = []

        // A quiet noise floor under everything: deeper when pressure is low, brighter in fog.
        // It's a floor, not the sound. At a place, the place leads and the floor nearly vanishes.
        let lowPressure = c.pressureHPA < 1005
        let floor = place == nil ? 1.0 : 0.45
        if c.isFog {
            mix.append((.white, 0.15 * floor))
            mix.append((.brown, 0.25 * floor))
        } else if c.isDay && !c.isRaining && !lowPressure {
            mix.append((.pink, 0.25 * floor))
        } else {
            mix.append((.brown, (lowPressure || c.isSnow ? 0.35 : 0.28) * floor))
        }

        if c.isRaining && !c.isSnow {
            mix.append((.rain, min(0.9, 0.4 + c.precipitationMM / 4)))
        }
        if c.isThunder {
            mix.append((.thunder, 0.4))
            mix.append((.lightning, 0.45))
        }
        let wind = min(0.8, max(0, (c.windKMH - 6) / 40))
        if wind > 0.08 {
            mix.append((.wind, c.isSnow ? wind * 0.6 : wind))
        }
        if c.isDay && !c.isRaining && c.code <= 3 {
            mix.append((.birds, 0.2))
        }
        // Warm, dry nights get crickets; hot days get cicadas.
        if !c.isDay && !c.isRaining && c.temperatureC >= 16 {
            mix.append((.crickets, 0.3))
        }
        if c.isDay && !c.isRaining && c.temperatureC >= 25 {
            mix.append((.cicadas, 0.25))
        }
        for (kind, signatureLevel) in place?.signature ?? [] {
            if kind == .fire && c.temperatureC >= 12 { continue }
            // The place's own sounds lead the mix.
            let level = min(0.9, signatureLevel * 1.5) * weatherFactor(for: kind, in: c)
            if level < 0.06 { continue }
            if let i = mix.firstIndex(where: { $0.0 == kind }) {
                mix[i].1 = max(mix[i].1, level)
            } else {
                mix.append((kind, level))
            }
        }
        // In the tropics, rain lands on tin roofs.
        if let place, abs(place.latitude) < 23.5, let i = mix.firstIndex(where: { $0.0 == .rain }) {
            mix[i].0 = .tinRoof
        }

        // Creatures keep their hours.
        let offHours: Set<SoundKind> = c.isDay
            ? [.crickets, .frogs, .treeFrogs, .owls, .wolves]
            : [.birds, .cicadas, .jungleBirds, .parrots, .howlers, .canopy, .cafe, .bells]
        mix = mix.filter { !offHours.contains($0.0) }

        // A recording that isn't in the app falls back to the nearest synthesized sound.
        var result: [(SoundKind, Double)] = []
        for (kind, level) in mix {
            guard let k = kind.playable else { continue }
            if let i = result.firstIndex(where: { $0.0 == k }) {
                result[i].1 = max(result[i].1, level)
            } else {
                result.append((k, level))
            }
        }
        return result
    }

    /// How the weather right now changes a place's own sounds.
    static func weatherFactor(for kind: SoundKind, in c: Conditions) -> Double {
        let heavy = c.isThunder || c.precipitationMM > 2.5
        let freezing = c.isSnow || c.temperatureC < 3
        switch kind {
        // Birds and insects shelter from rain, and stop altogether in a downpour or the cold.
        case .birds, .jungleBirds, .parrots, .cicadas, .crickets, .howlers:
            if freezing || heavy { return 0 }
            return c.isRaining ? 0.3 : 1
        // Frogs love rain; cold silences them.
        case .frogs, .treeFrogs:
            if freezing { return 0 }
            return c.isRaining ? 1.4 : 1
        // Wind roughens the sea and stirs the trees.
        case .ocean, .lake:
            return c.windKMH > 30 ? 1.3 : 1
        case .leaves:
            return c.windKMH > 30 ? 1.5 : c.windKMH < 8 ? 0.6 : 1
        // Snow muffles a city; rain empties café terraces.
        case .cityHum, .train:
            return c.isSnow ? 0.6 : 1
        case .cafe:
            return heavy ? 0.5 : 1
        case .whales:
            return heavy ? 0.6 : 1
        default:
            return 1
        }
    }

    /// The place whose weather is most unlike home's.
    static func bestEscape(from home: Conditions?, options: [Conditions]) -> Int {
        guard let home else { return 0 }
        func distance(_ c: Conditions) -> Double {
            (c.isRaining != home.isRaining ? 2 : 0)
                + abs(c.temperatureC - home.temperatureC) / 10
                + abs(c.windKMH - home.windKMH) / 25
                + (c.isDay != home.isDay ? 0.5 : 0)
        }
        return options.indices.max { distance(options[$0]) < distance(options[$1]) } ?? 0
    }
}

/// One-shot approximate location, plus a reverse-geocoded place name.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func current() async throws -> (CLLocationCoordinate2D, String) {
        let location: CLLocation = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(.failure(CLError(.denied)))
            default: manager.requestLocation()
            }
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.locality ?? placemark?.administrativeArea ?? "Here"
        return (location.coordinate, name)
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard continuation != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: finish(.failure(CLError(.denied)))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }
}
