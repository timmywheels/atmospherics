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

/// A place to escape to. Coastal places add ocean; cold ones add a fire.
struct Escape {
    let name: String
    let latitude: Double
    let longitude: Double
    let coastal: Bool
    let cozy: Bool

    static let all: [Escape] = [
        Escape(name: "Lanzarote", latitude: 28.96, longitude: -13.55, coastal: true, cozy: false),
        Escape(name: "Lofoten", latitude: 68.23, longitude: 14.56, coastal: true, cozy: true),
        Escape(name: "Kyoto", latitude: 35.01, longitude: 135.77, coastal: false, cozy: false),
        Escape(name: "Big Sur", latitude: 36.27, longitude: -121.81, coastal: true, cozy: false),
        Escape(name: "Manaus", latitude: -3.12, longitude: -60.02, coastal: false, cozy: false),
        Escape(name: "the Highlands", latitude: 57.12, longitude: -4.71, coastal: false, cozy: true),
    ]
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

    /// Conditions at every escape, in `Escape.all` order, from one request.
    func escapes() async throws -> [Conditions] {
        var all = try await openMeteo(Escape.all.map { ($0.latitude, $0.longitude) })
        for i in all.indices { all[i].place = Escape.all[i].name }
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
    static func orbs(for c: Conditions, escape: Escape? = nil) -> [(SoundKind, Double)] {
        var mix: [(SoundKind, Double)] = []

        // A noise bed: deeper when pressure is low or it's night, brighter in fog.
        let lowPressure = c.pressureHPA < 1005
        if c.isFog {
            mix.append((.white, 0.35))
            mix.append((.brown, 0.5))
        } else if c.isDay && !c.isRaining && !lowPressure {
            mix.append((.pink, 0.55))
        } else {
            mix.append((.brown, lowPressure || c.isSnow ? 0.75 : 0.6))
        }

        if c.isRaining && !c.isSnow {
            mix.append((.rain, min(0.9, 0.4 + c.precipitationMM / 4)))
        }
        if c.isThunder {
            mix.append((.thunder, 0.4))
        }
        let wind = min(0.8, max(0, (c.windKMH - 6) / 40))
        if wind > 0.08 {
            mix.append((.wind, c.isSnow ? wind * 0.6 : wind))
        }
        if c.isDay && !c.isRaining && c.code <= 3 {
            mix.append((.birds, 0.2))
        }
        if let escape {
            if escape.coastal { mix.append((.ocean, 0.55)) }
            if escape.cozy && c.temperatureC < 12 { mix.append((.fire, 0.45)) }
        }
        return mix
    }

    /// The escape whose weather is most unlike home's.
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
