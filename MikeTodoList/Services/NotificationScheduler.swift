import Foundation
import UserNotifications

enum NotificationScheduler {
    private static let center = UNUserNotificationCenter.current()

    static func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func cancel(for task: TodoTask) {
        center.removePendingNotificationRequests(withIdentifiers: [task.notificationIdentifier])
    }

    /// Cancels any pending request for this task, then schedules if eligible.
    static func reschedule(task: TodoTask, persistentTaskID: String) async {
        cancel(for: task)

        guard !task.isCompleted, let reminder = task.reminderDate else {
            return
        }

        let recurrence = task.recurrence

        if recurrence == .none, reminder <= Date() {
            return
        }

        let settings = await center.notificationSettings()
        let authorized =
            settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral

        if !authorized {
            do {
                let granted = try await requestAuthorization()
                if !granted { return }
            } catch {
                return
            }
        }

        let content = UNMutableNotificationContent()
        content.title = task.title
        if !task.notes.isEmpty {
            content.body = task.notes
        }
        content.sound = .default
        content.userInfo = [
            "notificationIdentifier": task.notificationIdentifier,
            "persistentTaskID": persistentTaskID
        ]

        let calendar = Calendar.current
        let trigger: UNNotificationTrigger?

        switch recurrence {
        case .none:
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        case .daily:
            let components = calendar.dateComponents([.hour, .minute], from: reminder)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .weekly:
            let components = calendar.dateComponents([.weekday, .hour, .minute], from: reminder)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .monthly:
            let components = calendar.dateComponents([.day, .hour, .minute], from: reminder)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

        guard let trigger else { return }

        let request = UNNotificationRequest(
            identifier: task.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            // Best-effort scheduling
        }
    }
}
