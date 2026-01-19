import SwiftUI

@main
struct DorisClientApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register background task handler
        HealthSyncManager.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Request authorizations on first launch
                    await requestAuthorizations()
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                HealthSyncManager.shared.appDidBecomeActive()
            case .background:
                HealthSyncManager.shared.appDidEnterBackground()
            default:
                break
            }
        }
    }

    private func requestAuthorizations() async {
        // Request HealthKit authorization
        do {
            try await HealthSyncManager.shared.requestAuthorization()
            print("[App] HealthKit authorization granted")

            // Do an initial sync (may fail if no data available - that's ok)
            do {
                try await HealthSyncManager.shared.syncTodaysHealth()
                print("[App] HealthKit sync completed")
            } catch {
                // "No data available" is not a real error, just means nothing to sync
                let errorDesc = error.localizedDescription
                if errorDesc.contains("No data available") {
                    print("[App] HealthKit: No health data to sync (this is normal if no Apple Watch)")
                } else {
                    print("[App] HealthKit sync failed: \(error)")
                }
            }
        } catch {
            print("[App] HealthKit authorization failed: \(error)")
        }

        // Request push notification authorization
        do {
            try await PushNotificationManager.shared.requestAuthorization()
            print("[App] Push notification authorization requested")
        } catch {
            print("[App] Push notification authorization failed: \(error)")
        }
    }
}
