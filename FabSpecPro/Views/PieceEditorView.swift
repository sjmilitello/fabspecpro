import SwiftUI
import SwiftData

struct PieceEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var treatments: [EdgeTreatment]
    @Query private var materials: [MaterialOption]
    @Bindable var piece: Piece

    @State private var selectedTreatmentId: UUID?
    @State private var nextPiece: Piece?
    @State private var isMaterialOpen = false
    @State private var isShapeOpen = false
    @State private var isDrawingOpen = false
    @State private var isOptionsOpen = false
    @State private var isNotesOpen = false
    @State private var isCutoutsOpen = false
    @State private var isNotchesOpen = false
    @State private var isCurvesOpen = false
    @State private var isAnglesOpen = false
    @State private var openCutoutIds: Set<UUID> = []
    @State private var openNotchIds: Set<UUID> = []
    @State private var openCurveIds: Set<UUID> = []
    @State private var openAngleIds: Set<UUID> = []
    @State private var showDeletePieceConfirm = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    collapsibleSection(title: "Material", isOpen: $isMaterialOpen) {
                        VStack(spacing: 12) {
                            TextField("Piece name", text: $piece.name)
                                .textInputAutocapitalization(.words)
                            TextField("Material name", text: $piece.materialName)
                                .textInputAutocapitalization(.words)
                            HStack {
                                Picker("Thickness", selection: $piece.thicknessRaw) {
                                    ForEach(MaterialThickness.allCases) { thickness in
                                        Text(thickness.rawValue).tag(thickness.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                Spacer()
                                Menu("Saved") {
                                    ForEach(materials) { material in
                                        Button(material.name) { piece.materialName = material.name }
                                    }
                                }
                            }
                        }
                    }

                    collapsibleSection(title: "Shape", isOpen: $isShapeOpen) {
                        VStack(spacing: 12) {
                            shapeButtons
                            dimensionFields
                            Stepper("Qty \(piece.quantity)", value: $piece.quantity, in: 1...99)
                        }
                    }

                    collapsibleSection(title: "Drawing", isOpen: $isDrawingOpen) {
                        VStack(spacing: 12) {
                            DrawingCanvasView(piece: piece, selectedTreatment: selectedTreatment)
                                .frame(height: 320)
                            edgeTreatmentPicker
                        }
                    }

                    optionsSection

                    collapsibleSection(title: "Notes", isOpen: $isNotesOpen) {
                        TextField("Notes", text: $piece.notes, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    HStack(spacing: 12) {
                        Button("Add Another Piece") {
                            addAnotherPiece()
                        }
                        .buttonStyle(PillButtonStyle(isProminent: true))

                        Spacer()

                        Button("Delete Piece", role: .destructive) {
                            showDeletePieceConfirm = true
                        }
                        .buttonStyle(PillButtonStyle(textColor: .white, backgroundColor: .red))
                    }
                    .alert("Delete Piece?", isPresented: $showDeletePieceConfirm) {
                        Button("Delete", role: .destructive) { deletePiece() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove the piece and its details.")
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(piece.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: piece.shape) { _, newShape in
            enforceShapeDefaults(newShape)
            markUpdated()
        }
        .onAppear {
            if selectedTreatmentId == nil {
                selectedTreatmentId = treatments.first?.id
            }
        }
        .onChange(of: treatments) { _, newValue in
            if selectedTreatmentId == nil {
                selectedTreatmentId = newValue.first?.id
            }
        }
        .onChange(of: piece.name) { _, _ in markUpdated() }
        .onChange(of: piece.materialName) { _, _ in markUpdated() }
        .onChange(of: piece.thicknessRaw) { _, _ in markUpdated() }
        .onChange(of: piece.shapeRaw) { _, _ in markUpdated() }
        .onChange(of: piece.widthText) { _, _ in
            markUpdated()
            updateTriangleCurveRadiusIfNeeded()
        }
        .onChange(of: piece.heightText) { _, _ in
            markUpdated()
            updateTriangleCurveRadiusIfNeeded()
        }
        .onChange(of: piece.quantity) { _, _ in markUpdated() }
        .onChange(of: piece.notes) { _, _ in markUpdated() }
        .onChange(of: piece.cutouts.count) { _, _ in markUpdated() }
        .onChange(of: piece.curvedEdges.count) { _, _ in markUpdated() }
        .onChange(of: piece.angleCuts.count) { _, _ in markUpdated() }
        .onChange(of: piece.edgeAssignments.count) { _, _ in markUpdated() }
        .navigationDestination(item: $nextPiece) { piece in
            PieceEditorView(piece: piece)
        }
    }

    private var shapeButtons: some View {
        let availableShapes = ShapeKind.allCases.filter { $0 != .quarterCircle }
        return HStack(spacing: 10) {
            ForEach(availableShapes) { shape in
                Button(shape.displayLabel) {
                    piece.shape = shape
                }
                .buttonStyle(PillButtonStyle(isProminent: piece.shape == shape))
            }
        }
    }

    private var dimensionFields: some View {
        VStack(spacing: 12) {
            FractionTextField(title: "Width", text: $piece.widthText)
            FractionTextField(title: "Length", text: $piece.heightText)
        }
    }

    private var edgeTreatmentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap edges to assign selected treatment")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            if treatments.isEmpty {
                Text("Add edge treatments in Settings.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            Picker("Edge Treatment", selection: $selectedTreatmentId) {
                Text("None").tag(UUID?.none)
                ForEach(treatments) { treatment in
                    Text("\(treatment.abbreviation) – \(treatment.name)")
                        .tag(Optional(treatment.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var optionsSection: some View {
        collapsibleSection(title: "Options", isOpen: $isOptionsOpen) {
            VStack(spacing: 12) {
                collapsibleSubsection(title: "Cutouts", isOpen: $isCutoutsOpen) {
                    VStack(spacing: 12) {
                        cutoutButtons
                        ForEach(nonNotchCutouts.indices, id: \.self) { index in
                            let cutout = nonNotchCutouts[index]
                            collapsibleItem(
                                title: "Cutout \(letter(for: index))",
                                isOpen: Binding(
                                    get: { openCutoutIds.contains(cutout.id) },
                                    set: { isOpen in
                                        if isOpen { openCutoutIds.insert(cutout.id) } else { openCutoutIds.remove(cutout.id) }
                                    }
                                )
                            ) {
                                CutoutRow(cutout: cutout, piece: piece)
                            }
                        }
                    }
                }
                collapsibleSubsection(title: "Notches", isOpen: $isNotchesOpen) {
                    VStack(spacing: 12) {
                        notchButtons
                        ForEach(notchCutouts.indices, id: \.self) { index in
                            let cutout = notchCutouts[index]
                            collapsibleItem(
                                title: "Notch \(letter(for: index))",
                                isOpen: Binding(
                                    get: { openNotchIds.contains(cutout.id) },
                                    set: { isOpen in
                                        if isOpen { openNotchIds.insert(cutout.id) } else { openNotchIds.remove(cutout.id) }
                                    }
                                )
                            ) {
                                CutoutRow(cutout: cutout, piece: piece)
                            }
                        }
                    }
                }
                collapsibleSubsection(title: "Curves", isOpen: $isCurvesOpen) {
                    VStack(spacing: 12) {
                        curveButtons
                        ForEach(piece.curvedEdges.indices, id: \.self) { index in
                            let curve = piece.curvedEdges[index]
                            collapsibleItem(
                                title: "Curve \(letter(for: index))",
                                isOpen: Binding(
                                    get: { openCurveIds.contains(curve.id) },
                                    set: { isOpen in
                                        if isOpen { openCurveIds.insert(curve.id) } else { openCurveIds.remove(curve.id) }
                                    }
                                )
                            ) {
                                CurveRow(curve: curve, shape: piece.shape)
                            }
                        }
                    }
                }
                collapsibleSubsection(title: "Angles", isOpen: $isAnglesOpen) {
                    VStack(spacing: 12) {
                        angleButtons
                        ForEach(piece.angleCuts.indices, id: \.self) { index in
                            let angle = piece.angleCuts[index]
                            collapsibleItem(
                                title: "Angle \(letter(for: index))",
                                isOpen: Binding(
                                    get: { openAngleIds.contains(angle.id) },
                                    set: { isOpen in
                                        if isOpen { openAngleIds.insert(angle.id) } else { openAngleIds.remove(angle.id) }
                                    }
                                )
                            ) {
                                AngleCutRow(angleCut: angle, piece: piece, angleIndex: index)
                            }
                        }
                    }
                }
            }
        }
    }

    private var cutoutButtons: some View {
        HStack(spacing: 10) {
            Button("Add Cutout") {
                addCutout(kind: .circle, isNotch: false)
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private var notchButtons: some View {
        HStack(spacing: 10) {
            Button("Add Notch") {
                addCutout(kind: .rectangle, isNotch: true)
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private var curveButtons: some View {
        HStack(spacing: 10) {
            Button("Add Curve") {
                addCurve()
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private var angleButtons: some View {
        HStack(spacing: 10) {
            Button("Add Angle") {
                addAngle()
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private func addCutout(kind: CutoutKind, isNotch: Bool) {
        let size = ShapePathBuilder.pieceSize(for: piece)
        if isNotch {
            let cutout = Cutout(kind: kind, width: 1, height: 1, centerX: 0.5, centerY: 0.5, isNotch: true)
            cutout.piece = piece
            piece.cutouts.append(cutout)
            modelContext.insert(cutout)
            return
        }

        let cutout = Cutout(kind: kind, width: 3, height: 3, centerX: size.width / 2, centerY: size.height / 2, isNotch: false)
        cutout.piece = piece
        piece.cutouts.append(cutout)
        modelContext.insert(cutout)
    }

    private func addCurve() {
        let defaultEdge: EdgePosition = piece.shape == .rightTriangle ? .hypotenuse : .top
        let defaultRadius: Double = piece.shape == .rightTriangle ? triangleQuarterCircleRadius() : 2
        let curve = CurvedEdge(edge: defaultEdge, radius: defaultRadius, isConcave: false)
        curve.piece = piece
        piece.curvedEdges.append(curve)
        modelContext.insert(curve)
    }

    private func addAngle() {
        let cornerCount = ShapePathBuilder.cornerPoints(for: piece).count
        let safeIndex = cornerCount > 0 ? 0 : 0
        let cut = AngleCut(anchorCornerIndex: safeIndex, anchorOffset: 2, secondaryCornerIndex: safeIndex, secondaryOffset: 2, usesSecondPoint: true, angleDegrees: 45)
        cut.piece = piece
        piece.angleCuts.append(cut)
        modelContext.insert(cut)
    }

    private func updateTriangleCurveRadiusIfNeeded() {
        guard piece.shape == .rightTriangle else { return }
        let radius = triangleQuarterCircleRadius()
        for curve in piece.curvedEdges where curve.edge == .hypotenuse {
            curve.radius = radius
        }
    }

    private func triangleQuarterCircleRadius() -> Double {
        let width = MeasurementParser.parseInches(piece.widthText) ?? 0
        let height = MeasurementParser.parseInches(piece.heightText) ?? 0
        let targetRadius = min(width, height)
        guard targetRadius > 0 else { return 0 }

        let targetMid = targetRadius / sqrt(2)
        let dx = targetMid - (width / 2)
        let dy = targetMid - (height / 2)
        let avg = (dx + dy) / 2
        let normalScale: Double = 0.7
        return max(avg / normalScale, 0)
    }

    private func enforceShapeDefaults(_ shape: ShapeKind) {
        switch shape {
        case .circle, .quarterCircle:
            piece.heightText = piece.widthText
        default:
            break
        }
    }

    private func addAnotherPiece() {
        guard let project = piece.project else { return }
        let newPiece = Piece(name: "Piece \(project.pieces.count + 1)")
        if let lastMaterial = project.pieces.last(where: { !$0.materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.materialName {
            newPiece.materialName = lastMaterial
        }
        newPiece.project = project
        project.pieces.append(newPiece)
        modelContext.insert(newPiece)
        markUpdated()
        nextPiece = newPiece
    }

    private func deletePiece() {
        guard let project = piece.project else { return }
        project.pieces.removeAll { $0.id == piece.id }
        modelContext.delete(piece)
        markUpdated()
    }

    private var selectedTreatment: EdgeTreatment? {
        guard let selectedTreatmentId else { return nil }
        return treatments.first(where: { $0.id == selectedTreatmentId })
    }

    private func markUpdated() {
        piece.project?.updatedAt = Date()
    }


    private var nonNotchCutouts: [Cutout] {
        piece.cutouts.filter { !$0.isNotch }
    }

    private var notchCutouts: [Cutout] {
        piece.cutouts.filter { $0.isNotch }
    }

    private func letter(for index: Int) -> String {
        let scalar = UnicodeScalar(65 + (index % 26))!
        return String(Character(scalar))
    }

    @ViewBuilder
    private func collapsibleSection<Content: View>(title: String, isOpen: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOpen.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Image(systemName: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen.wrappedValue {
                content()
            }
        }
        .padding(16)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func collapsibleSubsection<Content: View>(title: String, isOpen: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOpen.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Image(systemName: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen.wrappedValue {
                content()
            }
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func collapsibleItem<Content: View>(title: String, isOpen: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOpen.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Image(systemName: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen.wrappedValue {
                content()
            }
        }
        .padding(10)
        .background(Theme.panel.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }
}

private struct FractionOption: Identifiable {
    let numerator: Int
    let denominator: Int
    let label: String

    var id: Int { numerator }
}

private func makeFractionOptions() -> [FractionOption] {
    (0...15).map { numerator in
        if numerator == 0 {
            return FractionOption(numerator: 0, denominator: 16, label: "0")
        }
        let reduced = MeasurementParser.reducedFraction(numerator: numerator, denominator: 16)
        return FractionOption(numerator: numerator, denominator: 16, label: "\(reduced.numerator)/\(reduced.denominator)")
    }
}

private struct FractionTextField: View {
    let title: String
    @Binding var text: String
    private let options = makeFractionOptions()

    @State private var wholeText = ""
    @State private var selectedNumerator = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) (in)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 10) {
                TextField("0", text: $wholeText)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: wholeText) { _, _ in
                        updateTextFromFields()
                    }

                Picker("Fraction", selection: $selectedNumerator) {
                    ForEach(options) { option in
                        Text(option.label).tag(option.numerator)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedNumerator) { _, _ in
                    updateTextFromFields()
                }
            }
        }
        .onAppear(perform: syncFromText)
        .onChange(of: text) { _, _ in
            syncFromText()
        }
    }

    private func syncFromText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            wholeText = ""
            selectedNumerator = 0
            return
        }
        let value = MeasurementParser.parseInches(trimmed) ?? 0
        let components = MeasurementParser.fractionalComponents(value, denominator: 16)
        wholeText = components.whole == 0 ? "" : String(components.whole)
        selectedNumerator = components.numerator
    }

    private func updateTextFromFields() {
        let whole = Int(wholeText) ?? 0
        let reduced = MeasurementParser.reducedFraction(numerator: selectedNumerator, denominator: 16)
        if whole == 0 && reduced.numerator == 0 {
            text = ""
            return
        }
        text = MeasurementParser.formatFractional(whole: whole, numerator: reduced.numerator, denominator: reduced.denominator, isNegative: false)
    }

}

private struct FractionNumberField: View {
    let title: String
    @Binding var value: Double
    var allowNegative: Bool = false
    var showSignToggle: Bool = false
    private let options = makeFractionOptions()

    @State private var wholeText = "0"
    @State private var selectedNumerator = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 10) {
                if showSignToggle {
                    Toggle(isOn: signBinding) {
                        Text("")
                    }
                    .toggleStyle(SignToggleStyle())
                    .frame(width: 34)
                }

                TextField("0", text: $wholeText)
                    .keyboardType(allowNegative ? .numbersAndPunctuation : .numberPad)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: wholeText) { _, _ in
                        updateValueFromFields()
                    }

                Picker("Fraction", selection: $selectedNumerator) {
                    ForEach(options) { option in
                        Text(option.label).tag(option.numerator)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedNumerator) { _, _ in
                    updateValueFromFields()
                }
            }
        }
        .onAppear(perform: syncFromValue)
        .onChange(of: value) { _, _ in
            syncFromValue()
        }
    }

    private func syncFromValue() {
        let components = MeasurementParser.fractionalComponents(value, denominator: 16)
        let sign = components.isNegative ? "-" : ""
        wholeText = "\(sign)\(components.whole)"
        selectedNumerator = components.numerator
    }

    private func updateValueFromFields() {
        let trimmed = wholeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNegative = allowNegative && trimmed.hasPrefix("-")
        let absText = trimmed.replacingOccurrences(of: "-", with: "")
        let whole = Int(absText) ?? 0
        let reduced = MeasurementParser.reducedFraction(numerator: selectedNumerator, denominator: 16)
        let fraction = Double(reduced.numerator) / Double(reduced.denominator)
        let magnitude = Double(whole) + fraction
        value = isNegative ? -magnitude : magnitude
    }

    private var signBinding: Binding<Bool> {
        Binding(
            get: { value < 0 },
            set: { isNegative in
                let magnitude = abs(value)
                value = isNegative ? -magnitude : magnitude
            }
        )
    }
}

private struct SignToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            Text(configuration.isOn ? "-" : "+")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 28, height: 28)
                .background(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CutoutRow: View {
    @Bindable var cutout: Cutout
    let piece: Piece
    @Environment(\.modelContext) private var modelContext
    @State private var selectedCorner: NotchCorner?

    private enum NotchCorner: String, CaseIterable {
        case topLeft = "Top Left"
        case topRight = "Top Right"
        case bottomLeft = "Bottom Left"
        case bottomRight = "Bottom Right"
    }

    private enum HoleShape: String, CaseIterable {
        case circle = "Circle"
        case rectangle = "Rectangle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button("Delete", role: .destructive) {
                    cutout.piece?.cutouts.removeAll { $0.id == cutout.id }
                    modelContext.delete(cutout)
                }
            }

            if !cutout.isNotch {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cutout Shape")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Picker("Cutout Shape", selection: Binding(
                        get: { cutout.kind == .circle ? HoleShape.circle : HoleShape.rectangle },
                        set: { newValue in
                            cutout.kind = (newValue == .circle) ? .circle : .rectangle
                        }
                    )) {
                        ForEach(HoleShape.allCases, id: \.self) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)

                    labeledField("Width (in)", value: $cutout.width)
                    labeledField("Length (in)", value: $cutout.height)
                    labeledField("From Left to Center (in)", value: Binding(
                        get: { cutout.centerY },
                        set: { cutout.centerY = $0 }
                    ))
                    labeledField("From Top to Center (in)", value: Binding(
                        get: { cutout.centerX },
                        set: { cutout.centerX = $0 }
                    ))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("Notch Width (in)", value: $cutout.width)
                    labeledField("Notch Length (in)", value: $cutout.height)

                    Text("Corner")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)

                    let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(NotchCorner.allCases, id: \.self) { corner in
                            sideButton(title: corner.rawValue, isSelected: selectedCorner == corner) {
                                selectedCorner = corner
                                updateNotchCorner()
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            if cutout.isNotch, selectedCorner == nil {
                selectedCorner = inferredNotchCorner()
            }
        }
        .onChange(of: cutout.width) { _, _ in
            syncSquareSizesIfNeeded()
            if cutout.isNotch {
                updateNotchCorner()
            }
        }
        .onChange(of: cutout.height) { _, _ in
            if cutout.isNotch {
                updateNotchCorner()
            }
        }
        .onChange(of: selectedCorner) { _, _ in
            if cutout.isNotch {
                updateNotchCorner()
            }
        }
    }

    private func sideButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Theme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.accent : Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Theme.accent : Theme.divider, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func labeledField(_ title: String, value: Binding<Double>, allowNegative: Bool = false, showSignToggle: Bool = false) -> some View {
        FractionNumberField(title: title, value: value, allowNegative: allowNegative, showSignToggle: showSignToggle)
    }

    private func updateNotchCorner() {
        guard cutout.kind != .circle else { return }
        guard let selectedCorner else {
            cutout.centerX = -1
            cutout.centerY = -1
            return
        }

        let displaySize = ShapePathBuilder.displaySize(for: piece)
        let displayCutout = Cutout(
            kind: cutout.kind,
            width: cutout.height,
            height: cutout.width,
            centerX: cutout.centerY,
            centerY: cutout.centerX,
            isNotch: cutout.isNotch
        )
        let halfWidth = displayCutout.width / 2
        let halfHeight = displayCutout.height / 2

        let displayCenter: CGPoint
        switch selectedCorner {
        case .topLeft:
            displayCenter = CGPoint(x: halfWidth, y: halfHeight)
        case .topRight:
            displayCenter = CGPoint(x: max(displaySize.width - halfWidth, 0), y: halfHeight)
        case .bottomLeft:
            displayCenter = CGPoint(x: halfWidth, y: max(displaySize.height - halfHeight, 0))
        case .bottomRight:
            displayCenter = CGPoint(x: max(displaySize.width - halfWidth, 0), y: max(displaySize.height - halfHeight, 0))
        }

        let rawCenter = ShapePathBuilder.rawPoint(fromDisplay: displayCenter)
        cutout.centerX = rawCenter.x
        cutout.centerY = rawCenter.y
    }

    private func inferredNotchCorner() -> NotchCorner {
        let displaySize = ShapePathBuilder.displaySize(for: piece)
        let displayCenter = ShapePathBuilder.displayPoint(fromRaw: CGPoint(x: cutout.centerX, y: cutout.centerY))
        let isTop = displayCenter.y <= displaySize.height / 2
        let isLeft = displayCenter.x <= displaySize.width / 2
        switch (isTop, isLeft) {
        case (true, true):
            return .topLeft
        case (true, false):
            return .topRight
        case (false, true):
            return .bottomLeft
        case (false, false):
            return .bottomRight
        }
    }

    private func syncSquareSizesIfNeeded() {
        if cutout.kind == .square {
            cutout.height = cutout.width
        }
    }
}

private struct CurveRow: View {
    @Bindable var curve: CurvedEdge
    let shape: ShapeKind
    @Environment(\.modelContext) private var modelContext

    private var edgeOptions: [(EdgePosition, String)] {
        switch shape {
        case .rectangle:
            return [
                (.top, "Top"),
                (.right, "Right"),
                (.bottom, "Bottom"),
                (.left, "Left")
            ]
        case .rightTriangle:
            return [
                (.legA, "Side A"),
                (.legB, "Side B"),
                (.hypotenuse, "Side C")
            ]
        default:
            return EdgePosition.allCases.map { ($0, $0.label) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Edge", selection: $curve.edgeRaw) {
                    ForEach(edgeOptions, id: \.0) { edge, label in
                        Text(label).tag(edge.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button("Delete", role: .destructive) {
                    curve.piece?.curvedEdges.removeAll { $0.id == curve.id }
                    modelContext.delete(curve)
                }
            }
            HStack(spacing: 12) {
                FractionNumberField(title: "Radius", value: $curve.radius)
                Toggle("Concave", isOn: $curve.isConcave)
            }
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct AngleCutRow: View {
    @Bindable var angleCut: AngleCut
    let piece: Piece
    let angleIndex: Int
    @Environment(\.modelContext) private var modelContext
    @State private var isUpdating = false

    var body: some View {
        let labels = cornerLabels()
        return VStack(alignment: .leading, spacing: 8) {
            deleteRow
            cornerRow(labels: labels)
            edgeDistancesRow
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }

    private var deleteRow: some View {
        HStack {
            Spacer()
            Button("Delete", role: .destructive) {
                angleCut.piece?.angleCuts.removeAll { $0.id == angleCut.id }
                modelContext.delete(angleCut)
            }
        }
    }

    private func cornerRow(labels: [String]) -> some View {
        HStack(spacing: 12) {
            cornerPickerField(title: "Corner", selection: $angleCut.anchorCornerIndex, labels: labels)
        }
    }

    private var edgeDistancesRow: some View {
        HStack(spacing: 12) {
            labeledField("Along Edge 1 (in)", value: $angleCut.anchorOffset)
            labeledField("Along Edge 2 (in)", value: $angleCut.secondaryOffset)
        }
    }

    private func labeledField(_ title: String, value: Binding<Double>, allowNegative: Bool = false, showSignToggle: Bool = false) -> some View {
        FractionNumberField(title: title, value: value, allowNegative: allowNegative, showSignToggle: showSignToggle)
    }

    private func cornerPickerField(title: String, selection: Binding<Int>, labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Picker(title, selection: selection) {
                ForEach(labels.indices, id: \.self) { index in
                    Text(labels[index]).tag(index)
                }
            }
            .pickerStyle(.menu)
        }
    }


    private func cornerLabel(for index: Int) -> String {
        var value = index
        var result = ""
        repeat {
            let remainder = value % 26
            let scalar = UnicodeScalar(65 + remainder)!
            result = String(Character(scalar)) + result
            value = (value / 26) - 1
        } while value >= 0
        return result
    }

    private func cornerLabels() -> [String] {
        let count = ShapePathBuilder.cornerPoints(for: piece, includeAngles: false, angleCutLimit: angleIndex).count
        return (0..<count).map { cornerLabel(for: $0) }
    }
}
