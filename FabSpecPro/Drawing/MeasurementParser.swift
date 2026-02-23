import Foundation

enum MeasurementParser {
    static func parseInches(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if let value = Double(trimmed) {
            return value
        }

        let normalized = trimmed.replacingOccurrences(of: "-", with: " ")
        let parts = normalized.split(separator: " ")

        if parts.count == 2 {
            if let whole = Double(parts[0]), let fraction = fractionValue(String(parts[1])) {
                return whole + fraction
            }
        } else if parts.count == 1 {
            if let fraction = fractionValue(String(parts[0])) {
                return fraction
            }
        }

        return nil
    }

    private static func fractionValue(_ raw: String) -> Double? {
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              let numerator = Double(parts[0]),
              let denominator = Double(parts[1]),
              denominator != 0 else {
            return nil
        }
        return numerator / denominator
    }

    static func formatInches(_ value: Double) -> String {
        let components = fractionalComponents(value, denominator: 16)
        return formatFractional(whole: components.whole, numerator: components.numerator, denominator: components.denominator, isNegative: components.isNegative)
    }

    static func fractionalComponents(_ value: Double, denominator: Int) -> (whole: Int, numerator: Int, denominator: Int, isNegative: Bool) {
        let isNegative = value < 0
        let absValue = abs(value)
        var whole = Int(floor(absValue))
        let fraction = absValue - Double(whole)
        var numerator = Int(round(fraction * Double(denominator)))

        if numerator == denominator {
            whole += 1
            numerator = 0
        }

        let reduced = reducedFraction(numerator: numerator, denominator: denominator)
        return (whole, reduced.numerator, reduced.denominator, isNegative)
    }

    static func reducedFraction(numerator: Int, denominator: Int) -> (numerator: Int, denominator: Int) {
        guard numerator != 0 else { return (0, denominator) }
        let divisor = gcd(abs(numerator), denominator)
        return (numerator / divisor, denominator / divisor)
    }

    static func formatFractional(whole: Int, numerator: Int, denominator: Int, isNegative: Bool) -> String {
        let signPrefix = isNegative ? "-" : ""
        if numerator == 0 {
            return "\(signPrefix)\(whole)"
        }
        if whole == 0 {
            return "\(signPrefix)\(numerator)/\(denominator)"
        }
        return "\(signPrefix)\(whole) \(numerator)/\(denominator)"
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            let remainder = x % y
            x = y
            y = remainder
        }
        return x
    }
}
