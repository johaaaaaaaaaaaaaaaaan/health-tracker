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

enum ProbeCounting {
    static func nightsWithStages(_ records: [ProbeSleepRecord], timeZone: TimeZone) -> Int {
        0
    }

    static func workoutsBySource(_ sources: [(bundleID: String, name: String)]) -> [ProbeSourceCount] {
        []
    }

    static func isWorkOutDoors(bundleID: String, name: String) -> Bool {
        false
    }
}
