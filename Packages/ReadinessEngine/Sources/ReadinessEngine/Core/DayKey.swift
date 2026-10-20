import Foundation

/// A local calendar day, "YYYY-MM-DD". Always computed in an explicit time zone.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns nil when the date does not exist (e.g. 2026-02-30).
    public init?(year: Int, month: Int, day: Int) {
        let cal = Self.calendar(TimeZone(identifier: "UTC")!)
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
        let c = cal.dateComponents([.year, .month, .day], from: date)
        guard c.year == year, c.month == month, c.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Accepts exactly "YYYY-MM-DD".
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(date: Date, timeZone: TimeZone) {
        let c = Self.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    public var description: String {
        let y = String(year), m = String(month), d = String(day)
        return String(repeating: "0", count: max(0, 4 - y.count)) + y + "-"
            + (m.count < 2 ? "0" : "") + m + "-" + (d.count < 2 ? "0" : "") + d
    }

    /// Day arithmetic anchored at noon UTC, so it is unaffected by DST.
    public func advanced(by days: Int) -> DayKey {
        let cal = Self.calendar(TimeZone(identifier: "UTC")!)
        let noon = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return DayKey(date: cal.date(byAdding: .day, value: days, to: noon)!, timeZone: cal.timeZone)
    }

    /// Inclusive range; empty when `end` precedes `self`.
    public func range(to end: DayKey) -> [DayKey] {
        var result: [DayKey] = []
        var current = self
        while current <= end {
            result.append(current)
            current = current.advanced(by: 1)
        }
        return result
    }

    /// Local midnight of this day in `timeZone`.
    public func startDate(in timeZone: TimeZone) -> Date {
        let cal = Self.calendar(timeZone)
        let noon = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return cal.startOfDay(for: noon)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let key = DayKey(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid day \"\(string)\"")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }
}
