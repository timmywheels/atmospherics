import Foundation

/// A place you can listen to. Its sound is its live weather plus a signature that
/// makes it that place. Fire only joins in when it's actually cold there.
struct Place: Identifiable, Hashable {
    enum Region: String, CaseIterable {
        case americas = "Americas", europe = "Europe", africa = "Africa & Middle East", asia = "Asia", oceania = "Oceania"
    }

    let name: String
    let country: String
    let region: Region
    let latitude: Double
    let longitude: Double
    let signature: [(SoundKind, Double)]

    var id: String { name }

    /// The name as a title: "The Highlands" rather than "the Highlands".
    var title: String { name.prefix(1).uppercased() + name.dropFirst() }

    /// The loudest signature sound, used to color the place on the globe.
    var accent: SoundKind { signature.max { $0.1 < $1.1 }?.0 ?? .ocean }

    static func == (a: Place, b: Place) -> Bool { a.name == b.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    static func named(_ name: String) -> Place? { all.first { $0.name == name } }

    static let all: [Place] = [
        // Americas
        Place(name: "Aruba", country: "Caribbean", region: .americas, latitude: 12.52, longitude: -70.03,
              signature: [(.ocean, 0.6), (.wind, 0.45), (.birds, 0.15)]),
        Place(name: "Havana", country: "Cuba", region: .americas, latitude: 23.11, longitude: -82.37,
              signature: [(.ocean, 0.4), (.crickets, 0.3), (.cityHum, 0.2)]),
        Place(name: "Honolulu", country: "Hawaiʻi", region: .americas, latitude: 21.31, longitude: -157.86,
              signature: [(.ocean, 0.55), (.wind, 0.3), (.birds, 0.2)]),
        Place(name: "New York", country: "USA", region: .americas, latitude: 40.71, longitude: -74.01,
              signature: [(.cityHum, 0.6), (.train, 0.2)]),
        Place(name: "Boston", country: "Massachusetts", region: .americas, latitude: 42.36, longitude: -71.06,
              signature: [(.cityHum, 0.4), (.ocean, 0.3), (.train, 0.15)]),
        Place(name: "Providence", country: "Rhode Island", region: .americas, latitude: 41.82, longitude: -71.41,
              signature: [(.cityHum, 0.35), (.stream, 0.25), (.birds, 0.15)]),
        Place(name: "Waterford", country: "Maine", region: .americas, latitude: 44.25, longitude: -70.75,
              signature: [(.stream, 0.35), (.birds, 0.3), (.crickets, 0.25), (.fire, 0.4)]),
        Place(name: "San Francisco", country: "USA", region: .americas, latitude: 37.77, longitude: -122.42,
              signature: [(.ocean, 0.35), (.wind, 0.3), (.cityHum, 0.25)]),
        Place(name: "Big Sur", country: "USA", region: .americas, latitude: 36.27, longitude: -121.81,
              signature: [(.ocean, 0.65), (.birds, 0.15)]),
        Place(name: "Vancouver", country: "Canada", region: .americas, latitude: 49.28, longitude: -123.12,
              signature: [(.stream, 0.3), (.ocean, 0.3), (.cityHum, 0.15)]),
        Place(name: "Mexico City", country: "Mexico", region: .americas, latitude: 19.43, longitude: -99.13,
              signature: [(.cityHum, 0.5), (.birds, 0.15)]),
        Place(name: "Manaus", country: "Brazil", region: .americas, latitude: -3.12, longitude: -60.02,
              signature: [(.frogs, 0.45), (.birds, 0.4), (.green, 0.3)]),
        Place(name: "Rio de Janeiro", country: "Brazil", region: .americas, latitude: -22.91, longitude: -43.17,
              signature: [(.ocean, 0.55), (.birds, 0.25), (.cityHum, 0.15)]),
        Place(name: "Buenos Aires", country: "Argentina", region: .americas, latitude: -34.60, longitude: -58.38,
              signature: [(.cityHum, 0.4), (.birds, 0.2)]),
        Place(name: "Reykjavík", country: "Iceland", region: .europe, latitude: 64.15, longitude: -21.94,
              signature: [(.wind, 0.55), (.ocean, 0.35)]),

        // Europe
        Place(name: "London", country: "UK", region: .europe, latitude: 51.51, longitude: -0.13,
              signature: [(.cityHum, 0.45), (.train, 0.25)]),
        Place(name: "the Highlands", country: "Scotland", region: .europe, latitude: 57.12, longitude: -4.71,
              signature: [(.fire, 0.5), (.wind, 0.3)]),
        Place(name: "Paris", country: "France", region: .europe, latitude: 48.86, longitude: 2.35,
              signature: [(.cityHum, 0.4), (.birds, 0.15)]),
        Place(name: "Amsterdam", country: "Netherlands", region: .europe, latitude: 52.37, longitude: 4.90,
              signature: [(.stream, 0.3), (.cityHum, 0.3), (.wind, 0.2)]),
        Place(name: "Lisbon", country: "Portugal", region: .europe, latitude: 38.72, longitude: -9.14,
              signature: [(.ocean, 0.4), (.cityHum, 0.25)]),
        Place(name: "Rome", country: "Italy", region: .europe, latitude: 41.90, longitude: 12.50,
              signature: [(.cicadas, 0.3), (.cityHum, 0.3)]),
        Place(name: "Lofoten", country: "Norway", region: .europe, latitude: 68.23, longitude: 14.56,
              signature: [(.ocean, 0.5), (.fire, 0.45)]),
        Place(name: "Lanzarote", country: "Spain", region: .europe, latitude: 28.96, longitude: -13.55,
              signature: [(.ocean, 0.6)]),

        // Africa & Middle East
        Place(name: "Marrakech", country: "Morocco", region: .africa, latitude: 31.63, longitude: -7.99,
              signature: [(.cityHum, 0.35), (.wind, 0.25), (.crickets, 0.2)]),
        Place(name: "Cairo", country: "Egypt", region: .africa, latitude: 30.04, longitude: 31.24,
              signature: [(.cityHum, 0.45), (.wind, 0.2)]),
        Place(name: "Nairobi", country: "Kenya", region: .africa, latitude: -1.29, longitude: 36.82,
              signature: [(.birds, 0.35), (.crickets, 0.25)]),
        Place(name: "Cape Town", country: "South Africa", region: .africa, latitude: -33.92, longitude: 18.42,
              signature: [(.ocean, 0.5), (.wind, 0.4)]),
        Place(name: "Dubai", country: "UAE", region: .africa, latitude: 25.20, longitude: 55.27,
              signature: [(.cityHum, 0.35), (.wind, 0.3)]),

        // Asia
        Place(name: "Mumbai", country: "India", region: .asia, latitude: 19.08, longitude: 72.88,
              signature: [(.cityHum, 0.4), (.ocean, 0.3), (.birds, 0.15)]),
        Place(name: "Kathmandu", country: "Nepal", region: .asia, latitude: 27.72, longitude: 85.32,
              signature: [(.chimes, 0.35), (.wind, 0.25), (.birds, 0.2)]),
        Place(name: "Bangkok", country: "Thailand", region: .asia, latitude: 13.76, longitude: 100.50,
              signature: [(.cityHum, 0.35), (.cicadas, 0.3)]),
        Place(name: "Singapore", country: "Singapore", region: .asia, latitude: 1.35, longitude: 103.82,
              signature: [(.cicadas, 0.3), (.cityHum, 0.3), (.frogs, 0.2)]),
        Place(name: "Bali", country: "Indonesia", region: .asia, latitude: -8.41, longitude: 115.19,
              signature: [(.ocean, 0.4), (.frogs, 0.3), (.crickets, 0.3), (.chimes, 0.15)]),
        Place(name: "Hong Kong", country: "China", region: .asia, latitude: 22.32, longitude: 114.17,
              signature: [(.cityHum, 0.45), (.ocean, 0.25)]),
        Place(name: "Seoul", country: "South Korea", region: .asia, latitude: 37.57, longitude: 126.98,
              signature: [(.cityHum, 0.4), (.cicadas, 0.2)]),
        Place(name: "Kyoto", country: "Japan", region: .asia, latitude: 35.01, longitude: 135.77,
              signature: [(.stream, 0.4), (.chimes, 0.25), (.birds, 0.2)]),
        Place(name: "Tokyo", country: "Japan", region: .asia, latitude: 35.68, longitude: 139.69,
              signature: [(.cityHum, 0.45), (.train, 0.3), (.crickets, 0.15)]),

        // Oceania
        Place(name: "Sydney", country: "Australia", region: .oceania, latitude: -33.87, longitude: 151.21,
              signature: [(.ocean, 0.45), (.birds, 0.25), (.cicadas, 0.2)]),
        Place(name: "Queenstown", country: "New Zealand", region: .oceania, latitude: -45.03, longitude: 168.66,
              signature: [(.stream, 0.4), (.wind, 0.35), (.birds, 0.15)]),
    ]
}
