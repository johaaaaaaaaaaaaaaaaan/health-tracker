import HealthKit

enum HealthKitTypes {
    static var probeRead: Set<HKObjectType> {
        [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKSeriesType.heartbeat(),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.workoutEffortScore),
            HKQuantityType(.estimatedWorkoutEffortScore),
        ]
    }

    static var probeShare: Set<HKSampleType> {
        [HKQuantityType(.workoutEffortScore)]
    }
}
