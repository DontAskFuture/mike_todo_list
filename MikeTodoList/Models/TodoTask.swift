import Foundation
import SwiftData

/// Named `TodoTask` to avoid clashing with Swift's `Task` type.
@Model
final class TodoTask {
    var title: String
    var notes: String
    var isCompleted: Bool
    var completedAt: Date?
    var dueDate: Date?
    var reminderDate: Date?
    /// Stores `Recurrence.rawValue`
    var recurrenceRaw: String
    /// Stable id for `UNNotificationRequest` scheduling/cancellation
    var notificationIdentifier: String

    var project: Project?

    init(
        title: String,
        notes: String = "",
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        recurrenceRaw: String = Recurrence.none.rawValue,
        notificationIdentifier: String = UUID().uuidString,
        project: Project? = nil
    ) {
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.recurrenceRaw = recurrenceRaw
        self.notificationIdentifier = notificationIdentifier
        self.project = project
    }
}

extension TodoTask {
    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
}
