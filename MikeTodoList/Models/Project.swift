import Foundation
import SwiftData

@Model
final class Project {
    var name: String
    var createdAt: Date
    var taskCount: Int

    @Relationship(deleteRule: .cascade, inverse: \TodoTask.project)
    var tasks: [TodoTask] = []

    init(name: String, createdAt: Date = .now, taskCount: Int = 0) {
        self.name = name
        self.createdAt = createdAt
        self.taskCount = taskCount
    }
}
