import Foundation

/// Converts queries like `3 GB in MB`, `100 f to c` or `90 min in h`.
///
/// Data units follow macOS: `GB` is 10⁹ bytes, `GiB` is 2³⁰. A capitalized prefix with a
/// lowercase `b` (`Mb`, `Gb`) means bits; other spellings (`mb`, `MB`) mean bytes.
public enum UnitConverter {
    public struct Conversion: Sendable, Equatable {
        public let value: Double
        public let unit: String
        public let result: Double
        public let targetUnit: String
    }

    private static let separators = [" in ", " to ", " as ", " -> ", " => ", " = "]

    public static func convert(_ text: String) -> Conversion? {
        let text = text.trimmingCharacters(in: .whitespaces)
        // Try each separator position from the right, so `3 in in cm` reads as inches to cm.
        var splits: [Range<String.Index>] = []
        for separator in separators {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: separator, options: .caseInsensitive, range: searchRange) {
                splits.append(found)
                searchRange = text.index(after: found.lowerBound)..<text.endIndex
            }
        }
        for split in splits.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            let source = String(text[..<split.lowerBound])
            let target = String(text[split.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard let (value, unitName) = amount(source),
                  let unit = unit(named: unitName), let targetUnit = Self.unit(named: target),
                  unit.kind == targetUnit.kind else { continue }
            let result = targetUnit.fromBase(unit.toBase(value))
            guard result.isFinite else { return nil }
            return Conversion(value: value, unit: unitName, result: result, targetUnit: target)
        }
        return nil
    }

