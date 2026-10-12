import MapKit

/// Listens around your home, through Apple's place search, for "Outside your window".
enum PlaceSearch {
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
        async let airports = count("airport", near: c, km: 25)
        async let fuel = count("gas station", near: c, km: 3)   // where the big roads are
        let (b, s, l, f, k, ch) = await (beaches, stations, lakes, woods, cafes, churches)
        let (a, g) = await (airports, fuel)
        let tropical = abs(c.latitude) < 23.5
        let urban = s >= 2

        var cast: [(SoundKind, Double)] = []
        if b > 0 { cast.append((.ocean, 0.55)) }
        if l > 0 && b == 0 { cast.append((.lake, 0.35)) }
        if urban { cast.append((.cityHum, 0.4)) } else if s == 1 { cast.append((.cityHum, 0.2)) }
        // Cars on the streets, a highway's hum, and planes: often near an airport, now and then anywhere.
        if urban { cast.append((.traffic, 0.25)) } else if s == 1 || g > 0 { cast.append((.traffic, 0.08)) }
        if g >= 4 { cast.append((.highway, 0.15)) } else if g >= 1 { cast.append((.highway, 0.06)) }
        cast.append((.planes, a > 0 ? 0.15 : 0.05))
        if s >= 5 { cast.append((.train, 0.15)) }
        if k >= 5 { cast.append((.cafe, 0.2)) }
        if ch >= 2 { cast.append((.bells, 0.12)) }
        if f > 0 || !urban { cast.append((.leaves, urban ? 0.15 : 0.3)) }
        if !urban && l == 0 && b == 0 { cast.append((.stream, 0.2)) }
        if tropical {
            cast += [(.jungleBirds, 0.25), (.crickets, 0.25), (.treeFrogs, 0.2)]
        } else {
            cast += [(.birds, urban ? 0.12 : 0.2), (.crickets, urban ? 0.1 : 0.2), (.geese, urban ? 0.06 : 0.12)]
            if b > 0 { cast.append((.gulls, 0.12)) }
            if !urban { cast += [(.owls, 0.15), (.frogs, l > 0 ? 0.2 : 0.1)] }
            // Spring peepers: eastern North America's wet woods and towns.
            let easternNorthAmerica = (25...55).contains(c.latitude) && (-100 ... -55).contains(c.longitude)
            if easternNorthAmerica && !urban { cast.append((.peepers, l > 0 ? 0.25 : 0.15)) }
        }
        return cast
    }

    private static func count(_ what: String, near c: CLLocationCoordinate2D, km: Double) async -> Int {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = what
        request.region = MKCoordinateRegion(center: c, latitudinalMeters: km * 2000, longitudinalMeters: km * 2000)
        if #available(iOS 18, macOS 15, *) { request.regionPriority = .required }
        // Before iOS 18 (macOS 15) results can spill outside the region, so count only those inside it.
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        let center = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return items.filter { $0.placemark.location.map { $0.distance(from: center) <= km * 1000 } ?? false }.count
    }
}
