import Foundation
import ReadinessEngine

struct ProbeSleepRecord {
    let end: Date
    let hasStage: Bool   // core, deep or REM
}

struct ProbeSourceCount: Equatable {
    let name: String
    let bundleID: String
    let count: Int
}

struct ProbeWorkoutCandidate {
    let id: UUID
    let bundleID: String
    let name: String
    let hasEffort: Bool
}

enum ProbeCounting {
    static func workoutForEffortTest(_ candidates: [ProbeWorkoutCandidate]) -> UUID? {
        nil
    }

    /// Number of distinct local days (by sample end) that have at least one staged sleep sample.
    static func nightsWithStages(_ records: [ProbeSleepRecord], timeZone: TimeZone) -> Int {
        Set(records.filter(\.hasStage).map { DayKey(date: $0.end, timeZone: timeZone) }).count
    }

    /// Workouts grouped by source bundle ID, sorted by count (descending) then name (ascending).
    static func workoutsBySource(_ sources: [(bundleID: String, name: String)]) -> [ProbeSourceCount] {
        var counts: [String: (name: String, count: Int)] = [:]
        for source in sources {
            counts[source.bundleID, default: (source.name, 0)].count += 1
        }
        return counts
            .map { ProbeSourceCount(name: $0.value.name, bundleID: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    static func isWorkOutDoors(bundleID: String, name: String) -> Bool {
        bundleID.lowercased().contains("workoutdoors") || name.lowercased().contains("workoutdoors")
    }
}