    /// `"3.5 GB"` or `"3.5GB"` → (3.5, "GB").
    private static func amount(_ text: String) -> (Double, String)? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let match = text.firstMatch(of: /^([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*(\S.*)$/),
              let value = Double(match.1) else { return nil }
        return (value, String(match.2))
    }

    /// A unit as a linear map to its kind's base unit (bytes, meters, kilograms, liters,
    /// kelvin, seconds, m/s, m², joules, radians). Exact factors; Foundation's are rounded.
    struct Unit: Sendable, Equatable {
        enum Kind: Sendable { case data, length, mass, volume, temperature, time, speed, area, energy, angle }
        let kind: Kind
        let factor: Double
        var offset = 0.0

        func toBase(_ value: Double) -> Double { value * factor + offset }
        func fromBase(_ value: Double) -> Double { (value - offset) / factor }
    }

    static func unit(named name: String) -> Unit? {
        let name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return caseSensitiveUnits[name] ?? units[name.lowercased()]
    }

    private static let caseSensitiveUnits: [String: Unit] = [
        "B": Unit(kind: .data, factor: 1),
        "b": Unit(kind: .data, factor: 1.0 / 8),
        "Kb": Unit(kind: .data, factor: 1e3 / 8),
        "Mb": Unit(kind: .data, factor: 1e6 / 8),
        "Gb": Unit(kind: .data, factor: 1e9 / 8),
        "Tb": Unit(kind: .data, factor: 1e12 / 8),
        "K": Unit(kind: .temperature, factor: 1),
    ]

    private static let units: [String: Unit] = {
        var table: [String: Unit] = [:]
        func add(_ kind: Unit.Kind, _ factor: Double, offset: Double = 0, _ names: String...) {
            for name in names { table[name] = Unit(kind: kind, factor: factor, offset: offset) }
        }
        let pound = 0.45359237, inch = 0.0254, mile = 1609.344
        let gallon = 3.785411784, fluidOunce = gallon / 128

        // Data, in bytes
        add(.data, 1, "byte", "bytes")
        add(.data, 1e3, "kb", "kilobyte", "kilobytes")
        add(.data, 1e6, "mb", "megabyte", "megabytes")
        add(.data, 1e9, "gb", "gigabyte", "gigabytes")
        add(.data, 1e12, "tb", "terabyte", "terabytes")
        add(.data, 1e15, "pb", "petabyte", "petabytes")
        add(.data, 0x1p10, "kib", "kibibyte", "kibibytes")
        add(.data, 0x1p20, "mib", "mebibyte", "mebibytes")
        add(.data, 0x1p30, "gib", "gibibyte", "gibibytes")
        add(.data, 0x1p40, "tib", "tebibyte", "tebibytes")
        add(.data, 1.0 / 8, "bit", "bits")
        add(.data, 1e3 / 8, "kbit", "kilobit", "kilobits")
        add(.data, 1e6 / 8, "mbit", "megabit", "megabits")
        add(.data, 1e9 / 8, "gbit", "gigabit", "gigabits")
        // Length, in meters
        add(.length, 1e-9, "nm", "nanometer", "nanometers", "nanometre", "nanometres")
        add(.length, 1e-6, "µm", "um", "micrometer", "micrometers", "micron", "microns")
        add(.length, 1e-3, "mm", "millimeter", "millimeters", "millimetre", "millimetres")
        add(.length, 1e-2, "cm", "centimeter", "centimeters", "centimetre", "centimetres")
        add(.length, 1, "m", "meter", "meters", "metre", "metres")
        add(.length, 1e3, "km", "kilometer", "kilometers", "kilometre", "kilometres")
        add(.length, inch, "in", "inch", "inches", "\"")
        add(.length, inch * 12, "ft", "foot", "feet", "'")
        add(.length, inch * 36, "yd", "yard", "yards")
        add(.length, mile, "mi", "mile", "miles")
        add(.length, 1852, "nmi", "nautical mile", "nautical miles")
        // Mass, in kilograms
        add(.mass, 1e-6, "mg", "milligram", "milligrams")
        add(.mass, 1e-3, "g", "gram", "grams")
        add(.mass, 1, "kg", "kilo", "kilos", "kilogram", "kilograms")
        add(.mass, 1e3, "t", "tonne", "tonnes")
        add(.mass, pound / 16, "oz", "ounce", "ounces")
        add(.mass, pound, "lb", "lbs", "pound", "pounds")
        add(.mass, pound * 14, "st", "stone", "stones")
        // Volume, in liters (US customary)
        add(.volume, 1e-3, "ml", "milliliter", "milliliters", "millilitre", "millilitres")
        add(.volume, 1e-2, "cl", "centiliter", "centiliters")
        add(.volume, 1e-1, "dl", "deciliter", "deciliters")
        add(.volume, 1, "l", "liter", "liters", "litre", "litres")
        add(.volume, 1e3, "m3", "m³", "cubic meter", "cubic meters")
        add(.volume, fluidOunce / 6, "tsp", "teaspoon", "teaspoons")
        add(.volume, fluidOunce / 2, "tbsp", "tablespoon", "tablespoons")
        add(.volume, fluidOunce, "fl oz", "floz", "fluid ounce", "fluid ounces")
        add(.volume, fluidOunce * 8, "cup", "cups")
        add(.volume, fluidOunce * 16, "pt", "pint", "pints")
        add(.volume, fluidOunce * 32, "qt", "quart", "quarts")
        add(.volume, gallon, "gal", "gallon", "gallons")
        // Temperature, in kelvin
        add(.temperature, 1, offset: 273.15, "c", "°c", "celsius")
        add(.temperature, 5.0 / 9, offset: 459.67 * 5 / 9, "f", "°f", "fahrenheit")
        add(.temperature, 1, "kelvin")
        // Time, in seconds
        add(.time, 1e-3, "ms", "millisecond", "milliseconds")
        add(.time, 1, "s", "sec", "secs", "second", "seconds")
        add(.time, 60, "min", "mins", "minute", "minutes")
        add(.time, 3600, "h", "hr", "hrs", "hour", "hours")
        add(.time, 86_400, "d", "day", "days")
        add(.time, 604_800, "wk", "week", "weeks")
        add(.time, 31_557_600, "yr", "yrs", "year", "years")
        // Speed, in meters per second
        add(.speed, 1 / 3.6, "km/h", "kmh", "kph")
        add(.speed, mile / 3600, "mph", "mi/h")
        add(.speed, 1, "m/s")
        add(.speed, 1852.0 / 3600, "kn", "kt", "knot", "knots")
        // Area, in square meters
        add(.area, 1, "m2", "m²", "sq m", "square meter", "square meters")
        add(.area, 1e6, "km2", "km²", "sq km", "square kilometer", "square kilometers")
        add(.area, (inch * 12) * (inch * 12), "ft2", "ft²", "sq ft", "square foot", "square feet")
        add(.area, mile * mile, "mi2", "mi²", "sq mi", "square mile", "square miles")
        add(.area, 4046.8564224, "ac", "acre", "acres")
        add(.area, 1e4, "ha", "hectare", "hectares")
        // Energy, in joules
        add(.energy, 1, "j", "joule", "joules")
        add(.energy, 1e3, "kj", "kilojoule", "kilojoules")
        add(.energy, 4.184, "cal", "calorie", "calories")
        add(.energy, 4184, "kcal", "kilocalorie", "kilocalories")
        add(.energy, 3.6e6, "kwh", "kilowatt hour", "kilowatt hours")
        // Angle, in radians
        add(.angle, .pi / 180, "deg", "°", "degree", "degrees")
        add(.angle, 1, "rad", "radian", "radians")
        return table
    }()
}
