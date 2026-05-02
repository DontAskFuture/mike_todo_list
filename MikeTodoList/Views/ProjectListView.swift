import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var projects: [Project] = []
    /// Sheet dismissal triggers `onAppear` again; skip redundant reloads so a transient empty fetch can't wipe the list.
    @State private var didPerformInitialFetch = false
    @State private var newProjectName = ""
    @State private var showingAdd = false
    @State private var persistenceError: String?
    /// `NavigationLink` adds its own trailing chevron; drive navigation manually so only `ProjectCard`'s arrow shows.
    @State private var selectedProject: Project?

    var body: some View {
        NavigationStack {
            ZStack {
                GeekTheme.background.ignoresSafeArea()

                if projects.isEmpty {
                    GeekEmptyState(
                        title: "NO PROJECTS",
                        subtitle: "Tap + to initialize a project.",
                        symbol: "folder.badge.plus"
                    )
                } else {
                    List {
                        Section {
                            ForEach(projects) { project in
                                Button {
                                    selectedProject = project
                                } label: {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens project tasks")
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
                            }
                            .onDelete(perform: deleteProjects)
                        } header: {
                            Text("WORKSPACES")
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(GeekTheme.accent)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(GeekTheme.background)
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(item: $selectedProject) { project in
                TaskListView(project: project)
            }
            .onAppear {
                if !didPerformInitialFetch {
                    didPerformInitialFetch = true
                    reloadProjects()
                }
                repairTaskCountsIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newProjectName = ""
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add project")
                }
            }
            .sheet(isPresented: $showingAdd) {
                NavigationStack {
                    Form {
                        TextField("Project name", text: $newProjectName)
                            .font(.body.monospaced())
                    }
                    .navigationTitle("New Project")
                    .navigationBarTitleDisplayMode(.inline)
                    .scrollContentBackground(.hidden)
                    .background(GeekTheme.background)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                addProject()
                            }
                            .accessibilityIdentifier("addProjectConfirm")
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .alert("Could not save project", isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(persistenceError ?? "Unknown error")
            }
        }
    }

    private func addProject() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let project = Project(name: trimmed)
        modelContext.insert(project)

        do {
            modelContext.processPendingChanges()
            try modelContext.save()
            // Immediate fetch can transiently return [] — keep the row visible regardless.
            if !projects.contains(where: { $0.persistentModelID == project.persistentModelID }) {
                projects.insert(project, at: 0)
            }
            showingAdd = false
        } catch {
            modelContext.delete(project)
            persistenceError = error.localizedDescription
        }
    }

    private func deleteProjects(at offsets: IndexSet) {
        for index in offsets {
            let project = projects[index]
            for task in project.tasks {
                NotificationScheduler.cancel(for: task)
            }
            modelContext.delete(project)
        }
        do {
            modelContext.processPendingChanges()
            try modelContext.save()
            reloadProjects()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func reloadProjects() {
        var descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true

        do {
            projects = try modelContext.fetch(descriptor)
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func repairTaskCountsIfNeeded() {
        var repaired = false
        for project in projects {
            let actualCount = project.tasks.count
            if project.taskCount != actualCount {
                project.taskCount = actualCount
                repaired = true
            }
        }
        if repaired {
            do {
                modelContext.processPendingChanges()
                try modelContext.save()
                reloadProjects()
            } catch {
                persistenceError = error.localizedDescription
            }
        }
    }
}

private struct ProjectCard: View {
    let project: Project

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(GeekTheme.accentDim.opacity(0.35))
                Text("#")
                    .font(.title3.monospaced().weight(.bold))
                    .foregroundStyle(GeekTheme.accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(project.name.isEmpty ? "untitled" : project.name)
                    .font(.headline.monospaced().weight(.semibold))
                    .foregroundStyle(GeekTheme.text)
                Text("\(project.taskCount) tasks")
                    .font(.caption.monospaced())
                    .foregroundStyle(GeekTheme.muted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(GeekTheme.accent.opacity(0.7))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: GeekTheme.cornerRadius)
                .fill(GeekTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: GeekTheme.cornerRadius)
                        .stroke(GeekTheme.border, lineWidth: 1)
                )
        )
    }
}

struct GeekEmptyState: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(GeekTheme.accent)
            Text(title)
                .font(.title3.monospaced().weight(.bold))
                .foregroundStyle(GeekTheme.text)
            Text(subtitle)
                .font(.subheadline.monospaced())
                .foregroundStyle(GeekTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ProjectListView()
        .modelContainer(for: [Project.self, TodoTask.self], inMemory: true)
}
