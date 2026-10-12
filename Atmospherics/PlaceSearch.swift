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
                     signature: await signature(near: coordinate))
    }

    /// A beach nearby means ocean; several train stations means a city. Birds everywhere, softly.
    private func signature(near c: CLLocationCoordinate2D) async -> [(SoundKind, Double)] {
        async let beaches = count("beach", near: c, km: 15)
        async let stations = count("train station", near: c, km: 5)
        async let lakes = count("lake", near: c, km: 10)
        async let woods = count("forest", near: c, km: 10)
        async let cafes = count("cafe", near: c, km: 1)
        let (b, s, l, f, k) = await (beaches, stations, lakes, woods, cafes)
        var sig: [(SoundKind, Double)] = []
        if b > 0 { sig.append((.ocean, 0.55)) }
        if l > 0 && b == 0 { sig.append((.lake, 0.4)) }
        if s >= 2 { sig.append((.cityHum, 0.4)) }
        if s >= 5 { sig.append((.train, 0.15)) }
        if k >= 5 { sig.append((.cafe, 0.2)) }
        if f > 0 && s < 2 { sig.append((.leaves, 0.25)) }
        if s < 2 && l == 0 && b == 0 { sig.append((.stream, 0.25)) }   // somewhere quieter: a little water
        // Tropical places get jungle birds and tree frogs; elsewhere, ordinary birds.
        if abs(c.latitude) < 23.5 {
            sig.append((.jungleBirds, 0.25))
            sig.append((.treeFrogs, 0.2))
        } else {
            sig.append((.birds, 0.2))
        }
        return sig
    }

    private func count(_ what: String, near c: CLLocationCoordinate2D, km: Double) async -> Int {
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
