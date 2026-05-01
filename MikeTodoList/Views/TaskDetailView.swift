import SwiftUI
import SwiftData
import UserNotifications

struct TaskDetailView: View {
    @Bindable var task: TodoTask
    @Environment(\.dismiss) private var dismiss

    @State private var validationAlert = false
    @State private var notificationDeniedAlert = false

    @State private var hasDueDate = false
    @State private var hasReminder = false

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $task.title)
                ZStack(alignment: .topLeading) {
                    if task.notes.isEmpty {
                        Text("Description (optional)")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $task.notes)
                        .frame(minHeight: 120)
                }
            }

            Section("Due date") {
                Toggle("Due date", isOn: $hasDueDate)
                    .onChange(of: hasDueDate) { _, on in
                        if !on { task.dueDate = nil }
                        else if task.dueDate == nil { task.dueDate = Date() }
                    }
                if hasDueDate {
                    DatePicker(
                        "Due",
                        selection: Binding(
                            get: { task.dueDate ?? Date() },
                            set: { task.dueDate = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }

            Section("Reminder") {
                Toggle("Reminder", isOn: $hasReminder)
                    .onChange(of: hasReminder) { _, on in
                        if !on {
                            task.reminderDate = nil
                            task.recurrenceRaw = Recurrence.none.rawValue
                            Task { await syncNotifications() }
                        } else if task.reminderDate == nil {
                            task.reminderDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
                            Task { await syncNotifications() }
                        }
                    }

                if hasReminder {
                    DatePicker(
                        "Date & time",
                        selection: Binding(
                            get: { task.reminderDate ?? Date() },
                            set: { newVal in
                                task.reminderDate = newVal
                                Task { await syncNotifications() }
                            }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Picker("Repeat", selection: $task.recurrenceRaw) {
                        ForEach(Recurrence.allCases) { r in
                            Text(r.displayName).tag(r.rawValue)
                        }
                    }
                    .onChange(of: task.recurrenceRaw) { _, _ in
                        Task { await syncNotifications() }
                    }

                    Text(
                        "Repeats at the same clock time. Weekly uses this weekday; monthly uses this calendar day (day 31 may not fire in shorter months)."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Status") {
                Toggle("Completed", isOn: $task.isCompleted)
                    .onChange(of: task.isCompleted) { _, done in
                        task.completedAt = done ? Date() : nil
                        Task { await syncNotifications() }
                    }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        validationAlert = true
                        return
                    }
                    task.title = trimmed
                    dismiss()
                }
            }
        }
        .onAppear {
            hasDueDate = task.dueDate != nil
            hasReminder = task.reminderDate != nil
        }
        .onDisappear {
            Task { await syncNotifications() }
        }
        .onChange(of: task.title) { _, _ in
            Task { await syncNotifications() }
        }
        .onChange(of: task.notes) { _, _ in
            Task { await syncNotifications() }
        }
        .alert("Title required", isPresented: $validationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enter a title before saving.")
        }
        .alert("Notifications disabled", isPresented: $notificationDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable notifications in Settings to receive reminders.")
        }
    }

    private func syncNotifications() async {
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NotificationScheduler.cancel(for: task)
            return
        }

        if task.isCompleted || task.reminderDate == nil {
            NotificationScheduler.cancel(for: task)
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .denied {
            notificationDeniedAlert = true
            return
        }

        await NotificationScheduler.reschedule(
            task: task,
            persistentTaskID: String(describing: task.persistentModelID)
        )
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Project.self, TodoTask.self, configurations: config)
    let task = TodoTask(title: "Sample", notes: "Notes here")
    container.mainContext.insert(task)

    return NavigationStack {
        TaskDetailView(task: task)
    }
    .modelContainer(container)
}
