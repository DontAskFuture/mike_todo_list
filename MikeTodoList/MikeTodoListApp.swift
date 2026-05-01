import SwiftUI
import SwiftData

@main
struct MikeTodoListApp: App {
    var body: some Scene {
        WindowGroup {
            ProjectListView()
        }
        .modelContainer(for: [Project.self, TodoTask.self])
    }
}
