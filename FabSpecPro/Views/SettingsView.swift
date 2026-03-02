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
    @Query private var pieceDefaults: [PieceDefaults]
    @State private var newTreatmentName = ""
    @State private var newTreatmentCode = ""
    @State private var newMaterialName = ""
    @State private var logoItem: PhotosPickerItem?
    @State private var showLogoFileImporter = false

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
                pieceDefaultsTab
                    .tabItem {
                        Label("Piece Defaults", systemImage: "square.on.square")
                    }
            }
        }
        .navigationTitle("Settings")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            ensureHeaderExists()
            ensurePieceDefaultsExists()
        }
    }

    private var businessInfoTab: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let header = currentHeader {
                        SectionCard(title: "Business Info") {
                        VStack(spacing: 12) {
                            TextField("Business name", text: binding(for: header, keyPath: \.businessName), prompt: Text("Business name").foregroundStyle(Theme.secondaryText))
                                .foregroundStyle(Theme.primaryText)
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.words)
                                #endif
                            TextField("Address", text: binding(for: header, keyPath: \.address), prompt: Text("Address").foregroundStyle(Theme.secondaryText))
                                .foregroundStyle(Theme.primaryText)
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.words)
                                #endif
                            TextField("Email", text: binding(for: header, keyPath: \.email), prompt: Text("Email").foregroundStyle(Theme.secondaryText))
                                .foregroundStyle(Theme.primaryText)
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                #endif
                            TextField("Phone", text: binding(for: header, keyPath: \.phone), prompt: Text("Phone").foregroundStyle(Theme.secondaryText))
                                .foregroundStyle(Theme.primaryText)
                                #if canImport(UIKit)
                                .keyboardType(.phonePad)
                                #endif
                            Menu("Choose Logo") {
                                Button("None") {
                                    header.logoData = nil
                                    logoItem = nil
                                }

                                PhotosPicker("Photo Library", selection: $logoItem, matching: .images)

                                Button("Choose File") {
                                    showLogoFileImporter = true
                                }
                            }
                            .buttonStyle(PillButtonStyle())
                            .onChange(of: logoItem) { _, newValue in
                                guard let newValue else { return }
                                Task {
                                    if let data = try? await newValue.loadTransferable(type: Data.self) {
                                        header.logoData = data
                                    }
                                }
                            }
                            .fileImporter(
                                isPresented: $showLogoFileImporter,
                                allowedContentTypes: [.image],
                                allowsMultipleSelection: false
                            ) { result in
                                guard let url = try? result.get().first else { return }
                                guard let data = try? Data(contentsOf: url) else { return }
                                header.logoData = data
                            }
                        }
                    }
                }
            }
            .padding(20)
            }
            .dismissKeyboardOnSwipe()
        }
    }

    private var materialsTab: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
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
                                .foregroundStyle(Theme.primaryText)
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
            .dismissKeyboardOnSwipe()
        }
    }

    private var edgesTab: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(title: "Edges Library") {
                    VStack(spacing: 12) {
                        ForEach(treatments) { treatment in
                            HStack {
                                TextField("Code", text: binding(for: treatment, keyPath: \.abbreviation))
                                    .frame(width: 70)
                                    #if canImport(UIKit)
                                    .textInputAutocapitalization(.characters)
                                    #endif
                                    .foregroundStyle(Theme.accent)
                                TextField("Name", text: binding(for: treatment, keyPath: \.name))
                                    .foregroundStyle(Theme.primaryText)
                                Spacer()
                                Button("Delete", role: .destructive) {
                                    for assignment in edgeAssignments where assignment.treatment?.id == treatment.id {
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
                                .foregroundStyle(Theme.accent)
                            TextField("Name", text: $newTreatmentName)
                                .foregroundStyle(Theme.primaryText)
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
            .dismissKeyboardOnSwipe()
        }
    }

    private var pieceDefaultsTab: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let defaults = currentPieceDefaults {
                        // Basic Defaults Section
                        SectionCard(title: "Basic Defaults") {
                            VStack(spacing: 12) {
                                // Material picker
                                HStack {
                                    Text("Material")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Picker("Material", selection: Binding(
                                        get: { defaults.defaultMaterialName },
                                        set: { defaults.defaultMaterialName = $0 }
                                    )) {
                                        Text("None").tag("")
                                        ForEach(materials) { material in
                                            Text(material.name).tag(material.name)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Theme.accent)
                                }

                                // Thickness picker
                                HStack {
                                    Text("Thickness")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Picker("Thickness", selection: Binding(
                                        get: { defaults.defaultThickness },
                                        set: { defaults.defaultThickness = $0 }
                                    )) {
                                        ForEach(MaterialThickness.allCases, id: \.self) { thickness in
                                            Text(thickness.rawValue).tag(thickness.rawValue)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Theme.accent)
                                }

                                // Shape picker
                                HStack {
                                    Text("Shape")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Picker("Shape", selection: Binding(
                                        get: { defaults.defaultShape },
                                        set: { defaults.defaultShape = $0 }
                                    )) {
                                        ForEach(ShapeKind.allCases, id: \.self) { shape in
                                            Text(shape.rawValue).tag(shape.rawValue)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Theme.accent)
                                }

                                // Width
                                HStack {
                                    Text("Width")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    TextField("Width", text: Binding(
                                        get: { defaults.defaultWidth },
                                        set: { defaults.defaultWidth = $0 }
                                    ), prompt: Text("24").foregroundStyle(Theme.secondaryText))
                                    .foregroundStyle(Theme.primaryText)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    #if canImport(UIKit)
                                    .keyboardType(.decimalPad)
                                    #endif
                                }

                                // Length
                                HStack {
                                    Text("Length")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    TextField("Length", text: Binding(
                                        get: { defaults.defaultHeight },
                                        set: { defaults.defaultHeight = $0 }
                                    ), prompt: Text("18").foregroundStyle(Theme.secondaryText))
                                    .foregroundStyle(Theme.primaryText)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    #if canImport(UIKit)
                                    .keyboardType(.decimalPad)
                                    #endif
                                }

                                // Quantity
                                HStack {
                                    Text("Quantity")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Stepper("\(defaults.defaultQuantity)", value: Binding(
                                        get: { defaults.defaultQuantity },
                                        set: { defaults.defaultQuantity = $0 }
                                    ), in: 1...100)
                                    .foregroundStyle(Theme.primaryText)
                                }
                            }
                        }

                        // Cutout Defaults Section
                        SectionCard(title: "Cutout Defaults") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Shape")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Button("Circle") {
                                            defaults.defaultCutoutShape = "Circle"
                                        }
                                        .buttonStyle(PillButtonStyle(isProminent: defaults.defaultCutoutShape == "Circle"))

                                        Button("Rectangle") {
                                            defaults.defaultCutoutShape = "Rectangle"
                                        }
                                        .buttonStyle(PillButtonStyle(isProminent: defaults.defaultCutoutShape == "Rectangle"))
                                    }
                                }

                                HStack {
                                    Text("Width")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    TextField("Width", value: Binding(
                                        get: { defaults.defaultCutoutWidth },
                                        set: { defaults.defaultCutoutWidth = $0 }
                                    ), format: .number)
                                    .foregroundStyle(Theme.primaryText)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    #if canImport(UIKit)
                                    .keyboardType(.decimalPad)
                                    #endif
                                }

                                HStack {
                                    Text("Length")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    TextField("Length", value: Binding(
                                        get: { defaults.defaultCutoutHeight },
                                        set: { defaults.defaultCutoutHeight = $0 }
                                    ), format: .number)
                                    .foregroundStyle(Theme.primaryText)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    #if canImport(UIKit)
                                    .keyboardType(.decimalPad)
                                    #endif
                                }
                            }
                        }

                        // Curve Defaults Section
                        SectionCard(title: "Curve Defaults") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Arc Depth")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    TextField("Arc Depth", value: Binding(
                                        get: { defaults.defaultCurveRadius },
                                        set: { defaults.defaultCurveRadius = $0 }
                                    ), format: .number)
                                    .foregroundStyle(Theme.primaryText)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    #if canImport(UIKit)
                                    .keyboardType(.decimalPad)
                                    #endif
                                }

                                Toggle("Concave", isOn: Binding(
                                    get: { defaults.defaultCurveIsConcave },
                                    set: { defaults.defaultCurveIsConcave = $0 }
                                ))
                                .foregroundStyle(Theme.primaryText)
                                .tint(Theme.accent)
                                
                                HStack {
                                    Text("Start Corner")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Picker("Start Corner", selection: Binding(
                                        get: { defaults.defaultCurveStartCorner },
                                        set: { defaults.defaultCurveStartCorner = $0 }
                                    )) {
                                        Text("None").tag(-1)
                                        Text("A").tag(0)
                                        Text("B").tag(1)
                                        Text("C").tag(2)
                                        Text("D").tag(3)
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Theme.accent)
                                }
                                
                                HStack {
                                    Text("End Corner")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Picker("End Corner", selection: Binding(
                                        get: { defaults.defaultCurveEndCorner },
                                        set: { defaults.defaultCurveEndCorner = $0 }
                                    )) {
                                        Text("None").tag(-1)
                                        Text("A").tag(0)
                                        Text("B").tag(1)
                                        Text("C").tag(2)
                                        Text("D").tag(3)
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Theme.accent)
                                }
                            }
                        }

                        // Angle Defaults Section
                        SectionCard(title: "Angle Defaults") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Corner")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Picker("Corner", selection: Binding(
                                        get: { defaults.defaultAngleCorner },
                                        set: { defaults.defaultAngleCorner = $0 }
                                    )) {
                                        Text("None").tag(-1)
                                        Text("A").tag(0)
                                        Text("B").tag(1)
                                        Text("C").tag(2)
                                        Text("D").tag(3)
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Theme.accent)
                                }
                                
                                HStack {
                                    Text("Degrees")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    TextField("Degrees", value: Binding(
                                        get: { defaults.defaultAngleDegrees },
                                        set: { defaults.defaultAngleDegrees = $0 }
                                    ), format: .number)
                                    .foregroundStyle(Theme.primaryText)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    #if canImport(UIKit)
                                    .keyboardType(.decimalPad)
                                    #endif
                                }
                            }
                        }

                        // Corner Radius Defaults Section
                        SectionCard(title: "Corner Radius Defaults") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Radius")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    TextField("Radius", value: Binding(
                                        get: { defaults.defaultCornerRadiusValue },
                                        set: { defaults.defaultCornerRadiusValue = $0 }
                                    ), format: .number)
                                    .foregroundStyle(Theme.primaryText)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    #if canImport(UIKit)
                                    .keyboardType(.decimalPad)
                                    #endif
                                }
                                
                                HStack {
                                    Text("Corner")
                                        .foregroundStyle(Theme.primaryText)
                                    Spacer()
                                    Picker("Corner", selection: Binding(
                                        get: { defaults.defaultCornerRadiusCorner },
                                        set: { defaults.defaultCornerRadiusCorner = $0 }
                                    )) {
                                        Text("None").tag(-1)
                                        Text("A").tag(0)
                                        Text("B").tag(1)
                                        Text("C").tag(2)
                                        Text("D").tag(3)
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Theme.accent)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .dismissKeyboardOnSwipe()
        }
    }

    private var currentPieceDefaults: PieceDefaults? {
        pieceDefaults.first
    }

    private func ensurePieceDefaultsExists() {
        if pieceDefaults.isEmpty {
            let defaults = PieceDefaults()
            modelContext.insert(defaults)
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
