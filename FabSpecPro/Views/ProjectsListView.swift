import SwiftUI
import SwiftData

struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query private var treatments: [EdgeTreatment]
    @Query private var materials: [MaterialOption]
    @State private var isShowingNewProject = false
    @State private var newProjectName = ""
    @State private var newlyCreatedProject: Project?
    @State private var projectToDelete: Project?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LogoHeaderView()
                        SectionCard(title: "Projects") {
                            VStack(spacing: 12) {
                                if projects.isEmpty {
                                    Text("No projects yet. Tap New Project to start.")
                                        .foregroundStyle(Theme.secondaryText)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                ForEach(projects) { project in
                                    NavigationLink {
                                        ProjectDetailView(project: project)
                                    } label: {
                                        ProjectRow(project: project)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete Project", role: .destructive) {
                                            projectToDelete = project
                                        }
                                    }
                                }
                                Button("New Project") {
                                    isShowingNewProject = true
                                }
                                .buttonStyle(PillButtonStyle(isProminent: true))
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Settings") {
                        SettingsView()
                    }
                }
            }
            .alert("New Project", isPresented: $isShowingNewProject) {
                TextField("Project name", text: $newProjectName)
                Button("Create") {
                    addProject()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter a name for the project.")
            }
            .navigationDestination(item: $newlyCreatedProject) { project in
                ProjectDetailView(project: project)
            }
            .alert("Delete Project?", isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let projectToDelete {
                        modelContext.delete(projectToDelete)
                        self.projectToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    projectToDelete = nil
                }
            } message: {
                Text("This will remove the project and all pieces.")
            }
            .task {
                seedDefaultsIfNeeded()
            }
        }
    }

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let project = Project(name: name)
        modelContext.insert(project)
        newProjectName = ""
        newlyCreatedProject = project
    }

    private func seedDefaultsIfNeeded() {
        if treatments.isEmpty {
            let defaults = [
                EdgeTreatment(name: "Polished", abbreviation: "P"),
                EdgeTreatment(name: "Eased", abbreviation: "E"),
                EdgeTreatment(name: "Bevel", abbreviation: "B"),
                EdgeTreatment(name: "Radius", abbreviation: "R")
            ]
            defaults.forEach { modelContext.insert($0) }
        }

        if materials.isEmpty {
            let defaults = [
                MaterialOption(name: "Quartz"),
                MaterialOption(name: "Granite"),
                MaterialOption(name: "Marble")
            ]
            defaults.forEach { modelContext.insert($0) }
        }
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .foregroundStyle(Theme.primaryText)
                    .font(.system(size: 14, weight: .semibold))
                Text("Pieces: \(project.pieces.count)")
                    .foregroundStyle(Theme.secondaryText)
                    .font(.system(size: 12))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
