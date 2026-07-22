import Foundation

struct HSBColorSelection: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = Self.clamp(hue)
        self.saturation = Self.clamp(saturation)
        self.brightness = Self.clamp(brightness)
    }

    init(token: String) {
        let rgb = TaskChannelRGB.resolve(token)
            ?? TaskChannelRGB.resolve(DailyProgressPreferences.defaultColorToken)
            ?? TaskChannelRGB(red: 85, green: 201, blue: 135)
        self = Self(rgb: rgb)
    }

    var encodedToken: String {
        let huePosition = (hue - floor(hue)) * 6
        let chroma = brightness * saturation
        let intermediate = chroma * (1 - abs(huePosition.truncatingRemainder(dividingBy: 2) - 1))
        let base: (Double, Double, Double) = switch huePosition {
        case 0..<1: (chroma, intermediate, 0)
        case 1..<2: (intermediate, chroma, 0)
        case 2..<3: (0, chroma, intermediate)
        case 3..<4: (0, intermediate, chroma)
        case 4..<5: (intermediate, 0, chroma)
        default: (chroma, 0, intermediate)
        }
        let match = brightness - chroma
        return TaskChannelRGB(
            red: Int(((base.0 + match) * 255).rounded()),
            green: Int(((base.1 + match) * 255).rounded()),
            blue: Int(((base.2 + match) * 255).rounded())
        ).encodedColorName
    }

    private init(rgb: TaskChannelRGB) {
        let red = Double(rgb.red) / 255
        let green = Double(rgb.green) / 255
        let blue = Double(rgb.blue) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        let resolvedHue: Double
        if delta == 0 {
            resolvedHue = 0
        } else if maximum == red {
            resolvedHue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == green {
            resolvedHue = (((blue - red) / delta) + 2) / 6
        } else {
            resolvedHue = (((red - green) / delta) + 4) / 6
        }

        hue = resolvedHue < 0 ? resolvedHue + 1 : resolvedHue
        saturation = maximum == 0 ? 0 : delta / maximum
        brightness = maximum
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
