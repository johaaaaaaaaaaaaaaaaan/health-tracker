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
    /// Most recent WorkOutDoors workout that has no effort yet, so the test never touches a workout the user rated.
    /// `candidates` must be sorted most recent first.
    static func workoutForEffortTest(_ candidates: [ProbeWorkoutCandidate]) -> UUID? {
        candidates.first { isWorkOutDoors(bundleID: $0.bundleID, name: $0.name) && !$0.hasEffort }?.id
    }

    /// Number of distinct nights with at least one staged sleep sample. A sample ending at or after 15:00 local
    /// belongs to the next day's night (SPEC §8.2: the main sleep of day J ends in [J 03:00, J 15:00[).
    static func nightsWithStages(_ records: [ProbeSleepRecord], timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return Set(records.filter(\.hasStage).map { record in
            let day = DayKey(date: record.end, timeZone: timeZone)
            return calendar.component(.hour, from: record.end) >= 15 ? day.advanced(by: 1) : day
        }).count
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
