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
    @State private var isCurvesOpen = false
    @State private var isAnglesOpen = false
    @State private var isCornerRadiiOpen = false
    @State private var openCutoutIds: Set<UUID> = []
    @State private var openCurveIds: Set<UUID> = []
    @State private var openAngleIds: Set<UUID> = []
    @State private var openCornerRadiusIds: Set<UUID> = []
    @State private var showDeletePieceConfirm = false
    @State private var showDeleteCutoutsConfirm = false
    @State private var showDeleteCurvesConfirm = false
    @State private var showDeleteAnglesConfirm = false
    @State private var showDeleteCornerRadiiConfirm = false

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
        .onChange(of: piece.cornerRadii.count) { _, _ in markUpdated() }
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
            Button(edgeAssignmentsPresent ? "Remove All" : "Apply to All Edges") {
                if edgeAssignmentsPresent {
                    removeAllEdgeTreatments()
                } else {
                    applySelectedTreatmentToAllEdges()
                }
            }
            .buttonStyle(
                PillButtonStyle(
                    isProminent: true,
                    textColor: edgeAssignmentsPresent ? Theme.primaryText : nil,
                    backgroundColor: edgeAssignmentsPresent ? Color.red : nil
                )
            )
        }
    }

    private var optionsSection: some View {
        collapsibleSection(title: "Options", isOpen: $isOptionsOpen) {
            VStack(spacing: 12) {
                collapsibleSubsection(title: "Cutouts", isOpen: $isCutoutsOpen) {
                    VStack(spacing: 12) {
                        cutoutButtons
                        let displayCutouts = Array(piece.cutouts.reversed())
                        let cutoutCount = displayCutouts.count
                        ForEach(displayCutouts.indices, id: \.self) { index in
                            let cutout = displayCutouts[index]
                            collapsibleItem(
                                title: "Cutout \(cutoutCount - index)",
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
                collapsibleSubsection(title: "Corner Radius", isOpen: $isCornerRadiiOpen) {
                    VStack(spacing: 12) {
                        cornerRadiusButtons
                        let displayCornerRadii = piece.cornerRadii.sorted { lhs, rhs in
                            if lhs.cornerIndex == rhs.cornerIndex {
                                return lhs.id.uuidString > rhs.id.uuidString
                            }
                            return lhs.cornerIndex > rhs.cornerIndex
                        }
                        ForEach(displayCornerRadii.indices, id: \.self) { index in
                            let cornerRadius = displayCornerRadii[index]
                            let labelNumber = cornerRadius.cornerIndex >= 0 ? (cornerRadius.cornerIndex + 1) : (displayCornerRadii.count - index)
                            collapsibleItem(
                                title: "Corner \(labelNumber)",
                                isOpen: Binding(
                                    get: { openCornerRadiusIds.contains(cornerRadius.id) },
                                    set: { isOpen in
                                        if isOpen { openCornerRadiusIds.insert(cornerRadius.id) } else { openCornerRadiusIds.remove(cornerRadius.id) }
                                    }
                                )
                            ) {
                                CornerRadiusRow(cornerRadius: cornerRadius, piece: piece)
                            }
                        }
                    }
                }
                collapsibleSubsection(title: "Angles", isOpen: $isAnglesOpen) {
                    VStack(spacing: 12) {
                        angleButtons
                        let displayAngles = piece.angleCuts.sorted { lhs, rhs in
                            if lhs.anchorCornerIndex == rhs.anchorCornerIndex {
                                return lhs.id.uuidString > rhs.id.uuidString
                            }
                            return lhs.anchorCornerIndex > rhs.anchorCornerIndex
                        }
                        ForEach(displayAngles.indices, id: \.self) { index in
                            let angle = displayAngles[index]
                            let labelNumber = angle.anchorCornerIndex >= 0 ? (angle.anchorCornerIndex + 1) : (displayAngles.count - index)
                            collapsibleItem(
                                title: "Angle \(labelNumber)",
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
                collapsibleSubsection(title: "Curves", isOpen: $isCurvesOpen) {
                    VStack(spacing: 12) {
                        curveButtons
                        let displayCurves = Array(piece.curvedEdges.reversed())
                        let curveCount = displayCurves.count
                        ForEach(displayCurves.indices, id: \.self) { index in
                            let curve = displayCurves[index]
                            collapsibleItem(
                                title: "Curve \(curveCount - index)",
                                isOpen: Binding(
                                    get: { openCurveIds.contains(curve.id) },
                                    set: { isOpen in
                                        if isOpen { openCurveIds.insert(curve.id) } else { openCurveIds.remove(curve.id) }
                                    }
                                )
                            ) {
                                CurveRow(curve: curve, shape: piece.shape, piece: piece)
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
                addCutout(kind: .circle)
            }
            .buttonStyle(PillButtonStyle())
            Button("Delete All", role: .destructive) {
                showDeleteCutoutsConfirm = true
            }
            .buttonStyle(PillButtonStyle(textColor: .white, backgroundColor: .red))
            Spacer()
        }
        .alert("Delete All Cutouts?", isPresented: $showDeleteCutoutsConfirm) {
            Button("Delete", role: .destructive) { deleteAllCutouts() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all cutouts for this piece.")
        }
    }

    private var curveButtons: some View {
        HStack(spacing: 10) {
            Button("Add Curve") {
                addCurve()
            }
            .buttonStyle(PillButtonStyle())
            Button("Delete All", role: .destructive) {
                showDeleteCurvesConfirm = true
            }
            .buttonStyle(PillButtonStyle(textColor: .white, backgroundColor: .red))
            Spacer()
        }
        .alert("Delete All Curves?", isPresented: $showDeleteCurvesConfirm) {
            Button("Delete", role: .destructive) { deleteAllCurves() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all curves for this piece.")
        }
    }

    private var cornerRadiusButtons: some View {
        HStack(spacing: 10) {
            Button("Add Radius") {
                addCornerRadius()
            }
            .buttonStyle(PillButtonStyle())
            Button("Delete All", role: .destructive) {
                showDeleteCornerRadiiConfirm = true
            }
            .buttonStyle(PillButtonStyle(textColor: .white, backgroundColor: .red))
            Spacer()
        }
        .alert("Delete All Corner Radius?", isPresented: $showDeleteCornerRadiiConfirm) {
            Button("Delete", role: .destructive) { deleteAllCornerRadii() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all corner radius for this piece.")
        }
    }

    private var angleButtons: some View {
        HStack(spacing: 10) {
            Button("Add Angle") {
                addAngle()
            }
            .buttonStyle(PillButtonStyle())
            Button("Delete All", role: .destructive) {
                showDeleteAnglesConfirm = true
            }
            .buttonStyle(PillButtonStyle(textColor: .white, backgroundColor: .red))
            Spacer()
        }
        .alert("Delete All Angles?", isPresented: $showDeleteAnglesConfirm) {
            Button("Delete", role: .destructive) { deleteAllAngles() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all angles for this piece.")
        }
    }

    private func addCutout(kind: CutoutKind) {
        let size = ShapePathBuilder.pieceSize(for: piece)
        let cutout = Cutout(kind: kind, width: 3, height: 3, centerX: size.width / 2, centerY: size.height / 2, isNotch: false)
        cutout.piece = piece
        modelContext.insert(cutout)
        openCutoutIds = [cutout.id]
    }

    private func deleteAllCutouts() {
        let targets = piece.cutouts
        guard !targets.isEmpty else { return }
        for cutout in targets {
            modelContext.delete(cutout)
        }
        piece.cutouts.removeAll()
        openCutoutIds.removeAll()
        markUpdated()
    }

    private func addCurve() {
        let defaultRadius: Double = piece.shape == .rightTriangle ? triangleQuarterCircleRadius() : 2
        let maxCurves = piece.shape == .rightTriangle ? 3 : 4
        if piece.curvedEdges.count >= maxCurves {
            return
        }
        let curveIndex = piece.curvedEdges.count
        let defaultEdge: EdgePosition
        if piece.shape == .rightTriangle {
            switch curveIndex % 3 {
            case 1:
                defaultEdge = .legB
            case 2:
                defaultEdge = .legA
            default:
                defaultEdge = .hypotenuse
            }
        } else {
            switch curveIndex % 4 {
            case 1:
                defaultEdge = .right
            case 2:
                defaultEdge = .bottom
            case 3:
                defaultEdge = .left
            default:
                defaultEdge = .top
            }
        }
        let curve = CurvedEdge(edge: defaultEdge, radius: defaultRadius, isConcave: false)
        curve.piece = piece
        modelContext.insert(curve)
        openCurveIds = [curve.id]
    }

    private func deleteAllCurves() {
        let targets = piece.curvedEdges
        guard !targets.isEmpty else { return }
        for curve in targets {
            modelContext.delete(curve)
        }
        piece.curvedEdges.removeAll()
        openCurveIds.removeAll()
        markUpdated()
    }

    private func addCornerRadius() {
        let cornerCount = ShapePathBuilder.cornerLabelCount(for: piece)
        guard cornerCount > 0 else { return }
        let usedAngles = Set(piece.angleCuts.map { $0.anchorCornerIndex })
        let usedRadii = Set(piece.cornerRadii.map { $0.cornerIndex })
        let avoid = usedAngles.union(usedRadii)
        let index = nextAvailableCornerIndex(count: cornerCount, avoiding: avoid) ?? -1
        if index >= 0 {
            removeAngle(at: index)
        }
        let cornerRadius = CornerRadius(cornerIndex: index, radius: 1, isInside: false)
        cornerRadius.piece = piece
        modelContext.insert(cornerRadius)
        openCornerRadiusIds = [cornerRadius.id]
    }

    private func deleteAllCornerRadii() {
        let targets = piece.cornerRadii
        guard !targets.isEmpty else { return }
        for radius in targets {
            modelContext.delete(radius)
        }
        piece.cornerRadii.removeAll()
        openCornerRadiusIds.removeAll()
        markUpdated()
    }

    private func addAngle() {
        let cornerCount = ShapePathBuilder.cornerLabelCount(for: piece)
        guard cornerCount > 0 else { return }
        let usedAngles = Set(piece.angleCuts.map { $0.anchorCornerIndex })
        let usedRadii = Set(piece.cornerRadii.map { $0.cornerIndex })
        let avoid = usedAngles.union(usedRadii)
        let defaultCorner = nextAvailableCornerIndex(count: cornerCount, avoiding: avoid) ?? -1
        if defaultCorner >= 0 {
            removeCornerRadius(at: defaultCorner)
        }
        let angle = AngleCut(anchorCornerIndex: defaultCorner)
        angle.piece = piece
        modelContext.insert(angle)
        openAngleIds = [angle.id]
    }

    private func deleteAllAngles() {
        let targets = piece.angleCuts
        guard !targets.isEmpty else { return }
        for angle in targets {
            modelContext.delete(angle)
        }
        piece.angleCuts.removeAll()
        openAngleIds.removeAll()
        markUpdated()
    }

    private func nextAvailableCornerIndex(count: Int, avoiding: Set<Int>) -> Int? {
        guard count > 0 else { return nil }
        for index in 0..<count where !avoiding.contains(index) {
            return index
        }
        return nil
    }

    private func removeCornerRadius(at cornerIndex: Int) {
        let matching = piece.cornerRadii.filter { $0.cornerIndex == cornerIndex }
        guard !matching.isEmpty else { return }
        for radius in matching {
            modelContext.delete(radius)
        }
    }

    private func removeAngle(at cornerIndex: Int) {
        let matching = piece.angleCuts.filter { $0.anchorCornerIndex == cornerIndex }
        guard !matching.isEmpty else { return }
        for angle in matching {
            modelContext.delete(angle)
        }
    }

    private func sortedCurvedEdges() -> [CurvedEdge] {
        piece.curvedEdges.sorted { lhs, rhs in
            let leftOrder = curveEdgeOrder(lhs)
            let rightOrder = curveEdgeOrder(rhs)
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func curveEdgeOrder(_ curve: CurvedEdge) -> Int {
        switch piece.shape {
        case .rightTriangle:
            switch curve.edge {
            case .hypotenuse: return 0
            case .legB: return 1
            case .legA: return 2
            default: return 3
            }
        default:
            switch curve.edge {
            case .top: return 0
            case .right: return 1
            case .bottom: return 2
            case .left: return 3
            default: return 4
            }
        }
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
        modelContext.insert(newPiece)
        markUpdated()
        nextPiece = newPiece
    }

    private func deletePiece() {
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

    private var edgeAssignmentsPresent: Bool {
        !piece.edgeAssignments.isEmpty
    }

    private func applySelectedTreatmentToAllEdges() {
        guard let selectedTreatment else { return }
        if piece.shape == .rightTriangle {
            for edge in edgesForShape(piece.shape) {
                piece.setTreatment(selectedTreatment, for: edge, context: modelContext)
            }
        } else {
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        let segmentGroups = Dictionary(grouping: segments, by: { $0.edge })
        let hasSplitSegments = segmentGroups.contains { $0.value.count > 1 }
        if piece.shape == .rectangle, hasSplitSegments {
            for segment in segments {
                piece.setSegmentTreatment(selectedTreatment, for: segment.edge, index: segment.index, context: modelContext)
            }
        } else {
            let edgesPresent = Set(segmentGroups.keys)
            for edge in edgesForShape(piece.shape) where edgesPresent.isEmpty || edgesPresent.contains(edge) {
                piece.setTreatment(selectedTreatment, for: edge, context: modelContext)
            }
        }
        }

        let pieceSize = ShapePathBuilder.pieceSize(for: piece)
        for cutout in piece.cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 {
            for edge in edgesForCutout(cutout) {
                guard isInteriorCutoutEdge(cutout: cutout, edge: edge, pieceSize: pieceSize) else { continue }
                piece.setCutoutTreatment(selectedTreatment, for: cutout.id, edge: edge, context: modelContext)
            }
        }
        markUpdated()
    }

    private func clearSegmentTreatments(for edge: EdgePosition) {
        let toDelete = piece.edgeAssignments.filter { $0.segmentEdge?.edge == edge }
        guard !toDelete.isEmpty else { return }
        for assignment in toDelete {
            modelContext.delete(assignment)
        }
        piece.edgeAssignments.removeAll { $0.segmentEdge?.edge == edge }
    }

    private func removeAllEdgeTreatments() {
        let assignments = piece.edgeAssignments
        guard !assignments.isEmpty else { return }
        for assignment in assignments {
            modelContext.delete(assignment)
        }
        piece.edgeAssignments.removeAll()
        markUpdated()
    }

    private func edgesForShape(_ shape: ShapeKind) -> [EdgePosition] {
        switch shape {
        case .rightTriangle:
            return [.legA, .legB, .hypotenuse]
        default:
            return [.top, .right, .bottom, .left]
        }
    }

    private func edgesForCutout(_ cutout: Cutout) -> [EdgePosition] {
        switch cutout.kind {
        case .rectangle, .square:
            return [.top, .right, .bottom, .left]
        case .circle:
            return [.top]
        }
    }

    private func isInteriorCutoutEdge(cutout: Cutout, edge: EdgePosition, pieceSize: CGSize) -> Bool {
        if cutout.kind == .circle {
            return true
        }
        let displayCutout = Cutout(
            kind: cutout.kind,
            width: cutout.height,
            height: cutout.width,
            centerX: cutout.centerY,
            centerY: cutout.centerX,
            isNotch: cutout.isNotch
        )
        let displaySize = CGSize(width: pieceSize.height, height: pieceSize.width)
        let halfWidth = displayCutout.width / 2
        let halfHeight = displayCutout.height / 2
        let minX = displayCutout.centerX - halfWidth
        let maxX = displayCutout.centerX + halfWidth
        let minY = displayCutout.centerY - halfHeight
        let maxY = displayCutout.centerY + halfHeight
        let eps: CGFloat = 0.01

        switch edge {
        case .left:
            return minX > eps
        case .right:
            return maxX < displaySize.width - eps
        case .top:
            return minY > eps
        case .bottom:
            return maxY < displaySize.height - eps
        default:
            return true
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

private func makeFractionOptions(denominator: Int = 16) -> [FractionOption] {
    let maxNumerator = max(denominator - 1, 0)
    return (0...maxNumerator).map { numerator in
        if numerator == 0 {
            return FractionOption(numerator: 0, denominator: denominator, label: "0")
        }
        let reduced = MeasurementParser.reducedFraction(numerator: numerator, denominator: denominator)
        return FractionOption(numerator: numerator, denominator: denominator, label: "\(reduced.numerator)/\(reduced.denominator)")
    }
}

private func fractionSelectionComponents(_ value: Double, denominator: Int) -> (whole: Int, numerator: Int, isNegative: Bool) {
    let isNegative = value < 0
    let absValue = abs(value)
    var whole = Int(floor(absValue))
    let fraction = absValue - Double(whole)
    var numerator = Int(round(fraction * Double(denominator)))
    if numerator == denominator {
        whole += 1
        numerator = 0
    }
    return (whole, numerator, isNegative)
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

            HStack(spacing: 8) {
                TextField("0", text: $wholeText)
                    .keyboardType(.numberPad)
                    .frame(width: 52)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: wholeText) { _, _ in
                        updateTextFromFields()
                    }

                Picker(selection: $selectedNumerator) {
                    ForEach(options) { option in
                        Text(option.label)
                            .font(.system(size: 9, weight: .semibold))
                            .tag(option.numerator)
                    }
                } label: {
                    Text(selectedFractionLabelShort)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .pickerStyle(.menu)
                .controlSize(.mini)
                .frame(minWidth: 52, alignment: .leading)
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
        let components = fractionSelectionComponents(value, denominator: 16)
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

    private var selectedFractionLabelShort: String {
        if selectedNumerator == 0 { return "0" }
        let reduced = MeasurementParser.reducedFraction(numerator: selectedNumerator, denominator: 16)
        return "\(reduced.numerator)\u{2044}\(reduced.denominator)"
    }

}

private struct FractionNumberField: View {
    let title: String
    @Binding var value: Double
    var allowNegative: Bool = false
    var showSignToggle: Bool = false
    var denominator: Int = 16
    private var options: [FractionOption] { makeFractionOptions(denominator: denominator) }

    @State private var wholeText = "0"
    @State private var selectedNumerator = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 8) {
                if showSignToggle {
                    Toggle(isOn: signBinding) {
                        Text("")
                    }
                    .toggleStyle(SignToggleStyle())
                    .frame(width: 34)
                }

                TextField("0", text: $wholeText)
                    .keyboardType(allowNegative ? .numbersAndPunctuation : .numberPad)
                    .frame(width: 52)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: wholeText) { _, _ in
                        updateValueFromFields()
                    }

                Picker(selection: $selectedNumerator) {
                    ForEach(options) { option in
                        Text(option.label)
                            .font(.system(size: 9, weight: .semibold))
                            .tag(option.numerator)
                    }
                } label: {
                    Text(selectedFractionLabelShort)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .pickerStyle(.menu)
                .controlSize(.mini)
                .frame(minWidth: 52, alignment: .leading)
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
        let components = fractionSelectionComponents(value, denominator: denominator)
        let sign = components.isNegative ? "-" : ""
        wholeText = "\(sign)\(components.whole)"
        selectedNumerator = components.numerator
    }

    private func updateValueFromFields() {
        let trimmed = wholeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNegative = allowNegative && trimmed.hasPrefix("-")
        let absText = trimmed.replacingOccurrences(of: "-", with: "")
        let whole = Int(absText) ?? 0
        let reduced = MeasurementParser.reducedFraction(numerator: selectedNumerator, denominator: denominator)
        let fraction = Double(reduced.numerator) / Double(reduced.denominator)
        let magnitude = Double(whole) + fraction
        value = isNegative ? -magnitude : magnitude
    }

    private var selectedFractionLabelShort: String {
        if selectedNumerator == 0 { return "0" }
        let reduced = MeasurementParser.reducedFraction(numerator: selectedNumerator, denominator: denominator)
        return "\(reduced.numerator)\u{2044}\(reduced.denominator)"
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Cutout Shape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Picker("Cutout Shape", selection: Binding(
                    get: { cutout.kind == .circle ? HoleShape.circle : HoleShape.rectangle },
                    set: { newValue in
                        cutout.kind = (newValue == .circle) ? .circle : .rectangle
                        if newValue == .circle {
                            selectedCorner = nil
                            cutout.isNotch = false
                            cutout.cornerIndex = -1
                            cutout.cornerAnchorX = -1
                            cutout.cornerAnchorY = -1
                        } else if selectedCorner != nil {
                            updateNotchCorner()
                        }
                    }
                )) {
                    ForEach(HoleShape.allCases, id: \.self) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    labeledField("Width (in)", value: $cutout.width)
                        .frame(maxWidth: .infinity)
                    labeledField("From Left to Center (in)", value: Binding(
                        get: { cutout.centerY },
                        set: { cutout.centerY = $0 }
                    ), denominator: 32)
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 12) {
                    labeledField("Length (in)", value: $cutout.height)
                        .frame(maxWidth: .infinity)
                    labeledField("From Top to Center (in)", value: Binding(
                        get: { cutout.centerX },
                        set: { cutout.centerX = $0 }
                    ), denominator: 32)
                    .frame(maxWidth: .infinity)
                }

                if cutout.kind != .circle {
                    Text("Snap to Corner")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)

                    let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(availableCorners, id: \.self) { corner in
                            sideButton(title: corner.rawValue, isSelected: selectedCorner == corner) {
                                if selectedCorner == corner {
                                    selectedCorner = nil
                                    cutout.isNotch = false
                                    cutout.cornerIndex = -1
                                    cutout.cornerAnchorX = -1
                                    cutout.cornerAnchorY = -1
                                } else {
                                    selectedCorner = corner
                                    updateNotchCorner()
                                }
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
                let inferred = inferredNotchCorner()
                if piece.shape == .rightTriangle, inferred == .bottomRight {
                    cutout.isNotch = false
                } else {
                    selectedCorner = inferred
                }
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

    private func labeledField(_ title: String, value: Binding<Double>, allowNegative: Bool = false, showSignToggle: Bool = false, denominator: Int = 16) -> some View {
        FractionNumberField(title: title, value: value, allowNegative: allowNegative, showSignToggle: showSignToggle, denominator: denominator)
    }

    private func updateNotchCorner() {
        guard cutout.kind != .circle else { return }
        guard let selectedCorner else { return }

        cutout.isNotch = true
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
        case .bottomRight:
            displayCenter = CGPoint(x: max(displaySize.width - halfWidth, 0), y: max(displaySize.height - halfHeight, 0))
        case .bottomLeft:
            displayCenter = CGPoint(x: halfWidth, y: max(displaySize.height - halfHeight, 0))
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
        case (false, false):
            return .bottomRight
        case (false, true):
            return .bottomLeft
        }
    }

    private func syncSquareSizesIfNeeded() {
        if cutout.kind == .square {
            cutout.height = cutout.width
        }
    }

    private var availableCorners: [NotchCorner] {
        if piece.shape == .rightTriangle {
            return [.topLeft, .topRight, .bottomLeft]
        }
        return NotchCorner.allCases
    }
}

private struct CurveRow: View {
    @Bindable var curve: CurvedEdge
    let shape: ShapeKind
    let piece: Piece
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button("Delete", role: .destructive) {
                    modelContext.delete(curve)
                }
            }
            spanPickers
            HStack(spacing: 12) {
                FractionNumberField(title: "Arc Depth (in)", value: $curve.radius)
                Toggle("Concave", isOn: $curve.isConcave)
            }
        }
        .onAppear { normalizeSpanSelection() }
        .onChange(of: piece.widthText) { _, _ in
            normalizeSpanSelection()
        }
        .onChange(of: piece.heightText) { _, _ in
            normalizeSpanSelection()
        }
        .onChange(of: piece.cutouts.count) { _, _ in
            normalizeSpanSelection()
        }
        .onChange(of: curve.startCornerIndex) { _, _ in
            updateEdgeFromSpan()
        }
        .onChange(of: curve.endCornerIndex) { _, _ in
            updateEdgeFromSpan()
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var spanPickers: some View {
        let labels = spanCornerLabels()
        let labelToPolygon = spanCornerIndexMap()
        let polygonToLabel = spanPolygonToLabelMap(from: labelToPolygon)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                cornerPickerField(
                    title: "Start",
                    selection: spanBinding(
                        polygonIndex: $curve.startCornerIndex,
                        labelToPolygon: labelToPolygon,
                        polygonToLabel: polygonToLabel
                    ),
                    labels: labels,
                    dimmedIndices: []
                )
                cornerPickerField(
                    title: "End",
                    selection: spanBinding(
                        polygonIndex: $curve.endCornerIndex,
                        labelToPolygon: labelToPolygon,
                        polygonToLabel: polygonToLabel
                    ),
                    labels: labels,
                    dimmedIndices: []
                )
            }
            let inferredEdge = inferredEdgeFromSpan()
            let isSamePoint = curve.startCornerIndex == curve.endCornerIndex
            let spanIsValid = inferredEdge.map { spanPathIsValid(edge: $0) } ?? false
            if isSamePoint || (!isSamePoint && inferredEdge != nil && !spanIsValid) {
                Text("Select a Different Start or End Point")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red)
            } else if inferredEdge == nil {
                Text("Select a Different Start or End Point")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red)
            }
        }
    }

    private func spanCornerLabels() -> [String] {
        let count = spanCornerPoints().count
        return (0..<count).map { cornerLabel(for: $0) }
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

    private func normalizeSpanSelection() {
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        let count = points.count
        if count <= 1 {
            curve.startCornerIndex = 0
            curve.endCornerIndex = 0
            return
        }
        if curve.startCornerIndex < 0 || curve.startCornerIndex >= count ||
            curve.endCornerIndex < 0 || curve.endCornerIndex >= count ||
            curve.startCornerIndex == curve.endCornerIndex {
            if let defaultSpan = defaultSpanForEdge(points: points) {
                curve.startCornerIndex = defaultSpan.start
                curve.endCornerIndex = defaultSpan.end
            } else {
                curve.startCornerIndex = 0
                curve.endCornerIndex = min(1, count - 1)
            }
        }
        updateEdgeFromSpan()
    }

    private func inferredEdgeFromSpan() -> EdgePosition? {
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        guard points.count > 1 else { return nil }
        let baseBounds = piece.shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : nil
        let startIndex = curve.startCornerIndex
        let endIndex = curve.endCornerIndex
        if startIndex < 0 || endIndex < 0 || startIndex >= points.count || endIndex >= points.count { return nil }
        let start = points[startIndex]
        let end = points[endIndex]
        return edgeForSpanPoints(start: start, end: end, polygon: points, baseBounds: baseBounds)
    }

    private func updateEdgeFromSpan() {
        if let edge = inferredEdgeFromSpan(), spanPathIsValid(edge: edge) {
            curve.edgeRaw = edge.rawValue
        }
    }

    private func defaultSpanForEdge(points: [CGPoint]) -> (start: Int, end: Int)? {
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        let edgeSegments = segments.filter { $0.edge == curve.edge }
        guard let first = edgeSegments.first, let last = edgeSegments.last else { return nil }
        return (start: first.startIndex, end: last.endIndex)
    }

    private func spanPathIsValid(edge: EdgePosition) -> Bool {
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        let bounds = bounds(for: points)
        let hypotenuseBounds = piece.shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : bounds
        return ShapePathBuilder.spanPathIsValid(
            points: points,
            startIndex: curve.startCornerIndex,
            endIndex: curve.endCornerIndex,
            edge: edge,
            shape: piece.shape,
            hypotenuseBounds: hypotenuseBounds,
            bounds: bounds
        )
    }

    private func edgeForSpanPoints(start: CGPoint, end: CGPoint, polygon: [CGPoint], baseBounds: CGRect?) -> EdgePosition? {
        let bounds = baseBounds ?? bounds(for: polygon)
        let edgeTolerance: CGFloat = 0.5
        switch piece.shape {
        case .rightTriangle:
            let eps: CGFloat = 0.01
            let onLegA = abs(start.y - bounds.minY) < edgeTolerance && abs(end.y - bounds.minY) < edgeTolerance
            if onLegA { return .legA }
            let onLegB = abs(start.x - bounds.minX) < edgeTolerance && abs(end.x - bounds.minX) < edgeTolerance
            if onLegB { return .legB }
            let a = CGPoint(x: bounds.maxX, y: bounds.minY)
            let b = CGPoint(x: bounds.minX, y: bounds.maxY)
            let onHypotenuse = pointLineDistance(point: start, a: a, b: b) < eps &&
                pointLineDistance(point: end, a: a, b: b) < eps
            return onHypotenuse ? .hypotenuse : nil
        default:
            let minX = bounds.minX
            let maxX = bounds.maxX
            let minY = bounds.minY
            let maxY = bounds.maxY
            let onTop = abs(start.y - minY) < edgeTolerance && abs(end.y - minY) < edgeTolerance
            if onTop { return .top }
            let onBottom = abs(start.y - maxY) < edgeTolerance && abs(end.y - maxY) < edgeTolerance
            if onBottom { return .bottom }
            let onLeft = abs(start.x - minX) < edgeTolerance && abs(end.x - minX) < edgeTolerance
            if onLeft { return .left }
            let onRight = abs(start.x - maxX) < edgeTolerance && abs(end.x - maxX) < edgeTolerance
            if onRight { return .right }
            return nil
        }
    }

    private func bounds(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func pointLineDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let denom = max(dx * dx + dy * dy, 0.0001)
        let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / denom
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        let diffX = point.x - proj.x
        let diffY = point.y - proj.y
        return sqrt(diffX * diffX + diffY * diffY)
    }

    private func spanCornerPoints() -> [CGPoint] {
        ShapePathBuilder.cornerPoints(for: piece, includeAngles: false)
    }

    private func spanCornerIndexMap() -> [Int] {
        let labelPoints = spanCornerPoints()
        let polygonPoints = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        guard !labelPoints.isEmpty, !polygonPoints.isEmpty else { return [] }
        var used: Set<Int> = []
        var mapping: [Int] = []
        for labelPoint in labelPoints {
            var bestIndex = 0
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for (index, point) in polygonPoints.enumerated() where !used.contains(index) {
                let dx = labelPoint.x - point.x
                let dy = labelPoint.y - point.y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            used.insert(bestIndex)
            mapping.append(bestIndex)
        }
        return mapping
    }

    private func spanPolygonToLabelMap(from labelToPolygon: [Int]) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for (labelIndex, polygonIndex) in labelToPolygon.enumerated() {
            map[polygonIndex] = labelIndex
        }
        return map
    }

    private func spanBinding(
        polygonIndex: Binding<Int>,
        labelToPolygon: [Int],
        polygonToLabel: [Int: Int]
    ) -> Binding<Int> {
        Binding(
            get: {
                polygonToLabel[polygonIndex.wrappedValue] ?? 0
            },
            set: { newLabelIndex in
                if newLabelIndex >= 0 && newLabelIndex < labelToPolygon.count {
                    polygonIndex.wrappedValue = labelToPolygon[newLabelIndex]
                }
            }
        )
    }

    private func cornerPickerField(title: String, selection: Binding<Int>, labels: [String], dimmedIndices: Set<Int>) -> some View {
        let options = labels.enumerated().map { (index: $0.offset, label: $0.element) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Picker(title, selection: selection) {
                ForEach(options, id: \.index) { option in
                    let prefix = dimmedIndices.contains(option.index) ? "✓ " : ""
                    Text(prefix + option.label)
                        .tag(option.index)
                }
            }
            .pickerStyle(.menu)
        }
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
        .onAppear { normalizeCornerSelection(count: labels.count) }
        .onChange(of: angleCut.anchorCornerIndex) { _, newValue in
            if newValue < 0 { return }
            removeCornerRadius(at: newValue)
        }
        .onChange(of: labels.count) { _, newValue in
            normalizeCornerSelection(count: newValue)
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
        let radiusOccupied = Set(piece.cornerRadii.map { $0.cornerIndex })
        let curveOccupied = curveOccupiedBaseCorners()
        let disabledCorners = radiusOccupied.union(curveOccupied)
        return HStack(spacing: 12) {
            cornerPickerField(title: "Corner", selection: $angleCut.anchorCornerIndex, labels: labels, dimmedIndices: disabledCorners)
        }
    }
    
    private func curveOccupiedBaseCorners() -> Set<Int> {
        // Map polygon indices back to base corner indices
        let baseCorners = ShapePathBuilder.cornerPoints(for: piece, includeAngles: false)
        let polygonPoints = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        guard !baseCorners.isEmpty, !polygonPoints.isEmpty else { return [] }
        
        // Build reverse mapping: polygon index -> base corner index (if it's a base corner)
        var polygonToBase: [Int: Int] = [:]
        for (baseIndex, basePoint) in baseCorners.enumerated() {
            var bestPolygonIndex = 0
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for (polygonIndex, polygonPoint) in polygonPoints.enumerated() {
                let dx = basePoint.x - polygonPoint.x
                let dy = basePoint.y - polygonPoint.y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    bestPolygonIndex = polygonIndex
                }
            }
            if bestDistance < 0.01 { // Only if it's actually the same point
                polygonToBase[bestPolygonIndex] = baseIndex
            }
        }
        
        // Find base corners occupied by curve endpoints
        var occupied: Set<Int> = []
        for curve in piece.curvedEdges where curve.hasSpan {
            if let baseIndex = polygonToBase[curve.startCornerIndex] {
                occupied.insert(baseIndex)
            }
            if let baseIndex = polygonToBase[curve.endCornerIndex] {
                occupied.insert(baseIndex)
            }
        }
        return occupied
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

    private func cornerPickerField(title: String, selection: Binding<Int>, labels: [String], dimmedIndices: Set<Int>) -> some View {
        let options: [(Int, String)] = [(-1, "None")] + labels.indices.map { ($0, labels[$0]) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { option in
                    let prefix = dimmedIndices.contains(option.0) ? "✓ " : ""
                    Text(prefix + option.1)
                        .tag(option.0)
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
        let count = ShapePathBuilder.cornerLabelCount(for: piece)
        return (0..<count).map { cornerLabel(for: $0) }
    }

    private func normalizeCornerSelection(count: Int) {
        guard count > 0 else {
            angleCut.anchorCornerIndex = 0
            return
        }
        if angleCut.anchorCornerIndex == -1 {
            return
        }
        if angleCut.anchorCornerIndex >= count {
            angleCut.anchorCornerIndex = count - 1
        } else if angleCut.anchorCornerIndex < 0 {
            angleCut.anchorCornerIndex = 0
        }
    }

    private func removeCornerRadius(at cornerIndex: Int) {
        let matching = piece.cornerRadii.filter { $0.cornerIndex == cornerIndex }
        guard !matching.isEmpty else { return }
        piece.cornerRadii.removeAll { $0.cornerIndex == cornerIndex }
        for radius in matching {
            modelContext.delete(radius)
        }
    }
}

private struct CornerRadiusRow: View {
    @Bindable var cornerRadius: CornerRadius
    let piece: Piece
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let labels = cornerLabels()
        return VStack(alignment: .leading, spacing: 8) {
            deleteRow
            cornerRow(labels: labels)
            radiusRow
        }
        .onChange(of: cornerRadius.cornerIndex) { _, newValue in
            if newValue < 0 { return }
            removeAngle(at: newValue)
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
                cornerRadius.piece?.cornerRadii.removeAll { $0.id == cornerRadius.id }
                modelContext.delete(cornerRadius)
            }
        }
    }

    private func cornerRow(labels: [String]) -> some View {
        let angleOccupied = Set(piece.angleCuts.map { $0.anchorCornerIndex })
        let curveOccupied = curveOccupiedBaseCorners()
        let disabledCorners = angleOccupied.union(curveOccupied)
        return HStack(spacing: 12) {
            cornerPickerField(title: "Corner", selection: $cornerRadius.cornerIndex, labels: labels, dimmedIndices: disabledCorners)
        }
    }
    
    private func curveOccupiedBaseCorners() -> Set<Int> {
        // Map polygon indices back to base corner indices
        let baseCorners = ShapePathBuilder.cornerPoints(for: piece, includeAngles: false)
        let polygonPoints = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        guard !baseCorners.isEmpty, !polygonPoints.isEmpty else { return [] }
        
        // Build reverse mapping: polygon index -> base corner index (if it's a base corner)
        var polygonToBase: [Int: Int] = [:]
        for (baseIndex, basePoint) in baseCorners.enumerated() {
            var bestPolygonIndex = 0
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for (polygonIndex, polygonPoint) in polygonPoints.enumerated() {
                let dx = basePoint.x - polygonPoint.x
                let dy = basePoint.y - polygonPoint.y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    bestPolygonIndex = polygonIndex
                }
            }
            if bestDistance < 0.01 { // Only if it's actually the same point
                polygonToBase[bestPolygonIndex] = baseIndex
            }
        }
        
        // Find base corners occupied by curve endpoints
        var occupied: Set<Int> = []
        for curve in piece.curvedEdges where curve.hasSpan {
            if let baseIndex = polygonToBase[curve.startCornerIndex] {
                occupied.insert(baseIndex)
            }
            if let baseIndex = polygonToBase[curve.endCornerIndex] {
                occupied.insert(baseIndex)
            }
        }
        return occupied
    }

    private var radiusRow: some View {
        HStack(spacing: 12) {
            FractionNumberField(title: "Radius (in)", value: $cornerRadius.radius)
        }
    }

    private func cornerPickerField(title: String, selection: Binding<Int>, labels: [String], dimmedIndices: Set<Int>) -> some View {
        let options: [(Int, String)] = [(-1, "None")] + labels.indices.map { ($0, labels[$0]) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { option in
                    let prefix = dimmedIndices.contains(option.0) ? "✓ " : ""
                    Text(prefix + option.1)
                        .tag(option.0)
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
        let count = ShapePathBuilder.cornerLabelCount(for: piece)
        return (0..<count).map { cornerLabel(for: $0) }
    }

    private func removeAngle(at cornerIndex: Int) {
        let matching = piece.angleCuts.filter { $0.anchorCornerIndex == cornerIndex }
        guard !matching.isEmpty else { return }
        piece.angleCuts.removeAll { $0.anchorCornerIndex == cornerIndex }
        for angle in matching {
            modelContext.delete(angle)
        }
    }
}
