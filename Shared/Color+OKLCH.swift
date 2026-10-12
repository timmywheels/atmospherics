import SwiftUI

extension Color {
    /// OKLCH → sRGB, matching CSS `oklch()` so colors line up with the design mocks.
    static func oklch(_ l: Double, _ c: Double, _ h: Double) -> Color {
        let a = c * cos(h * .pi / 180), b = c * sin(h * .pi / 180)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        func encode(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return Color(.sRGB,
                     red: encode(4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S),
                     green: encode(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S),
                     blue: encode(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S))
    }

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}
