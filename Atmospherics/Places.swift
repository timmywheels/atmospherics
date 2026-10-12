import Foundation

/// A place you can listen to. Its sound is its live weather plus its cast: everything you
/// could hear there over a year. `Ecology` decides which of them are out right now.
struct Place: Identifiable, Hashable {
    enum Region: String, CaseIterable {
        case yours = "Your places"
        case americas = "Americas", europe = "Europe", africa = "Africa & Middle East", asia = "Asia", oceania = "Oceania"
    }

    let name: String
    let country: String
    let region: Region
    let latitude: Double
    let longitude: Double
    let signature: [(SoundKind, Double)]
    /// Defaults to one worked out from the latitude.
    var climate: Climate? = nil
    /// Rainy-season months in the tropics, when the frogs are loudest.
    var wetMonths: [Int] = []
    /// Months some sounds are around at all, e.g. whales passing through.
    var seasonal: [SoundKind: [Int]] = [:]

    var id: String { name }

    /// The name as a title: "The Highlands" rather than "the Highlands".
    var title: String { name.prefix(1).uppercased() + name.dropFirst() }

    /// The loudest signature sound, used to color the place on the globe.
    var accent: SoundKind { signature.max { $0.1 < $1.1 }?.0 ?? .ocean }

    static func == (a: Place, b: Place) -> Bool { a.name == b.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    static func named(_ name: String) -> Place? { all.first { $0.name == name } }

    // MARK: Saved places (from search)

    var dictionary: [String: Any] {
        ["name": name, "country": country, "lat": latitude, "lon": longitude,
         "signature": signature.map { ["kind": $0.0.rawValue, "level": $0.1] }]
    }

    // Cast levels are each sound at its seasonal peak.
    static let all: [Place] = [
        // Americas
        Place(name: "Aruba", country: "Caribbean", region: .americas, latitude: 12.52, longitude: -70.03,
              signature: [(.lapping, 0.55), (.ocean, 0.2), (.wind, 0.45), (.parrots, 0.15), (.crickets, 0.2), (.planes, 0.15), (.palms, 0.35)],
              climate: .tropical, wetMonths: [10, 11, 12, 1]),
        Place(name: "Havana", country: "Cuba", region: .americas, latitude: 23.11, longitude: -82.37,
              signature: [(.ocean, 0.4), (.cityHum, 0.3), (.cafe, 0.2), (.crickets, 0.25), (.traffic, 0.2), (.planes, 0.05), (.palms, 0.15)],
              climate: .tropical, wetMonths: [5, 6, 7, 8, 9, 10]),
        Place(name: "Honolulu", country: "Hawaiʻi", region: .americas, latitude: 21.31, longitude: -157.86,
              signature: [(.lapping, 0.35), (.ocean, 0.4), (.wind, 0.3), (.jungleBirds, 0.15), (.crickets, 0.15), (.whales, 0.2), (.cityHum, 0.1), (.traffic, 0.1), (.planes, 0.2), (.palms, 0.25)],
              climate: .tropical, wetMonths: [10, 11, 12, 1, 2, 3], seasonal: [.whales: [12, 1, 2, 3, 4]]),
        Place(name: "New York", country: "USA", region: .americas, latitude: 40.71, longitude: -74.01,
              signature: [(.cityHum, 0.55), (.cafe, 0.25), (.train, 0.15), (.birds, 0.1), (.crickets, 0.12), (.cicadas, 0.12), (.leaves, 0.1), (.geese, 0.06), (.traffic, 0.35), (.highway, 0.15), (.planes, 0.15)],
              climate: .temperate),
        Place(name: "Boston", country: "Massachusetts", region: .americas, latitude: 42.36, longitude: -71.06,
              signature: [(.cityHum, 0.35), (.lake, 0.2), (.cafe, 0.2), (.bells, 0.15), (.train, 0.1),
                          (.birds, 0.12), (.leaves, 0.12), (.crickets, 0.1), (.cicadas, 0.1), (.gulls, 0.15), (.geese, 0.1), (.traffic, 0.25), (.highway, 0.12), (.planes, 0.25), (.buoy, 0.12), (.halyards, 0.1)],
              climate: .temperate),
        Place(name: "Providence", country: "Rhode Island", region: .americas, latitude: 41.82, longitude: -71.41,
              signature: [(.cityHum, 0.3), (.leaves, 0.22), (.bells, 0.2), (.cafe, 0.15), (.lake, 0.15),
                          (.birds, 0.15), (.crickets, 0.15), (.cicadas, 0.1), (.owls, 0.12), (.gulls, 0.1), (.geese, 0.15),
                          (.peepers, 0.1), (.traffic, 0.2), (.highway, 0.15), (.planes, 0.12)],
              climate: .temperate),
        Place(name: "Newport", country: "Rhode Island", region: .americas, latitude: 41.49, longitude: -71.31,
              signature: [(.rocks, 0.45), (.ocean, 0.25), (.halyards, 0.3), (.buoy, 0.25), (.gulls, 0.25), (.birds, 0.12),
                          (.leaves, 0.12), (.crickets, 0.12), (.geese, 0.1), (.cafe, 0.12), (.bells, 0.1), (.traffic, 0.06),
                          (.planes, 0.05)],
              climate: .temperate),
        Place(name: "Waterford", country: "Maine", region: .americas, latitude: 44.25, longitude: -70.75,
              signature: [(.lake, 0.4), (.leaves, 0.35), (.loons, 0.35), (.owls, 0.25), (.fire, 0.4),
                          (.birds, 0.2), (.crickets, 0.2), (.frogs, 0.2), (.stream, 0.12), (.peepers, 0.3), (.geese, 0.2), (.planes, 0.05)],
              climate: .continental),
        Place(name: "Yellowstone", country: "Wyoming", region: .americas, latitude: 44.43, longitude: -110.59,
              signature: [(.wolves, 0.3), (.lake, 0.3), (.wind, 0.3), (.leaves, 0.2), (.stream, 0.2),
                          (.owls, 0.15), (.birds, 0.12), (.fire, 0.25), (.geese, 0.15), (.peepers, 0.1), (.planes, 0.05)],
              climate: .continental),
        Place(name: "Seattle", country: "Washington", region: .americas, latitude: 47.61, longitude: -122.33,
              signature: [(.cityHum, 0.3), (.cafe, 0.3), (.lake, 0.2), (.leaves, 0.15), (.birds, 0.1), (.gulls, 0.15), (.geese, 0.1), (.traffic, 0.2), (.highway, 0.15), (.planes, 0.15), (.halyards, 0.12), (.buoy, 0.08)],
              climate: .temperate),
        Place(name: "San Francisco", country: "USA", region: .americas, latitude: 37.77, longitude: -122.42,
              signature: [(.ocean, 0.3), (.wind, 0.3), (.cityHum, 0.25), (.cafe, 0.15), (.birds, 0.08), (.gulls, 0.15), (.traffic, 0.15), (.highway, 0.08), (.planes, 0.12), (.buoy, 0.15), (.halyards, 0.15)],
              climate: .mediterranean),
        Place(name: "Big Sur", country: "USA", region: .americas, latitude: 36.27, longitude: -121.81,
              signature: [(.rocks, 0.45), (.ocean, 0.35), (.wind, 0.25), (.whales, 0.2), (.birds, 0.12), (.leaves, 0.12), (.crickets, 0.1), (.gulls, 0.08), (.traffic, 0.04), (.planes, 0.05)],
              climate: .mediterranean, seasonal: [.whales: [12, 1, 2, 3, 4, 7, 8, 9, 10, 11]]),
        Place(name: "Vancouver", country: "Canada", region: .americas, latitude: 49.28, longitude: -123.12,
              signature: [(.lake, 0.25), (.stream, 0.2), (.leaves, 0.2), (.cityHum, 0.2), (.birds, 0.1), (.gulls, 0.12), (.geese, 0.12), (.traffic, 0.15), (.planes, 0.1), (.halyards, 0.12)],
              climate: .temperate),
        Place(name: "Mexico City", country: "Mexico", region: .americas, latitude: 19.43, longitude: -99.13,
              signature: [(.cityHum, 0.45), (.cafe, 0.2), (.bells, 0.2), (.crickets, 0.1), (.traffic, 0.4), (.highway, 0.15), (.planes, 0.25)],
              climate: .tropical, wetMonths: [5, 6, 7, 8, 9, 10]),
        Place(name: "Manaus", country: "Brazil", region: .americas, latitude: -3.12, longitude: -60.02,
              signature: [(.canopy, 0.45), (.howlers, 0.4), (.treeFrogs, 0.35), (.jungleBirds, 0.3),
                          (.parrots, 0.2), (.crickets, 0.2), (.planes, 0.05)],
              climate: .tropical, wetMonths: [12, 1, 2, 3, 4, 5]),
        Place(name: "Rio de Janeiro", country: "Brazil", region: .americas, latitude: -22.91, longitude: -43.17,
              signature: [(.ocean, 0.55), (.jungleBirds, 0.2), (.cityHum, 0.2), (.cafe, 0.12), (.cicadas, 0.15), (.crickets, 0.15), (.traffic, 0.25), (.planes, 0.15), (.palms, 0.15)],
              climate: .tropical, wetMonths: [12, 1, 2, 3]),
        Place(name: "Buenos Aires", country: "Argentina", region: .americas, latitude: -34.60, longitude: -58.38,
              signature: [(.cityHum, 0.4), (.cafe, 0.3), (.birds, 0.12), (.crickets, 0.12), (.bells, 0.1), (.traffic, 0.35), (.planes, 0.1)],
              climate: .subtropical),

        // Europe
        Place(name: "Reykjavík", country: "Iceland", region: .europe, latitude: 64.15, longitude: -21.94,
              signature: [(.wind, 0.5), (.ocean, 0.35), (.stream, 0.1), (.birds, 0.06), (.gulls, 0.15), (.geese, 0.1), (.traffic, 0.08), (.planes, 0.05), (.rocks, 0.25), (.halyards, 0.1)],
              climate: .subpolar),
        Place(name: "London", country: "UK", region: .europe, latitude: 51.51, longitude: -0.13,
              signature: [(.cityHum, 0.4), (.train, 0.18), (.cafe, 0.2), (.bells, 0.15), (.birds, 0.12), (.leaves, 0.1), (.gulls, 0.06), (.traffic, 0.3), (.planes, 0.25)],
              climate: .temperate),
        Place(name: "the Highlands", country: "Scotland", region: .europe, latitude: 57.12, longitude: -4.71,
              signature: [(.fire, 0.45), (.wind, 0.35), (.stream, 0.3), (.owls, 0.15), (.birds, 0.12), (.geese, 0.12), (.planes, 0.05)],
              climate: .temperate),
        Place(name: "Paris", country: "France", region: .europe, latitude: 48.86, longitude: 2.35,
              signature: [(.cafe, 0.4), (.cityHum, 0.3), (.bells, 0.2), (.birds, 0.1), (.leaves, 0.1), (.traffic, 0.3), (.planes, 0.06)],
              climate: .temperate),
        Place(name: "Amsterdam", country: "Netherlands", region: .europe, latitude: 52.37, longitude: 4.90,
              signature: [(.lake, 0.25), (.cityHum, 0.25), (.cafe, 0.2), (.bells, 0.2), (.birds, 0.1), (.gulls, 0.12), (.geese, 0.1), (.traffic, 0.1), (.planes, 0.15)],
              climate: .temperate),
        Place(name: "Lisbon", country: "Portugal", region: .europe, latitude: 38.72, longitude: -9.14,
              signature: [(.ocean, 0.3), (.cityHum, 0.25), (.cafe, 0.25), (.bells, 0.15), (.crickets, 0.1), (.gulls, 0.18), (.traffic, 0.25), (.planes, 0.35), (.halyards, 0.08)],
              climate: .mediterranean),
        Place(name: "Rome", country: "Italy", region: .europe, latitude: 41.90, longitude: 12.50,
              signature: [(.cityHum, 0.3), (.bells, 0.3), (.cafe, 0.2), (.cicadas, 0.3), (.stream, 0.15), (.crickets, 0.15), (.birds, 0.1), (.traffic, 0.35), (.planes, 0.06)],
              climate: .mediterranean),
        Place(name: "Lofoten", country: "Norway", region: .europe, latitude: 68.23, longitude: 14.56,
              signature: [(.ocean, 0.5), (.wind, 0.35), (.fire, 0.45), (.birds, 0.05), (.gulls, 0.18), (.planes, 0.05), (.rocks, 0.3), (.halyards, 0.12)],
              climate: .subpolar),
        Place(name: "Lanzarote", country: "Spain", region: .europe, latitude: 28.96, longitude: -13.55,
              signature: [(.rocks, 0.35), (.ocean, 0.45), (.wind, 0.3), (.crickets, 0.08), (.planes, 0.12), (.palms, 0.08)],
              climate: .arid),

        // Africa & Middle East
        Place(name: "The Gambia", country: "West Africa", region: .africa, latitude: 13.45, longitude: -16.58,
              signature: [(.jungleBirds, 0.35), (.ocean, 0.35), (.crickets, 0.25), (.treeFrogs, 0.2), (.cicadas, 0.12), (.traffic, 0.05), (.planes, 0.05), (.palms, 0.2)],
              climate: .tropical, wetMonths: [6, 7, 8, 9, 10]),
        Place(name: "Cape Verde", country: "Atlantic islands", region: .africa, latitude: 16.75, longitude: -22.95,
              signature: [(.lapping, 0.35), (.ocean, 0.35), (.wind, 0.45), (.crickets, 0.08), (.planes, 0.06)],
              climate: .arid, wetMonths: [8, 9, 10]),
        Place(name: "Marrakech", country: "Morocco", region: .africa, latitude: 31.63, longitude: -7.99,
              signature: [(.cityHum, 0.35), (.cafe, 0.3), (.wind, 0.2), (.crickets, 0.15), (.birds, 0.08), (.traffic, 0.25), (.planes, 0.05), (.palms, 0.1)],
              climate: .arid),
        Place(name: "Cairo", country: "Egypt", region: .africa, latitude: 30.04, longitude: 31.24,
              signature: [(.cityHum, 0.5), (.cafe, 0.15), (.wind, 0.2), (.crickets, 0.08), (.traffic, 0.45), (.highway, 0.15), (.planes, 0.08)],
              climate: .arid),
        Place(name: "Nairobi", country: "Kenya", region: .africa, latitude: -1.29, longitude: 36.82,
              signature: [(.jungleBirds, 0.35), (.crickets, 0.25), (.cityHum, 0.15), (.treeFrogs, 0.1), (.traffic, 0.25), (.planes, 0.08)],
              climate: .tropical, wetMonths: [3, 4, 5, 10, 11, 12]),
        Place(name: "Cape Town", country: "South Africa", region: .africa, latitude: -33.92, longitude: 18.42,
              signature: [(.ocean, 0.5), (.wind, 0.4), (.whales, 0.2), (.birds, 0.1), (.gulls, 0.12), (.traffic, 0.12), (.planes, 0.06), (.rocks, 0.3), (.halyards, 0.15)],
              climate: .mediterranean, seasonal: [.whales: [6, 7, 8, 9, 10, 11]]),
        Place(name: "Dubai", country: "UAE", region: .africa, latitude: 25.20, longitude: 55.27,
              signature: [(.cityHum, 0.35), (.wind, 0.3), (.lake, 0.15), (.traffic, 0.3), (.highway, 0.3), (.planes, 0.2), (.palms, 0.1)],
              climate: .arid),

        // Asia
        Place(name: "Mumbai", country: "India", region: .asia, latitude: 19.08, longitude: 72.88,
              signature: [(.cityHum, 0.45), (.ocean, 0.3), (.jungleBirds, 0.12), (.crickets, 0.15), (.traffic, 0.4), (.planes, 0.15), (.palms, 0.08)],
              climate: .tropical, wetMonths: [6, 7, 8, 9]),
        Place(name: "Kathmandu", country: "Nepal", region: .asia, latitude: 27.72, longitude: 85.32,
              signature: [(.chimes, 0.3), (.bells, 0.25), (.cityHum, 0.2), (.wind, 0.2), (.birds, 0.12), (.crickets, 0.12), (.traffic, 0.25), (.planes, 0.06)],
              climate: .subtropical),
        Place(name: "Bangkok", country: "Thailand", region: .asia, latitude: 13.76, longitude: 100.50,
              signature: [(.cityHum, 0.4), (.cicadas, 0.25), (.crickets, 0.2), (.cafe, 0.15), (.traffic, 0.4), (.highway, 0.15), (.planes, 0.08)],
              climate: .tropical, wetMonths: [5, 6, 7, 8, 9, 10]),
        Place(name: "Singapore", country: "Singapore", region: .asia, latitude: 1.35, longitude: 103.82,
              signature: [(.cityHum, 0.3), (.cicadas, 0.3), (.treeFrogs, 0.2), (.jungleBirds, 0.12), (.crickets, 0.15), (.traffic, 0.2), (.highway, 0.1), (.planes, 0.08), (.palms, 0.1)],
              climate: .tropical, wetMonths: [11, 12, 1]),
        Place(name: "Bali", country: "Indonesia", region: .asia, latitude: -8.41, longitude: 115.19,
              signature: [(.lapping, 0.3), (.ocean, 0.25), (.treeFrogs, 0.3), (.crickets, 0.3), (.jungleBirds, 0.2), (.cicadas, 0.15), (.chimes, 0.12), (.traffic, 0.06), (.planes, 0.05), (.palms, 0.25)],
              climate: .tropical, wetMonths: [11, 12, 1, 2, 3]),
        Place(name: "Hong Kong", country: "China", region: .asia, latitude: 22.32, longitude: 114.17,
              signature: [(.cityHum, 0.45), (.lake, 0.2), (.cafe, 0.12), (.cicadas, 0.15), (.train, 0.1), (.traffic, 0.3), (.planes, 0.08)],
              climate: .subtropical),
        Place(name: "Seoul", country: "South Korea", region: .asia, latitude: 37.57, longitude: 126.98,
              signature: [(.cityHum, 0.4), (.cafe, 0.2), (.cicadas, 0.3), (.birds, 0.1), (.train, 0.1), (.traffic, 0.3), (.highway, 0.12), (.planes, 0.06)],
              climate: .continental),
        Place(name: "Kyoto", country: "Japan", region: .asia, latitude: 35.01, longitude: 135.77,
              signature: [(.stream, 0.28), (.leaves, 0.3), (.chimes, 0.15), (.bells, 0.15), (.birds, 0.15),
                          (.cicadas, 0.25), (.crickets, 0.2), (.traffic, 0.06)],
              climate: .subtropical),
        Place(name: "Tokyo", country: "Japan", region: .asia, latitude: 35.68, longitude: 139.69,
              signature: [(.cityHum, 0.45), (.train, 0.2), (.cafe, 0.15), (.cicadas, 0.25), (.crickets, 0.15), (.birds, 0.08), (.traffic, 0.25), (.highway, 0.1), (.planes, 0.08)],
              climate: .subtropical),

        // Oceania
        Place(name: "Sydney", country: "Australia", region: .oceania, latitude: -33.87, longitude: 151.21,
              signature: [(.ocean, 0.45), (.birds, 0.25), (.cicadas, 0.25), (.cityHum, 0.15), (.crickets, 0.1), (.gulls, 0.08), (.traffic, 0.15), (.planes, 0.2), (.halyards, 0.15)],
              climate: .subtropical),
        Place(name: "Queenstown", country: "New Zealand", region: .oceania, latitude: -45.03, longitude: 168.66,
              signature: [(.lake, 0.35), (.wind, 0.3), (.stream, 0.25), (.birds, 0.15), (.fire, 0.25), (.leaves, 0.1), (.planes, 0.12)],
              climate: .temperate),
    ]
}

extension Place {
    init?(dictionary d: [String: Any]) {
        guard let name = d["name"] as? String, let country = d["country"] as? String,
              let lat = d["lat"] as? Double, let lon = d["lon"] as? Double,
              let sig = d["signature"] as? [[String: Any]] else { return nil }
        self.init(name: name, country: country, region: .yours, latitude: lat, longitude: lon,
                  signature: sig.compactMap { e in
                      guard let raw = e["kind"] as? String, let kind = SoundKind(rawValue: raw),
                            let level = e["level"] as? Double else { return nil }
                      return (kind, level)
                  })
    }
}
