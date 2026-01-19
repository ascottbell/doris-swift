import Foundation
import UserNotifications
import UIKit

/// Manages push notification registration and handling for Doris proactive alerts
class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published var isRegistered = false
    @Published var deviceToken: String?

    private let apiService = DorisAPIService()

    private override init() {
        super.init()
    }

    // MARK: - Registration

    /// Request push notification permissions and register with APNS
    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()

        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

        if granted {
            print("[Push] Authorization granted")
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } else {
            print("[Push] Authorization denied")
        }
    }

    /// Called when APNS registration succeeds
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[Push] Registered with token: \(token)")

        self.deviceToken = token
        self.isRegistered = true

        // Register with Doris server
        Task {
            await registerWithServer(token: token)
        }
    }

    /// Called when APNS registration fails
    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("[Push] Registration failed: \(error.localizedDescription)")
        self.isRegistered = false
    }

    // MARK: - Server Registration

    private func registerWithServer(token: String) async {
        do {
            let success = try await apiService.registerDevice(token: token)
            if success {
                print("[Push] Registered with Doris server")
            } else {
                print("[Push] Server registration returned failure")
            }
        } catch {
            print("[Push] Failed to register with server: \(error)")
        }
    }

    // MARK: - Notification Handling

    /// Handle notification received while app is in foreground
    func handleForegroundNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        print("[Push] Received in foreground: \(userInfo)")

        // Show banner even in foreground for proactive alerts
        return [.banner, .sound]
    }

    /// Handle notification tap
    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        print("[Push] Notification tapped: \(userInfo)")

        // Extract action info if present
        if let actionId = userInfo["action_id"] as? String,
           let actionType = userInfo["action_type"] as? String {
            print("[Push] Action: \(actionType) (\(actionId))")
            // Could navigate to specific view or trigger action here
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let options = handleForegroundNotification(notification)
        completionHandler(options)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponse(response)
        completionHandler()
    }
}
