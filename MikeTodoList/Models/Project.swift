import Foundation
import SwiftData

@Model
final class Project {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TodoTask.project)
    var tasks: [TodoTask] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}
