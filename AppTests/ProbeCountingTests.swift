import Testing
import Foundation
@testable import Readiness

private let paris = TimeZone(identifier: "Europe/Paris")!
private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func countsDistinctNightsWithStagesInLocalTime() {
    let records = [
        ProbeSleepRecord(end: iso("2026-10-19T05:10:00Z"), hasStage: true),
        ProbeSleepRecord(end: iso("2026-10-19T05:40:00Z"), hasStage: true),   // same night
        ProbeSleepRecord(end: iso("2026-10-18T23:30:00Z"), hasStage: true),   // 01:30 in Paris → 10/19, same night
        ProbeSleepRecord(end: iso("2026-10-18T05:00:00Z"), hasStage: false),  // no stage: ignored
        ProbeSleepRecord(end: iso("2026-10-17T05:00:00Z"), hasStage: true),
    ]
    #expect(ProbeCounting.nightsWithStages(records, timeZone: paris) == 2)
}

@Test func groupsWorkoutsBySourceSortedByCount() {
    let result = ProbeCounting.workoutsBySource([
        ("com.example.healthfit", "HealthFit"), ("com.example.wod", "WorkOutDoors"),
        ("com.example.wod", "WorkOutDoors"), ("com.apple.health.x", "Exercice"),
    ])
    #expect(result == [
        ProbeSourceCount(name: "WorkOutDoors", bundleID: "com.example.wod", count: 2),
        ProbeSourceCount(name: "Exercice", bundleID: "com.apple.health.x", count: 1),
        ProbeSourceCount(name: "HealthFit", bundleID: "com.example.healthfit", count: 1),
    ])
}

@Test func recognisesWorkOutDoorsByNameOrBundle() {
    #expect(ProbeCounting.isWorkOutDoors(bundleID: "com.x.app", name: "WorkOutDoors"))
    #expect(ProbeCounting.isWorkOutDoors(bundleID: "net.y.WORKOUTDOORS", name: "Autre"))
    #expect(!ProbeCounting.isWorkOutDoors(bundleID: "com.z.healthfit", name: "HealthFit"))
}
