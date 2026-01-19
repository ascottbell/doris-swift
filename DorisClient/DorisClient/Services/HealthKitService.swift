import Foundation
import HealthKit

/// Service for accessing Apple HealthKit data and syncing to Doris server
class HealthKitService {

    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()

    // MARK: - Data Types

    /// Health data types we want to read
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        // Activity
        if let stepCount = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepCount)
        }
        if let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let standTime = HKQuantityType.quantityType(forIdentifier: .appleStandTime) {
            types.insert(standTime)
        }

        // Heart
        if let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }

        // Cardio Fitness
        if let vo2max = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            types.insert(vo2max)
        }

        // Sleep
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }

        // Workouts
        types.insert(HKObjectType.workoutType())

        return types
    }

    // MARK: - Authorization

    /// Check if HealthKit is available on this device
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Request authorization to read health data
    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Check if we have authorization for required types
    func checkAuthorization() -> Bool {
        guard isAvailable else { return false }

        // Check step count as a proxy for general authorization
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return false
        }

        let status = healthStore.authorizationStatus(for: stepType)
        return status == .sharingAuthorized
    }

    // MARK: - Data Queries

    /// Get today's health summary (resilient - returns whatever data is available)
    func getTodaysSummary() async -> HealthSummary {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: startOfDay)!

        // Query each metric independently - don't fail if one is missing
        let steps = (try? await getSteps(from: startOfDay, to: now)) ?? 0
        let activeCalories = (try? await getActiveCalories(from: startOfDay, to: now)) ?? 0
        let standHours = (try? await getStandHours(from: startOfDay, to: now)) ?? 0
        let restingHR = try? await getRestingHeartRate(from: startOfDay, to: now)
        let hrv = try? await getHRV(from: yesterdayStart, to: now)
        let vo2max = try? await getVO2Max()
        let sleepData = try? await getSleepData(from: yesterdayStart, to: startOfDay)
        let workouts = (try? await getWorkouts(from: startOfDay, to: now)) ?? []

        return HealthSummary(
            date: formatDate(now),
            steps: steps,
            activeCalories: activeCalories,
            standHours: standHours,
            restingHR: restingHR,
            hrv: hrv,
            vo2max: vo2max,
            sleepHours: sleepData?.totalHours,
            sleepStages: sleepData?.stages,
            workouts: workouts
        )
    }

    /// Get health summary for a specific date
    func getSummary(for date: Date) async throws -> HealthSummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // For sleep, look at the night before
        let sleepStart = calendar.date(byAdding: .day, value: -1, to: startOfDay)!

        async let steps = getSteps(from: startOfDay, to: endOfDay)
        async let activeCalories = getActiveCalories(from: startOfDay, to: endOfDay)
        async let standHours = getStandHours(from: startOfDay, to: endOfDay)
        async let restingHR = getRestingHeartRate(from: startOfDay, to: endOfDay)
        async let hrv = getHRV(from: startOfDay, to: endOfDay)
        async let vo2max = getVO2Max()
        async let sleepData = getSleepData(from: sleepStart, to: startOfDay)
        async let workouts = getWorkouts(from: startOfDay, to: endOfDay)

        let sleep = try await sleepData
        return try await HealthSummary(
            date: formatDate(date),
            steps: steps,
            activeCalories: activeCalories,
            standHours: standHours,
            restingHR: restingHR,
            hrv: hrv,
            vo2max: vo2max,
            sleepHours: sleep?.totalHours,
            sleepStages: sleep?.stages,
            workouts: workouts
        )
    }

    // MARK: - Individual Queries

    private func getSteps(from start: Date, to end: Date) async throws -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return 0
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }

            healthStore.execute(query)
        }
    }

    private func getActiveCalories(from start: Date, to end: Date) async throws -> Int {
        guard let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return 0
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: calorieType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let calories = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: Int(calories))
            }

            healthStore.execute(query)
        }
    }

    private func getStandHours(from start: Date, to end: Date) async throws -> Int {
        guard let standType = HKQuantityType.quantityType(forIdentifier: .appleStandTime) else {
            return 0
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: standType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                // Stand time is in minutes, convert to hours
                let minutes = result?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                continuation.resume(returning: Int(minutes / 60))
            }

            healthStore.execute(query)
        }
    }

    private func getRestingHeartRate(from start: Date, to end: Date) async throws -> Int? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let bpm = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                continuation.resume(returning: Int(bpm))
            }

            healthStore.execute(query)
        }
    }

    private func getHRV(from start: Date, to end: Date) async throws -> Int? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let ms = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: Int(ms))
            }

            healthStore.execute(query)
        }
    }

    private func getVO2Max() async throws -> Double? {
        guard let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: vo2Type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                // VO2 Max in mL/(kg·min)
                let vo2 = sample.quantity.doubleValue(for: HKUnit(from: "mL/kg*min"))
                continuation.resume(returning: vo2)
            }

            healthStore.execute(query)
        }
    }

    private func getSleepData(from start: Date, to end: Date) async throws -> SleepData? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                var totalSeconds: Double = 0
                var coreSeconds: Double = 0
                var deepSeconds: Double = 0
                var remSeconds: Double = 0

                for sample in sleepSamples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        coreSeconds += duration
                        totalSeconds += duration
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deepSeconds += duration
                        totalSeconds += duration
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        remSeconds += duration
                        totalSeconds += duration
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        // Generic asleep (older data or non-Watch)
                        totalSeconds += duration
                    default:
                        break // Ignore inBed, awake, etc.
                    }
                }

                guard totalSeconds > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let stages = SleepStages(
                    coreHours: coreSeconds / 3600,
                    deepHours: deepSeconds / 3600,
                    remHours: remSeconds / 3600
                )

                continuation.resume(returning: SleepData(
                    totalHours: totalSeconds / 3600,
                    stages: (coreSeconds + deepSeconds + remSeconds > 0) ? stages : nil
                ))
            }

            healthStore.execute(query)
        }
    }

    private func getWorkouts(from start: Date, to end: Date) async throws -> [WorkoutSummary] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let summaries = workouts.map { workout -> WorkoutSummary in
                    // Get calories from statistics (new API)
                    var calories = 0
                    if let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
                       let stats = workout.statistics(for: calorieType),
                       let sum = stats.sumQuantity() {
                        calories = Int(sum.doubleValue(for: .kilocalorie()))
                    }

                    return WorkoutSummary(
                        type: HealthKitService.workoutTypeName(workout.workoutActivityType),
                        durationMinutes: Int(workout.duration / 60),
                        distanceMiles: workout.totalDistance?.doubleValue(for: .mile()),
                        calories: calories
                    )
                }

                continuation.resume(returning: summaries)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .cycling: return "cycling"
        case .walking: return "walking"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stairs"
        case .crossTraining: return "cross_training"
        case .mixedCardio: return "cardio"
        case .coreTraining: return "core"
        case .flexibility: return "flexibility"
        case .dance: return "dance"
        case .pilates: return "pilates"
        case .golf: return "golf"
        case .tennis: return "tennis"
        case .basketball: return "basketball"
        case .soccer: return "soccer"
        default: return "other"
        }
    }
}

