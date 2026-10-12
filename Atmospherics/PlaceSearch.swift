import MapKit
import Observation

/// Finds towns and cities anywhere, using Apple's place search, and turns a pick into a `Place`
/// whose sounds are guessed from what's nearby.
@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet { query.isEmpty ? (results = []) : (completer.queryFragment = query) }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var resolving = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = .address
        completer.delegate = self
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in self.results = Array(found.prefix(8)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    /// Looks up the chosen suggestion and builds a place for it.
    func resolve(_ completion: MKLocalSearchCompletion) async -> Place? {
        resolving = true
        defer { resolving = false }
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first
        else { return nil }
        let mark = item.placemark
        let coordinate = mark.coordinate
        let name = mark.locality ?? item.name ?? completion.title
        let country = (mark.isoCountryCode == "US" ? mark.administrativeArea : mark.country) ?? completion.subtitle
        return Place(name: name, country: country, region: .yours,
                     latitude: coordinate.latitude, longitude: coordinate.longitude,
                     signature: await Self.cast(near: coordinate))
    }

    /// What could be heard around a spot, worked out from what's nearby: a beach means surf,
    /// a lake means lapping water, train stations mean a city, trees mean rustling leaves.
    /// `Ecology` then decides which of these are in season and awake at any moment.
    static func cast(near c: CLLocationCoordinate2D) async -> [(SoundKind, Double)] {
        async let beaches = count("beach", near: c, km: 15)
        async let stations = count("train station", near: c, km: 5)
        async let lakes = count("lake", near: c, km: 10)
        async let woods = count("forest", near: c, km: 10)
        async let cafes = count("cafe", near: c, km: 1)
        async let churches = count("church", near: c, km: 1.5)
        let (b, s, l, f, k, ch) = await (beaches, stations, lakes, woods, cafes, churches)
        let tropical = abs(c.latitude) < 23.5
        let urban = s >= 2

        var cast: [(SoundKind, Double)] = []
        if b > 0 { cast.append((.ocean, 0.55)) }
        if l > 0 && b == 0 { cast.append((.lake, 0.35)) }
        if urban { cast.append((.cityHum, 0.4)) } else if s == 1 { cast.append((.cityHum, 0.2)) }
        if s >= 5 { cast.append((.train, 0.15)) }
        if k >= 5 { cast.append((.cafe, 0.2)) }
        if ch >= 2 { cast.append((.bells, 0.12)) }
        if f > 0 || !urban { cast.append((.leaves, urban ? 0.15 : 0.3)) }
        if !urban && l == 0 && b == 0 { cast.append((.stream, 0.2)) }
        if tropical {
            cast += [(.jungleBirds, 0.25), (.crickets, 0.25), (.treeFrogs, 0.2)]
        } else {
            cast += [(.birds, urban ? 0.12 : 0.2), (.crickets, urban ? 0.1 : 0.2)]
            if !urban { cast += [(.owls, 0.15), (.frogs, l > 0 ? 0.2 : 0.1)] }
        }
        return cast
    }

    private static func count(_ what: String, near c: CLLocationCoordinate2D, km: Double) async -> Int {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = what
        request.region = MKCoordinateRegion(center: c, latitudinalMeters: km * 2000, longitudinalMeters: km * 2000)
        if #available(iOS 18, *) { request.regionPriority = .required }
        // Before iOS 18 results can spill outside the region, so count only those inside it.
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        let center = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return items.filter { $0.placemark.location.map { $0.distance(from: center) <= km * 1000 } ?? false }.count
    }
}
