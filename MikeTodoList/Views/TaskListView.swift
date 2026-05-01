import SwiftUI
import SwiftData

struct TaskListView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext

    @State private var filter: TaskFilter = .active

    enum TaskFilter: String, CaseIterable {
        case active = "Active"
        case completed = "Completed"
    }

    private var sortedTasks: [TodoTask] {
        project.tasks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var displayedTasks: [TodoTask] {
        switch filter {
        case .active:
            return sortedTasks.filter { !$0.isCompleted }
        case .completed:
            return sortedTasks.filter(\.isCompleted)
        }
    }

    var body: some View {
        Group {
            if displayedTasks.isEmpty {
                ContentUnavailableView(
                    filter == .active ? "No Active Tasks" : "No Completed Tasks",
                    systemImage: "checklist",
                    description: Text(
                        filter == .active
                            ? "Tap + to add a task."
                            : "Completed tasks appear here."
                    )
                )
            } else {
                List {
                    ForEach(displayedTasks) { task in
                        NavigationLink(value: task) {
                            TaskRowView(task: task)
                        }
                    }
                    .onDelete { offsets in
                        deleteTasks(at: offsets)
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: TodoTask.self) { task in
            TaskDetailView(task: task)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Filter", selection: $filter) {
                    ForEach(TaskFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addTask()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add task")
            }
        }
    }

    private func addTask() {
        let task = TodoTask(title: "New task", project: project)
        modelContext.insert(task)
    }

    private func deleteTasks(at offsets: IndexSet) {
        let tasks = displayedTasks
        for index in offsets {
            let task = tasks[index]
            NotificationScheduler.cancel(for: task)
            modelContext.delete(task)
        }
    }
}

private struct TaskRowView: View {
    let task: TodoTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.headline)
                .strikethrough(task.isCompleted)

            if let due = task.dueDate {
                Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reminder = task.reminderDate {
                Label(reminder.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Project.self, TodoTask.self, configurations: config)
    let project = Project(name: "Demo")
    container.mainContext.insert(project)

    return NavigationStack {
        TaskListView(project: project)
    }
    .modelContainer(container)
}
