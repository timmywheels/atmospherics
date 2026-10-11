import SwiftUI

enum NoiseColor: String, CaseIterable, Identifiable {
    case white, pink, brown, green, blue

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    var blurb: String {
        switch self {
        case .white: "Bright, even hiss"
        case .pink:  "Soft, like steady rain"
        case .brown: "Deep, like distant surf"
        case .green: "Mid-range, like a forest"
        case .blue:  "Crisp, like spray"
        }
    }

    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .white: (0.93, 0.93, 0.95)
        case .pink:  (0.96, 0.55, 0.68)
        case .brown: (0.78, 0.50, 0.28)
        case .green: (0.40, 0.80, 0.45)
        case .blue:  (0.36, 0.55, 0.98)
        }
    }

    var tint: Color { Color(red: rgb.r, green: rgb.g, blue: rgb.b) }
}
