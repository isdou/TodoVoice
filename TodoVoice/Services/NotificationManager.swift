import Foundation
import UserNotifications
import UIKit

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        default:
            return false
        }
    }

    func schedule(title: String, dueDate: Date, notificationId: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])

        guard dueDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "待办提醒"
        content.body = title
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationId, content: content, trigger: trigger
        )
        center.add(request)
    }

    func cancel(notificationId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationId]
        )
    }

    func cancelAll(for items: [TodoItem]) {
        let ids = items.map(\.notificationId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
