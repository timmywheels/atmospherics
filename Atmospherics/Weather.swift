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
    var latitude: Double = 0
    var utcOffset: Int = 0           // seconds from UTC, for the local clock there
    var sunrise: Int? = nil          // minutes after local midnight
    var sunset: Int? = nil
    var snowDepth: Double = 0        // metres of snow on the ground
    var forcedPhase: DayPhase? = nil // a time-of-day override
    var forcedHour: Int? = nil       // an imagined scene's hour, instead of the clock's
    var forcedMonth: Int? = nil      // an imagined scene's month, for its season

    var isThunder: Bool { (95...99).contains(code) }
    var isSnow: Bool { (71...77).contains(code) || code == 85 || code == 86 }
    var isFog: Bool { code == 45 || code == 48 }
    enum RainIntensity { case light, moderate, heavy }

    var rainIntensity: RainIntensity {
        if isThunder || precipitationMM > 4 || [65, 67, 82].contains(code) { return .heavy }
        if precipitationMM < 0.6 && [51, 53, 55, 56, 57, 61, 80].contains(code) { return .light }
        if precipitationMM < 0.4 { return .light }
        return .moderate
    }

    var isRaining: Bool { precipitationMM > 0.05 || (51...67).contains(code) || (80...82).contains(code) || isThunder }

    /// "auto" (the phone's region), "f" or "c"; set from the menu.
    static var unitPreference: String { UserDefaults.standard.string(forKey: "tempUnit") ?? "auto" }

    var temperature: String {
        let m = Measurement(value: temperatureC, unit: UnitTemperature.celsius)
        switch Self.unitPreference {
        case "f": return "\(Int(m.converted(to: .fahrenheit).value.rounded()))°"
        case "c": return "\(Int(temperatureC.rounded()))°"
        default:
            return m.formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
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
            let snow_depth: Double?
        }
        struct Daily: Decodable {
            let sunrise: [String]
            let sunset: [String]
        }
        let current: Current
        let daily: Daily?
        let utc_offset_seconds: Int?
    }

    /// "2026-10-12T06:54" → minutes after midnight.
    private static func minutes(_ stamp: String?) -> Int? {
        guard let stamp, let t = stamp.split(separator: "T").last else { return nil }
        let parts = t.split(separator: ":").compactMap { Int($0) }
        return parts.count >= 2 ? parts[0] * 60 + parts[1] : nil
    }

    private func openMeteo(_ points: [(Double, Double)]) async throws -> [Conditions] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: points.map { String(format: "%.2f", $0.0) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: points.map { String(format: "%.2f", $0.1) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "temperature_2m,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,pressure_msl,is_day,snow_depth"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.badResponse }
        // One point returns an object; several return an array.
        let decoded: [OpenMeteoResponse] = points.count == 1
            ? [try JSONDecoder().decode(OpenMeteoResponse.self, from: data)]
            : try JSONDecoder().decode([OpenMeteoResponse].self, from: data)
        return zip(decoded, points).map { r, point in
            let c = r.current
            return Conditions(place: "", temperatureC: c.temperature_2m, precipitationMM: c.precipitation,
                              windKMH: max(c.wind_speed_10m, (c.wind_gusts_10m ?? 0) * 0.7),
                              pressureHPA: c.pressure_msl, code: c.weather_code, isDay: c.is_day == 1,
                              latitude: point.0, utcOffset: r.utc_offset_seconds ?? 0,
                              sunrise: Self.minutes(r.daily?.sunrise.first), sunset: Self.minutes(r.daily?.sunset.first),
                              snowDepth: c.snow_depth ?? 0)
        }
    }
}

/// Turns conditions into a field of sounds.
enum WeatherMix {
    static func orbs(for c: Conditions, place: Place? = nil) -> [(SoundKind, Double)] {
        Soundscape.compose(c, place: place)
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
/// The permission status comes from the delegate, so the main thread never waits on the
/// location service, and a request gives up after 15 seconds rather than hanging
/// (but never while the person is still deciding on the permission prompt).
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var status: CLAuthorizationStatus?   // nil until the delegate first reports it
    private var deadline = 0                     // bumped to cancel a pending time limit

    override init() {
        super.init()
        manager.delegate = self   // iOS reports the current status right after this
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var isDenied: Bool { status == .denied || status == .restricted }

    func current() async throws -> (CLLocationCoordinate2D, String) {
        let location: CLLocation = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            // Without a status yet, wait for the delegate's first report (but not forever).
            if let status { proceed(status) } else { giveUp(after: 15) }
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.locality ?? placemark?.administrativeArea ?? "Here"
        return (location.coordinate, name)
    }

    private func proceed(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            deadline += 1   // no time limit while the person decides
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(CLError(.denied)))
        default:
            manager.requestLocation()
            giveUp(after: 15)
        }
    }

    /// Fails the request if the location service hasn't answered in time.
    private func giveUp(after seconds: Double) {
        deadline += 1
        let this = deadline
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.deadline == this else { return }
            self.finish(.failure(CLError(.locationUnknown)))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.status = status
            if self.continuation != nil { self.proceed(status) }
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
