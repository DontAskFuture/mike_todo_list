import SwiftUI
import SwiftData

@main
struct MikeTodoListApp: App {
    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .preferredColorScheme(.dark)
                .tint(GeekTheme.accent)
        }
        .modelContainer(for: [Project.self, TodoTask.self])
    }
}

enum GeekTheme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.055)
    static let panel = Color(red: 0.075, green: 0.090, blue: 0.105)
    static let panelRaised = Color(red: 0.105, green: 0.125, blue: 0.145)
    static let border = Color(red: 0.18, green: 0.23, blue: 0.22)
    static let accent = Color(red: 0.34, green: 0.95, blue: 0.58)
    static let accentDim = Color(red: 0.18, green: 0.48, blue: 0.31)
    static let text = Color(red: 0.92, green: 0.96, blue: 0.92)
    static let muted = Color(red: 0.55, green: 0.63, blue: 0.60)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let cornerRadius: CGFloat = 18
}
