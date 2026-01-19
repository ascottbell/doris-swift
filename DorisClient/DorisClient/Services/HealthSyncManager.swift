import Foundation
import BackgroundTasks

/// Manages health data synchronization with Doris server
class HealthSyncManager {

    static let shared = HealthSyncManager()

    private let healthKit = HealthKitService.shared
    private let api = DorisAPIService()

    /// Background task identifier
    static let backgroundTaskIdentifier = "com.doris.healthsync"

    /// UserDefaults key for last sync date
    private let lastSyncKey = "lastHealthSyncDate"

    // MARK: - Initialization

    /// Register background task handler - call from AppDelegate or App init
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }

    /// Schedule the next background sync
    func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)

        // Schedule for early morning (6 AM) for daily sync
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 6
        components.minute = 0

        var targetDate = calendar.date(from: components)!

        // If it's already past 6 AM today, schedule for tomorrow
        if targetDate < Date() {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate)!
        }

        request.earliestBeginDate = targetDate

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[HealthSync] Scheduled background sync for \(targetDate)")
        } catch {
            print("[HealthSync] Failed to schedule background task: \(error)")
        }
    }

    /// Handle background task execution
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        // Schedule the next sync
        scheduleBackgroundSync()

        // Create a task to sync health data
        let syncTask = Task {
            do {
                try await syncTodaysHealth()
                task.setTaskCompleted(success: true)
            } catch {
                print("[HealthSync] Background sync failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        // Handle task expiration
        task.expirationHandler = {
            syncTask.cancel()
        }
    }

    // MARK: - Sync Operations

    /// Request HealthKit authorization
    func requestAuthorization() async throws {
        try await healthKit.requestAuthorization()
    }

    /// Check if authorized
    var isAuthorized: Bool {
        healthKit.checkAuthorization()
    }

    /// Sync today's health data to Doris
    func syncTodaysHealth() async throws {
        guard healthKit.isAvailable else {
            throw HealthKitError.notAvailable
        }

        let summary = await healthKit.getTodaysSummary()

        // Only sync if we have some data
        let hasData = summary.steps > 0 || summary.sleepHours != nil || !summary.workouts.isEmpty
        if !hasData {
            print("[HealthSync] No health data available to sync")
            return
        }

        let response = try await api.syncHealth(summary)

        // Update last sync date
        UserDefaults.standard.set(Date(), forKey: lastSyncKey)

        print("[HealthSync] Synced: \(summary.steps) steps, \(summary.workouts.count) workouts → \(response.status)")
    }

    /// Sync health data for a specific date
    func syncHealth(for date: Date) async throws {
        guard healthKit.isAvailable else {
            throw HealthKitError.notAvailable
        }

        let summary = try await healthKit.getSummary(for: date)
        let response = try await api.syncHealth(summary)

        print("[HealthSync] Synced \(summary.date): \(summary.steps) steps → \(response.status)")
    }

    /// Get last sync date
    var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    /// Check if we should sync (hasn't synced today)
    var shouldSync: Bool {
        guard let lastSync = lastSyncDate else {
            return true
        }

        return !Calendar.current.isDateInToday(lastSync)
    }

    // MARK: - App Lifecycle

    /// Called when app becomes active - sync if needed
    func appDidBecomeActive() {
        guard healthKit.isAvailable && isAuthorized && shouldSync else {
            return
        }

        Task {
            do {
                try await syncTodaysHealth()
            } catch {
                print("[HealthSync] Foreground sync failed: \(error)")
            }
        }
    }

    /// Called when app enters background - schedule next sync
    func appDidEnterBackground() {
        scheduleBackgroundSync()
    }
}
