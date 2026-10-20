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

@Test func nightCrossingMidnightCountsOnce() {
    let records = [
        ProbeSleepRecord(end: iso("2026-10-18T21:30:00Z"), hasStage: true),   // 23:30 in Paris, night of 10/19
        ProbeSleepRecord(end: iso("2026-10-19T05:10:00Z"), hasStage: true),   // 07:10 in Paris, same night
        ProbeSleepRecord(end: iso("2026-10-19T12:00:00Z"), hasStage: true),   // 14:00 in Paris, still 10/19
    ]
    #expect(ProbeCounting.nightsWithStages(records, timeZone: paris) == 1)
}

@Test func effortTestPicksLatestWorkOutDoorsWorkoutWithoutExistingEffort() {
    let rated = UUID(), unrated = UUID(), other = UUID()
    let candidates = [   // most recent first
        ProbeWorkoutCandidate(id: other, bundleID: "com.z.healthfit", name: "HealthFit", hasEffort: false),
        ProbeWorkoutCandidate(id: rated, bundleID: "com.x.wod", name: "WorkOutDoors", hasEffort: true),
        ProbeWorkoutCandidate(id: unrated, bundleID: "com.x.wod", name: "WorkOutDoors", hasEffort: false),
    ]
    #expect(ProbeCounting.workoutForEffortTest(candidates) == unrated)
    #expect(ProbeCounting.workoutForEffortTest(Array(candidates.prefix(2))) == nil)
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
