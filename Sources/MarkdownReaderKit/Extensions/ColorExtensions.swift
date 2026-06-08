import SwiftUI

extension Color {
    public init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        if hexSanitized.count == 3 {
            let chars = Array(hexSanitized)
            hexSanitized = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
        }

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    public var nsColor: NSColor {
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        return NSColor(red: resolved.redComponent, green: resolved.greenComponent,
                       blue: resolved.blueComponent, alpha: resolved.alphaComponent)
    }
}

extension NSColor {
    public var perceivedBrightness: CGFloat {
        let srgb = usingColorSpace(.sRGB) ?? self
        return 0.299 * srgb.redComponent + 0.587 * srgb.greenComponent + 0.114 * srgb.blueComponent
    }

    public func blended(with fraction: CGFloat, of other: NSColor) -> NSColor? {
        blended(withFraction: fraction, of: other)
    }
}
