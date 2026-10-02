import SwiftData
import SwiftUI

struct ProjectManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var showEditor = false
    @State private var editingProject: Project?
    @State private var alertInfo: AlertInfo?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Projects").font(.title2.bold())
                Spacer()
                Button("New Project", systemImage: "plus") {
                    editingProject = nil
                    showEditor = true
                }
            }
            .padding(20)

            Divider()

            if projects.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "folder", description: Text("Create a project before adding time entries."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if projects.contains(where: { !$0.isArchived }) {
                        Section("Active") {
                            ForEach(projects.filter { !$0.isArchived }, id: \.id) { project in
                                projectRow(project)
                            }
                        }
                    }
                    if projects.contains(where: { $0.isArchived }) {
                        Section("Archived") {
                            ForEach(projects.filter { $0.isArchived }, id: \.id) { project in
                                projectRow(project)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
        .sheet(isPresented: $showEditor) {
            ProjectEditorView(project: editingProject)
        }
        .alert(item: $alertInfo) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: project.colorHex)).frame(width: 12, height: 12)
            Text(project.name)
            Spacer()
            Text("\(project.entries.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Edit", systemImage: "pencil") {
                editingProject = project
                showEditor = true
            }
            .labelStyle(.iconOnly)
            Button(project.isArchived ? "Restore" : "Archive", systemImage: project.isArchived ? "arrow.uturn.backward" : "archivebox") {
                setArchived(project, archived: !project.isArchived)
            }
            .labelStyle(.iconOnly)
        }
        .padding(.vertical, 4)
    }

    private func setArchived(_ project: Project, archived: Bool) {
        do {
            try SwiftDataProjectRepository(context: modelContext).setArchived(project, archived: archived)
        } catch {
            alertInfo = AlertInfo(title: "Couldn’t Update Project", message: error.localizedDescription)
        }
    }
}

private struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let project: Project?

    @State private var name: String
    @State private var colorHex: String
    @State private var errorMessage: String?

    private let palette = ["3B82F6", "8B5CF6", "EC4899", "EF4444", "F97316", "EAB308", "22C55E", "14B8A6", "64748B"]

    init(project: Project?) {
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _colorHex = State(initialValue: project?.colorHex ?? "3B82F6")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(project == nil ? "New Project" : "Edit Project")
                .font(.title2.bold())
            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("Color").font(.headline)
            HStack(spacing: 12) {
                ForEach(palette, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay {
                                if colorHex == hex {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select color \(hex)")
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    private func save() {
        do {
            let repository = SwiftDataProjectRepository(context: modelContext)
            if let project { try repository.update(project, name: name, colorHex: colorHex) }
            else { _ = try repository.create(name: name, colorHex: colorHex) }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
