import SwiftUI
import SwiftData
import PhotosUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var treatments: [EdgeTreatment]
    @Query private var materials: [MaterialOption]
    @Query private var edgeAssignments: [EdgeAssignment]
    @Query private var pieces: [Piece]
    @Query private var headers: [BusinessHeader]
    @State private var newTreatmentName = ""
    @State private var newTreatmentCode = ""
    @State private var newMaterialName = ""
    @State private var logoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            TabView {
                businessInfoTab
                    .tabItem {
                        Label("Business Info", systemImage: "briefcase")
                    }
                materialsTab
                    .tabItem {
                        Label("Materials Library", systemImage: "square.grid.2x2")
                    }
                edgesTab
                    .tabItem {
                        Label("Edges Library", systemImage: "line.diagonal")
                    }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureHeaderExists()
        }
    }

    private var businessInfoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let header = currentHeader {
                    SectionCard(title: "Business Info") {
                        VStack(spacing: 12) {
                            TextField("Business name", text: binding(for: header, keyPath: \.businessName))
                                .textInputAutocapitalization(.words)
                            TextField("Address", text: binding(for: header, keyPath: \.address))
                                .textInputAutocapitalization(.words)
                            TextField("Email", text: binding(for: header, keyPath: \.email))
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                            TextField("Phone", text: binding(for: header, keyPath: \.phone))
                                .keyboardType(.phonePad)
                            PhotosPicker("Choose Logo", selection: $logoItem, matching: .images)
                                .buttonStyle(PillButtonStyle())
                                .onChange(of: logoItem) { _, newValue in
                                    guard let newValue else { return }
                                    Task {
                                        if let data = try? await newValue.loadTransferable(type: Data.self) {
                                            header.logoData = data
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var materialsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(title: "Materials Library") {
                    VStack(spacing: 12) {
                        ForEach(materials) { material in
                            HStack {
                                TextField("Material name", text: binding(for: material, keyPath: \.name))
                                    .foregroundStyle(Theme.primaryText)
                                Spacer()
                                Button("Delete", role: .destructive) {
                                    for piece in pieces where piece.materialName == material.name {
                                        piece.materialName = ""
                                    }
                                    modelContext.delete(material)
                                }
                                .buttonStyle(PillButtonStyle())
                            }
                            .padding(10)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        HStack {
                            TextField("Material name", text: $newMaterialName)
                            Button("Add") {
                                addMaterial()
                            }
                            .buttonStyle(PillButtonStyle(isProminent: true))
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var edgesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(title: "Edges Library") {
                    VStack(spacing: 12) {
                        ForEach(treatments) { treatment in
                            HStack {
                                TextField("Code", text: binding(for: treatment, keyPath: \.abbreviation))
                                    .frame(width: 70)
                                    .textInputAutocapitalization(.characters)
                                    .foregroundStyle(Theme.accent)
                                TextField("Name", text: binding(for: treatment, keyPath: \.name))
                                    .foregroundStyle(Theme.primaryText)
                                Spacer()
                                Button("Delete", role: .destructive) {
                                    for assignment in edgeAssignments where assignment.treatment?.id == treatment.id {
                                        assignment.piece?.edgeAssignments.removeAll { $0.id == assignment.id }
                                        modelContext.delete(assignment)
                                    }
                                    modelContext.delete(treatment)
                                }
                                .buttonStyle(PillButtonStyle())
                            }
                            .padding(10)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        HStack {
                            TextField("Code", text: $newTreatmentCode)
                            TextField("Name", text: $newTreatmentName)
                            Button("Add") {
                                addTreatment()
                            }
                            .buttonStyle(PillButtonStyle(isProminent: true))
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func addTreatment() {
        let name = newTreatmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = newTreatmentCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !code.isEmpty else { return }
        let treatment = EdgeTreatment(name: name, abbreviation: code)
        modelContext.insert(treatment)
        newTreatmentName = ""
        newTreatmentCode = ""
    }

    private func addMaterial() {
        let name = newMaterialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let material = MaterialOption(name: name)
        modelContext.insert(material)
        newMaterialName = ""
    }

    private var currentHeader: BusinessHeader? {
        headers.first
    }

    private func ensureHeaderExists() {
        if headers.isEmpty {
            let header = BusinessHeader()
            modelContext.insert(header)
        }
    }

    private func binding<T>(for model: T, keyPath: ReferenceWritableKeyPath<T, String>) -> Binding<String> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { model[keyPath: keyPath] = $0 }
        )
    }
}
