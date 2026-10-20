import Testing
import Foundation
@testable import ReadinessEngine

private let paris = TimeZone(identifier: "Europe/Paris")!
private let utc = TimeZone(identifier: "UTC")!
private func d(_ s: String) -> DayKey { DayKey(s)! }
private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func formatsAndParsesISODay() {
    #expect(d("2026-10-19").description == "2026-10-19")
    #expect(DayKey(year: 2026, month: 3, day: 5)?.description == "2026-03-05")
}

@Test(arguments: ["2026-02-30", "2026-13-01", "2026-1-05", "26-10-19", "2026/10/19", "", "abcd-ef-gh"])
func rejectsInvalidStrings(_ s: String) { #expect(DayKey(s) == nil) }

@Test func advancesAcrossMonthYearAndLeapDay() {
    #expect(d("2026-12-31").advanced(by: 1) == d("2027-01-01"))
    #expect(d("2028-02-28").advanced(by: 1) == d("2028-02-29"))
    #expect(d("2027-02-28").advanced(by: 1) == d("2027-03-01"))
    #expect(d("2026-10-19").advanced(by: -19) == d("2026-09-30"))
}

@Test func dayFromDateUsesGivenTimeZone() {
    let instant = iso("2026-10-18T22:30:00Z")
    #expect(DayKey(date: instant, timeZone: paris) == d("2026-10-19"))
    #expect(DayKey(date: instant, timeZone: utc) == d("2026-10-18"))
}

@Test func startDateHandlesDSTDay() {
    // 2026-03-29: EU switch to summer time, the day lasts 23 h.
    let start = d("2026-03-29").startDate(in: paris)
    #expect(start == iso("2026-03-28T23:00:00Z"))
    #expect(d("2026-03-30").startDate(in: paris).timeIntervalSince(start) == 23 * 3600)
}

@Test func rangeIsInclusiveAndEmptyWhenReversed() {
    #expect(d("2026-10-17").range(to: d("2026-10-19")) == [d("2026-10-17"), d("2026-10-18"), d("2026-10-19")])
    #expect(d("2026-10-19").range(to: d("2026-10-17")).isEmpty)
}

@Test func codableRoundTripsAsString() throws {
    let data = try JSONEncoder().encode(d("2026-10-19"))
    #expect(String(decoding: data, as: UTF8.self) == "\"2026-10-19\"")
    #expect(try JSONDecoder().decode(DayKey.self, from: data) == d("2026-10-19"))
    #expect(throws: (any Error).self) { try JSONDecoder().decode(DayKey.self, from: Data("\"2026-02-30\"".utf8)) }
}

@Test func ordersChronologically() {
    #expect(d("2026-09-30") < d("2026-10-01"))
    #expect(d("2026-12-31") < d("2027-01-01"))
}
