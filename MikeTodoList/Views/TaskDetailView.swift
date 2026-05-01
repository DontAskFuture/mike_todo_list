import SwiftUI
import SwiftData
import UserNotifications

struct TaskDetailView: View {
    @Bindable var task: TodoTask
    @Environment(\.dismiss) private var dismiss

    @State private var validationAlert = false
    @State private var notificationDeniedAlert = false

    @State private var hasReminder = false
    /// Debounces parsing title + notes so reminders appear shortly after you pause typing.
    @State private var reminderPhraseDetectionTask: Task<Void, Never>?

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

            Section("Reminder") {
                Toggle("Reminder", isOn: $hasReminder)
                    .onChange(of: hasReminder) { _, on in
                        if !on {
                            task.reminderDate = nil
                            task.recurrenceRaw = Recurrence.none.rawValue
                            Task { await syncNotifications() }
                        } else if task.reminderDate == nil {
                            applyNaturalLanguageReminderHints()
                            if task.reminderDate == nil {
                                task.reminderDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
                            }
                            Task { await syncNotifications() }
                        }
                    }

                Text(
                    "We scan the title and description while you type (after a short pause). Date hints: today, tomorrow 3 pm, next week, Monday 9 am, in 2 hours (only if no reminder time is set yet). Repeat: phrases like every day, weekly, every week, monthly, every month."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

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
                    applyNaturalLanguageReminderHints()
                    if task.reminderDate != nil {
                        hasReminder = true
                    }
                    dismiss()
                }
            }
        }
        .onAppear {
            hasReminder = task.reminderDate != nil
            scheduleReminderPhraseDetection()
        }
        .onDisappear {
            reminderPhraseDetectionTask?.cancel()
            reminderPhraseDetectionTask = nil
            Task { await syncNotifications() }
        }
        .onChange(of: task.title) { _, _ in
            scheduleReminderPhraseDetection()
            Task { await syncNotifications() }
        }
        .onChange(of: task.notes) { _, _ in
            scheduleReminderPhraseDetection()
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

    /// After typing pauses briefly, applies natural-language reminder time (if unset) and repeat hints.
    private func scheduleReminderPhraseDetection() {
        reminderPhraseDetectionTask?.cancel()
        reminderPhraseDetectionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            applyNaturalLanguageReminderHints()
            if task.reminderDate != nil {
                hasReminder = true
            }
            await syncNotifications()
        }
    }

    /// Fills reminder time and repeat from informal phrases when appropriate.
    private func applyNaturalLanguageReminderHints() {
        guard !task.isCompleted else { return }

        if task.reminderDate == nil {
            if let parsed = ReminderPhraseParser.suggestedReminderDate(
                title: task.title,
                notes: task.notes,
                reference: Date()
            ) {
                task.reminderDate = parsed
            }
        }

        if task.recurrence == .none,
           let recurring = ReminderPhraseParser.suggestedRecurrence(title: task.title, notes: task.notes)
        {
            task.recurrence = recurring
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
