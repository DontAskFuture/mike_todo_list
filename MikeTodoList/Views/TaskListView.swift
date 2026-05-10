import SwiftUI
import SwiftData

struct TaskListView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext

    @State private var tasks: [TodoTask] = []
    /// Cached, filter-applied projection of `tasks` so SwiftUI body re-renders don't re-filter every time.
    @State private var displayedTasks: [TodoTask] = []
    @State private var filter: TaskFilter = .active
    /// Opens task detail on the parent stack—never nest `NavigationStack` here or Projects stops navigating.
    @State private var selectedTask: TodoTask?
    @State private var newTaskID: PersistentIdentifier?
    /// Avoid re-fetching/re-sorting `project.tasks` on every back-navigation; mutations refresh explicitly.
    @State private var didInitialLoad = false
    @State private var persistenceError: String?

    init(project: Project) {
        self.project = project
    }

    enum TaskFilter: String, CaseIterable {
        case active = "Active"
        case completed = "Completed"
    }

    var body: some View {
        ZStack {
            GeekTheme.background.ignoresSafeArea()

            if displayedTasks.isEmpty {
                GeekEmptyState(
                    title: filter == .active ? "QUEUE EMPTY" : "NO ARCHIVED TASKS",
                    subtitle: filter == .active ? "Tap + to enqueue a task." : "Completed tasks land here.",
                    symbol: filter == .active ? "terminal" : "checkmark.seal"
                )
            } else {
                List {
                    Section {
                        ForEach(displayedTasks) { task in
                            HStack(alignment: .center, spacing: 12) {
                                TaskCompleteButton(
                                    isCompleted: task.isCompleted,
                                    accessibilityTitle: task.title
                                ) {
                                    toggleCompletion(for: task)
                                }

                                Button {
                                    selectedTask = task
                                } label: {
                                    HStack(spacing: 10) {
                                        TaskRowView(task: task)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(GeekTheme.accent.opacity(0.7))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens task details")
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: GeekTheme.cornerRadius)
                                    .fill(GeekTheme.panel)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: GeekTheme.cornerRadius)
                                            .stroke(task.isCompleted ? GeekTheme.accentDim : GeekTheme.border, lineWidth: 1)
                                    )
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 18))
                        }
                        .onDelete { offsets in
                            deleteTasks(at: offsets)
                        }
                    } header: {
                        Text(filter == .active ? "ACTIVE" : "COMPLETED")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(GeekTheme.accent)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(GeekTheme.background)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            reloadTasks()
        }
        .onChange(of: filter) { _, _ in
            updateDisplayedTasks()
        }
        .navigationDestination(item: $selectedTask) { task in
            TaskDetailView(
                task: task,
                deletesEmptyTaskOnDisappear: task.persistentModelID == newTaskID
            ) {
                discardNewTaskIfNeeded(task)
            } onKeepTask: {
                if task.persistentModelID == newTaskID {
                    newTaskID = nil
                }
                saveAndReloadTasks()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Filter", selection: $filter) {
                    ForEach(TaskFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .font(.caption.monospaced())
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
        .alert("Could not save", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "Unknown error")
        }
    }

    private func addTask() {
        let task = TodoTask(title: "")
        modelContext.insert(task)
        task.project = project
        if !project.tasks.contains(where: { $0.persistentModelID == task.persistentModelID }) {
            project.tasks.append(task)
        }
        project.taskCount += 1
        tasks.insert(task, at: 0)
        filter = .active
        updateDisplayedTasks()
        newTaskID = task.persistentModelID
        selectedTask = task
        saveAndReloadTasks()
    }

    private func discardNewTaskIfNeeded(_ task: TodoTask) {
        guard task.persistentModelID == newTaskID else { return }
        NotificationScheduler.cancel(for: task)
        modelContext.delete(task)
        project.taskCount = max(0, project.taskCount - 1)
        tasks.removeAll { $0.persistentModelID == task.persistentModelID }
        newTaskID = nil
        saveAndReloadTasks()
    }

    private func updateDisplayedTasks() {
        switch filter {
        case .active:
            displayedTasks = tasks.filter { !$0.isCompleted }
        case .completed:
            displayedTasks = tasks.filter(\.isCompleted)
        }
    }

    private func deleteTasks(at offsets: IndexSet) {
        let tasks = displayedTasks
        for index in offsets {
            let task = tasks[index]
            NotificationScheduler.cancel(for: task)
            modelContext.delete(task)
        }
        project.taskCount = max(0, project.taskCount - offsets.count)
        saveAndReloadTasks()
    }

    private func toggleCompletion(for task: TodoTask) {
        withAnimation(.easeInOut(duration: 0.22)) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? Date() : nil
        }
        if task.isCompleted {
            NotificationScheduler.cancel(for: task)
        } else if task.reminderDate != nil {
            Task {
                await NotificationScheduler.reschedule(
                    task: task,
                    persistentTaskID: String(describing: task.persistentModelID)
                )
            }
        }
        saveAndReloadTasks()
    }

    private func reloadTasks() {
        tasks = project.tasks.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        updateDisplayedTasks()
    }

    private func saveAndReloadTasks() {
        do {
            modelContext.processPendingChanges()
            try modelContext.save()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
        reloadTasks()
    }
}

/// Tappable control separate from `NavigationLink` so completion does not open the editor.
private struct TaskCompleteButton: View {
    let isCompleted: Bool
    let accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                .font(.system(size: 26, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isCompleted ? GeekTheme.accent : GeekTheme.muted)
                .symbolEffect(.bounce, value: isCompleted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isCompleted
                ? "Mark \(accessibilityTitle) as not done"
                : "Mark \(accessibilityTitle) as done"
        )
    }
}

private struct TaskRowView: View {
    let task: TodoTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title.isEmpty ? "untitled" : task.title)
                .font(.headline.monospaced().weight(.semibold))
                .foregroundStyle(task.isCompleted ? GeekTheme.muted : GeekTheme.text)
                .strikethrough(task.isCompleted)

            if let reminder = task.reminderDate {
                Group {
                    Label(reminder.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                        .font(.caption.monospaced())
                        .foregroundStyle(GeekTheme.muted)
                }
                .accessibilityIdentifier("taskRowReminder")
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
