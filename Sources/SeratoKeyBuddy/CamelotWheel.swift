import Foundation
import SwiftUI

enum CamelotWheel {
    struct CamelotKey: Hashable, CustomStringConvertible {
        let number: Int  // 1..12
        let mode: Mode   // A = minor, B = major

        enum Mode: String { case A, B }

        var description: String { "\(number)\(mode.rawValue)" }

        // Relative key (same number, opposite mode).
        var relative: CamelotKey { CamelotKey(number: number, mode: mode == .A ? .B : .A) }

        static func + (lhs: CamelotKey, rhs: Int) -> CamelotKey {
            let newNumber = ((lhs.number - 1 + rhs) % 12 + 12) % 12 + 1
            return CamelotKey(number: newNumber, mode: lhs.mode)
        }

        static func - (lhs: CamelotKey, rhs: Int) -> CamelotKey {
            let newNumber = ((lhs.number - 1 - rhs) % 12 + 12) % 12 + 1
            return CamelotKey(number: newNumber, mode: lhs.mode)
        }
    }

    enum Compatibility: String, CaseIterable {
        case perfect = "Perfect"
        case relative = "Relative"
        case plus1 = "+1"
        case minus1 = "−1"
        case energyBoost = "Energy Boost"

        var sortRank: Int {
            switch self {
            case .perfect: return 5
            case .relative: return 4
            case .plus1: return 3
            case .minus1: return 2
            case .energyBoost: return 1
            }
        }

        var description: String {
            switch self {
            case .perfect: return "Perfect match"
            case .relative: return "Relative major/minor"
            case .plus1: return "+1 on wheel"
            case .minus1: return "−1 on wheel"
            case .energyBoost: return "Energy boost (+2)"
            }
        }
    }

    private static let majorRoots: [String: Int] = [
        "C": 8, "G": 9, "D": 10, "A": 11, "E": 12, "B": 1,
        "F#": 2, "Gb": 2, "C#": 3, "Db": 3,
        "F": 4, "Bb": 5, "A#": 5, "Eb": 6, "D#": 6, "G#": 7, "Ab": 7
    ]

    private static let minorRoots: [String: Int] = [
        "A": 8, "E": 9, "B": 10, "F#": 11, "Gb": 11,
        "C#": 12, "Db": 12, "G#": 1, "Ab": 1,
        "D#": 2, "Eb": 2, "A#": 3, "Bb": 3,
        "F": 4, "C": 5, "G": 6, "D": 7
    ]

    /// Convert a Serato key string (musical or Open Key) into Camelot notation.
    static func parse(_ key: String) -> CamelotKey? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Remove spaces so "A m" / "C #" become "Am" / "C#".
        var normalized = trimmed.replacingOccurrences(of: " ", with: "")

        // Open Key notation: "1m" / "8d" / "10A" / "10B" etc.
        if normalized.count >= 2,
           let number = Int(String(normalized.dropLast())), (1...12).contains(number) {
            let last = normalized.lowercased().last
            if last == "m" || last == "a" { return CamelotKey(number: number, mode: .A) }
            if last == "d" || last == "b" { return CamelotKey(number: number, mode: .B) }
        }

        // Strip major/minor suffixes: "C Major", "Cmaj", "Cmin", "Cminor".
        let lower = normalized.lowercased()
        var isMinor = false
        let suffixesMinor = ["minor", "min"]
        let suffixesMajor = ["major", "maj"]
        for suffix in suffixesMinor where lower.hasSuffix(suffix) {
            normalized.removeLast(suffix.count)
            isMinor = true
        }
        for suffix in suffixesMajor where normalized.lowercased().hasSuffix(suffix) {
            normalized.removeLast(suffix.count)
        }

        // Treat a trailing lowercase 'm' as minor ("Am", "C#m", "Bbm").
        if normalized.lowercased().hasSuffix("m"), normalized.count > 1 {
            isMinor = true
            normalized = String(normalized.dropLast())
        }

        // Normalize root spelling.
        let root = normalized
        if isMinor {
            if let number = minorRoots[root] ?? minorRoots[root.capitalized] {
                return CamelotKey(number: number, mode: .A)
            }
        } else {
            if let number = majorRoots[root] ?? majorRoots[root.capitalized] {
                return CamelotKey(number: number, mode: .B)
            }
        }
        return nil
    }

    /// Determine the compatibility category between two Camelot keys.
    static func compatibility(current: CamelotKey, candidate: CamelotKey) -> Compatibility? {
        if candidate == current { return .perfect }
        if candidate == current.relative { return .relative }
        if candidate == current + 1 { return .plus1 }
        if candidate == current - 1 { return .minus1 }
        if candidate == current + 2 { return .energyBoost }
        return nil
    }

    /// Return a color for a Camelot key based on its number and mode.
    static func color(for key: CamelotKey) -> Color {
        // Distribute hue evenly around the wheel. B (major) is brighter, A (minor) slightly darker.
        let hue = Double(key.number - 1) / 12.0
        let saturation = key.mode == .B ? 0.85 : 0.70
        let brightness = key.mode == .B ? 0.95 : 0.85
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}
