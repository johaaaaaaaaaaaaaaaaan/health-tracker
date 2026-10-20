import Foundation
import HealthKit
import Observation

struct ProbeReport {
    var healthDataAvailable = HKHealthStore.isHealthDataAvailable()
    var appGroupContainerOK = false
    var authorizationError: String?
    var hrvSDNN = 0
    var heartbeatSeries = 0
    var nightsWithStages = 0
    var routes = 0
    var effortSamples = 0
    var workoutsBySource: [ProbeSourceCount] = []
    var effortWrite: EffortWriteOutcome?
}

enum EffortWriteOutcome: Equatable {
    case noWorkOutDoorsWorkout
    case success(path: String, readBack: Bool, deleted: Bool)   // path: "A" (relate directly) or "B" (save then relate)
    case failed(step: String, code: Int, message: String)
}

/// Step 0 probe: proves HealthKit works in a sideloaded build and tests writing an RPE
/// onto a workout recorded by another app (WorkOutDoors).
@MainActor @Observable
final class HealthKitProbe {
    private(set) var report = ProbeReport()
    private(set) var isRunning = false
    private let store = HKHealthStore()

    init() {
        let groupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? ""
        report.appGroupContainerOK = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    func requestAuthorization() async {
        isRunning = true
        defer { isRunning = false }
        do {
            try await store.requestAuthorization(toShare: HealthKitTypes.probeShare, read: HealthKitTypes.probeRead)
            report.authorizationError = nil
        } catch {
            report.authorizationError = Self.describe(error)
        }
    }

    func refreshCounts(days: Int = 7) async {
        isRunning = true
        defer { isRunning = false }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)!
        let range = HKQuery.predicateForSamples(withStart: start, end: end)
        do {
            report.hrvSDNN = try await count(HKQuantityType(.heartRateVariabilitySDNN), range)
            report.heartbeatSeries = try await count(HKSeriesType.heartbeat(), range)
            report.routes = try await count(HKSeriesType.workoutRoute(), range)
            report.effortSamples = try await count(HKQuantityType(.workoutEffortScore), range)

            let sleep = try await HKSampleQueryDescriptor(
                predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: range)],
                sortDescriptors: []).result(for: store)
            let stages: Set<Int> = [HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                    HKCategoryValueSleepAnalysis.asleepREM.rawValue]
            let records = sleep.map { sample in
                ProbeSleepRecord(end: sample.endDate, hasStage: stages.contains(sample.value))
            }
            report.nightsWithStages = ProbeCounting.nightsWithStages(records, timeZone: .current)

            let workouts = try await HKSampleQueryDescriptor(
                predicates: [.workout(range)], sortDescriptors: []).result(for: store)
            report.workoutsBySource = ProbeCounting.workoutsBySource(workouts.map {
                ($0.sourceRevision.source.bundleIdentifier, $0.sourceRevision.source.name)
            })
        } catch {
            report.authorizationError = Self.describe(error)
        }
    }

    func runEffortWriteTest() async {
        isRunning = true
        defer { isRunning = false }
        report.effortWrite = await effortWriteTest()
    }

    private func effortWriteTest() async -> EffortWriteOutcome {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end)!
        let workouts: [HKWorkout]
        do {
            workouts = try await HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)]).result(for: store)
        } catch {
            return Self.failure("find workout", error)
        }
        // Skip workouts that already have an effort, so the test never touches a workout the user rated.
        var candidates: [ProbeWorkoutCandidate] = []
        for workout in workouts {
            let source = workout.sourceRevision.source
            guard ProbeCounting.isWorkOutDoors(bundleID: source.bundleIdentifier, name: source.name) else { continue }
            let hasEffort: Bool
            do {
                hasEffort = try await relatedEfforts(of: workout).isEmpty == false
            } catch {
                return Self.failure("check existing effort", error)
            }
            candidates.append(ProbeWorkoutCandidate(id: workout.uuid, bundleID: source.bundleIdentifier,
                                                    name: source.name, hasEffort: hasEffort))
            if !hasEffort { break }
        }
        guard let id = ProbeCounting.workoutForEffortTest(candidates),
              let workout = workouts.first(where: { $0.uuid == id }) else { return .noWorkOutDoorsWorkout }

        let sample = HKQuantitySample(
            type: HKQuantityType(.workoutEffortScore),
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: 5),
            start: workout.startDate, end: workout.endDate,
            metadata: ["FormeDuJourProbe": "1"])

        let outcome: EffortWriteOutcome
        var path = "A"
        var pathAError: Error?
        do {
            do {
                try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
            } catch {
                path = "B"
                pathAError = error
                try await store.save(sample)
                try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
            }
            let readBack = try await relatedEfforts(of: workout).contains { $0.uuid == sample.uuid }
            outcome = .success(path: path, readBack: readBack, deleted: false)
        } catch {
            let step = path == "A" ? "relate (A)" : "save/relate (B), A: \(pathAError.map(Self.describe) ?? "-")"
            outcome = Self.failure(step, error)
        }

        // Always clean up, on every path: delete only the instance created above, never by predicate,
        // so the user's real RPEs stay untouched. Deleting a sample that was never saved fails harmlessly.
        let deleted = (try? await store.delete(sample)) != nil
        switch outcome {
        case let .success(path, readBack, _): return .success(path: path, readBack: readBack, deleted: deleted)
        case let .failed(step, code, message): return .failed(step: step, code: code, message: message + (deleted ? " · test sample deleted" : " · nothing to delete"))
        case .noWorkOutDoorsWorkout: return outcome
        }
    }

    private func relatedEfforts(of workout: HKWorkout) async throws -> [HKQuantitySample] {
        try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.workoutEffortScore),
                                         predicate: HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil))],
            sortDescriptors: []).result(for: store)
    }

    private func count(_ type: HKSampleType, _ predicate: NSPredicate) async throws -> Int {
        try await HKSampleQueryDescriptor(predicates: [.sample(type: type, predicate: predicate)],
                                          sortDescriptors: []).result(for: store).count
    }

    private static func failure(_ step: String, _ error: Error) -> EffortWriteOutcome {
        let ns = error as NSError
        return .failed(step: step, code: ns.code, message: ns.localizedDescription)
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }
}