// MARK: - Data Models

struct HealthSummary: Codable {
    let date: String
    let steps: Int
    let activeCalories: Int
    let standHours: Int
    let restingHR: Int?
    let hrv: Int?  // Heart rate variability in ms
    let vo2max: Double?  // mL/(kg·min)
    let sleepHours: Double?
    let sleepStages: SleepStages?
    let workouts: [WorkoutSummary]

    enum CodingKeys: String, CodingKey {
        case date
        case steps
        case activeCalories = "active_calories"
        case standHours = "stand_hours"
        case restingHR = "resting_hr"
        case hrv
        case vo2max = "vo2_max"
        case sleepHours = "sleep_hours"
        case sleepStages = "sleep_stages"
        case workouts
    }
}

struct SleepData {
    let totalHours: Double
    let stages: SleepStages?
}

struct SleepStages: Codable {
    let coreHours: Double
    let deepHours: Double
    let remHours: Double

    enum CodingKeys: String, CodingKey {
        case coreHours = "core_hours"
        case deepHours = "deep_hours"
        case remHours = "rem_hours"
    }
}

struct WorkoutSummary: Codable {
    let type: String
    let durationMinutes: Int
    let distanceMiles: Double?
    let calories: Int

    enum CodingKeys: String, CodingKey {
        case type
        case durationMinutes = "duration_min"
        case distanceMiles = "distance_mi"
        case calories
    }
}

// MARK: - Errors

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case notAuthorized
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .queryFailed(let message):
            return "Health data query failed: \(message)"
        }
    }
}
