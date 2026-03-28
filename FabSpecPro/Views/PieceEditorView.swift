import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct PieceEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var treatments: [EdgeTreatment]
    @Query private var materials: [MaterialOption]
    @Query private var pieceDefaults: [PieceDefaults]
    @Bindable var piece: Piece
    var onNavigateToPiece: ((Piece) -> Void)?

    @State private var selectedTreatmentId: UUID?
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
    @State private var keyboardHeight: CGFloat = 0
    @State private var isKeyboardVisible = false
    @FocusState private var isMaterialNameFocused: Bool

    private let keyboardOverlapHeight: CGFloat = 200

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Drawing section pinned to top
                collapsibleSection(title: "Drawing", isOpen: $isDrawingOpen) {
                    VStack(spacing: 12) {
                        DrawingCanvasView(piece: piece, selectedTreatment: selectedTreatment)
                            .frame(height: 320)
                        edgeTreatmentPicker
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 18)
                .background(Theme.background)
                
                // Scrollable content below
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        collapsibleSection(title: "Material", isOpen: $isMaterialOpen, onClose: saveMaterialToLibraryIfNeeded) {
                            VStack(spacing: 12) {
                                TextField("Piece name", text: $piece.name, prompt: Text("Piece name").foregroundStyle(Theme.secondaryText))
                                    .foregroundStyle(Theme.primaryText)
                                    #if canImport(UIKit)
                                    .textInputAutocapitalization(.words)
                                    #endif
                                TextField("Material name", text: $piece.materialName, prompt: Text("Material name").foregroundStyle(Theme.secondaryText))
                                    .foregroundStyle(Theme.primaryText)
                                    .focused($isMaterialNameFocused)
                                    #if canImport(UIKit)
                                    .textInputAutocapitalization(.words)
                                    #endif
                                    .onSubmit {
                                        saveMaterialToLibraryIfNeeded()
                                    }
                                    .onChange(of: isMaterialNameFocused) { _, isFocused in
                                        if !isFocused {
                                            saveMaterialToLibraryIfNeeded()
                                        }
                                    }
                                HStack {
                                    Picker("Thickness", selection: $piece.thicknessRaw) {
                                        ForEach(MaterialThickness.allCases) { thickness in
                                            Text(thickness.rawValue).tag(thickness.rawValue)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    Spacer()
                                    Menu("Saved") {
                                        ForEach(materials.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { material in
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
                                    .foregroundStyle(Theme.primaryText)
                            }
                        }

                        optionsSection

                        collapsibleSection(title: "Notes", isOpen: $isNotesOpen) {
                            TextField("Notes", text: $piece.notes, prompt: Text("Notes").foregroundStyle(Theme.secondaryText), axis: .vertical)
                                .foregroundStyle(Theme.primaryText)
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .dismissKeyboardOnSwipe()
                .modifier(KeyboardOverlapModifier(isKeyboardVisible: isKeyboardVisible, keyboardHeight: keyboardHeight, overlapHeight: keyboardOverlapHeight))
            }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardState(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
            isKeyboardVisible = false
        }
        #endif
        .navigationTitle(piece.name)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
    }

    #if canImport(UIKit)
    private func updateKeyboardState(from notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let window = keyWindow()
        let screenHeight = window?.windowScene?.screen.bounds.height ?? endFrame.maxY
        let overlap = max(0, screenHeight - endFrame.origin.y)
        let safeAreaBottom = window?.safeAreaInsets.bottom ?? 0
        let adjustedHeight = max(0, overlap - safeAreaBottom)
        keyboardHeight = adjustedHeight
        isKeyboardVisible = adjustedHeight > 0
    }

    private func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return nil
    }
    #endif

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
            HStack(alignment: .top, spacing: 12) {
                Picker(selection: $selectedTreatmentId, label: edgeTreatmentPickerLabel) {
                    Text("None").tag(UUID?.none)
                    ForEach(treatments) { treatment in
                        Text("\(treatment.abbreviation) – \(treatment.name)")
                            .tag(Optional(treatment.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(edgeAssignmentsPresent ? "Remove All" : "Apply All") {
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
                .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private var edgeTreatmentPickerLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Edge Treatment")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(selectedTreatmentDisplay)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedTreatmentDisplay: String {
        if let selectedTreatment {
            return "\(selectedTreatment.abbreviation) – \(selectedTreatment.name)"
        }
        return "None"
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
                let defaultKind: CutoutKind
                if let defaults = pieceDefaults.first {
                    defaultKind = defaults.defaultCutoutShape == "Rectangle" ? .rectangle : .circle
                } else {
                    defaultKind = .circle
                }
                addCutout(kind: defaultKind)
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
        
        // Apply defaults
        var cutoutWidth: Double = 3
        var cutoutHeight: Double = 3
        if let defaults = pieceDefaults.first {
            cutoutWidth = defaults.defaultCutoutWidth
            cutoutHeight = defaults.defaultCutoutHeight
        }
        
        let cutout = Cutout(kind: kind, width: cutoutWidth, height: cutoutHeight, centerX: size.width / 2, centerY: size.height / 2, isNotch: false)
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

    /// Returns all boundary segments not already covered by an existing curve.
    private func unclaimedBoundarySegments() -> [BoundarySegment] {
        let allSegments = ShapePathBuilder.boundarySegments(for: piece)
        let existingCurves = piece.curvedEdges.filter { $0.radius > 0 }
        guard !existingCurves.isEmpty else { return allSegments }

        // Build a set of claimed (edge, segmentIndex) pairs
        var claimed: Set<String> = []
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        for curve in existingCurves {
            let edge = curve.edge
            let curveSegments = allSegments.filter { $0.edge == edge }
            for seg in curveSegments {
                if curveClaimsSegment(curve: curve, segment: seg, points: points) {
                    claimed.insert("\(edge.rawValue)_\(seg.index)")
                }
            }
        }
        let unclaimed = allSegments.filter { !claimed.contains("\($0.edge.rawValue)_\($0.index)") }
        // Sort segments in clockwise walk order within each edge:
        // top: left→right (ascending progress), right: top→bottom (ascending),
        // bottom: right→left (descending progress), left: bottom→top (descending).
        // Preserve the original edge ordering (top, right, bottom, left).
        let b = bounds(for: points)
        return unclaimed.sorted { a, aNext in
            if a.edge != aNext.edge {
                // Preserve original edge order from allSegments
                let aEdgeOrder = allSegments.firstIndex(where: { $0.edge == a.edge }) ?? 0
                let bEdgeOrder = allSegments.firstIndex(where: { $0.edge == aNext.edge }) ?? 0
                return aEdgeOrder < bEdgeOrder
            }
            let aProgress = ShapePathBuilder.edgeProgress(for: a.start, edge: a.edge, shape: piece.shape, bounds: b)
            let bProgress = ShapePathBuilder.edgeProgress(for: aNext.start, edge: aNext.edge, shape: piece.shape, bounds: b)
            // Bottom and left edges walk in reverse direction (right→left, bottom→top)
            // so sort descending to match clockwise walk order.
            if a.edge == .bottom || a.edge == .left {
                return aProgress > bProgress
            }
            return aProgress < bProgress
        }
    }

    /// Checks if a curve's span covers a given boundary segment.
    private func curveClaimsSegment(curve: CurvedEdge, segment: BoundarySegment, points: [CGPoint]) -> Bool {
        guard curve.edge == segment.edge else { return false }
        // A full-edge curve (no span) claims all segments on that edge
        if !curve.hasSpan {
            return true
        }
        guard curve.usesEdgeProgress else { return false }
        // Use coordinate-based edgeProgress for both segment and curve,
        // so they share the same reference frame (left→right for top/bottom,
        // top→bottom for left/right). The previous distance-based calculation
        // used polygon walk order which is opposite on bottom/left edges.
        let b = bounds(for: points)
        let segSP = ShapePathBuilder.edgeProgress(for: segment.start, edge: curve.edge, shape: piece.shape, bounds: b)
        let segEP = ShapePathBuilder.edgeProgress(for: segment.end, edge: curve.edge, shape: piece.shape, bounds: b)
        let segP0 = min(segSP, segEP)
        let segP1 = max(segSP, segEP)

        let curveP0 = CGFloat(min(curve.startEdgeProgress, curve.endEdgeProgress))
        let curveP1 = CGFloat(max(curve.startEdgeProgress, curve.endEdgeProgress))

        // Overlap check with tolerance
        let overlap = min(curveP1, segP1) - max(curveP0, segP0)
        return overlap > 0.01
    }

    /// Finds the next unclaimed boundary segment to use as default for a new curve.
    private func nextUnclaimedSegment() -> (edge: EdgePosition, start: Int, end: Int)? {
        let unclaimed = unclaimedBoundarySegments()
        guard let seg = unclaimed.first else { return nil }
        return (edge: seg.edge, start: seg.startIndex, end: seg.endIndex)
    }

    /// Checks whether the given curve's span overlaps any other curve on the same edge.
    private func curveOverlapsExisting(curve: CurvedEdge) -> Bool {
        let otherCurves = piece.curvedEdges.filter { $0.id != curve.id && $0.radius > 0 && $0.edge == curve.edge }
        guard !otherCurves.isEmpty else { return false }

        // Resolve this curve's progress range — if not available, can't determine overlap
        guard let myRange = resolvedCurveProgressPiece(curve) else { return false }

        for other in otherCurves {
            // Skip curves still being set up (no progress data yet)
            guard let otherRange = resolvedCurveProgressPiece(other) else { continue }

            let overlap = min(myRange.p1, otherRange.p1) - max(myRange.p0, otherRange.p0)
            if overlap > 0.01 { return true }
        }
        return false
    }

    /// Resolve edge progress for a curve, computing from corner indices if needed.
    private func resolvedCurveProgressPiece(_ c: CurvedEdge) -> (p0: CGFloat, p1: CGFloat)? {
        if c.usesEdgeProgress {
            let p0 = CGFloat(min(c.startEdgeProgress, c.endEdgeProgress))
            let p1 = CGFloat(max(c.startEdgeProgress, c.endEdgeProgress))
            if p1 - p0 > 0.001 { return (p0, p1) }
        }
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        if c.usesCornerIndices &&
           c.startCornerIndex != c.endCornerIndex &&
           c.startCornerIndex >= 0 && c.startCornerIndex < points.count &&
           c.endCornerIndex >= 0 && c.endCornerIndex < points.count {
            let startPt = points[c.startCornerIndex]
            let endPt = points[c.endCornerIndex]
            let b = bounds(for: points)
            let sp = ShapePathBuilder.edgeProgress(for: startPt, edge: c.edge, shape: piece.shape, bounds: b)
            let ep = ShapePathBuilder.edgeProgress(for: endPt, edge: c.edge, shape: piece.shape, bounds: b)
            let p0 = min(sp, ep)
            let p1 = max(sp, ep)
            if p1 - p0 > 0.001 { return (p0, p1) }
        }
        return nil
    }

    private func addCurve() {
        // Determine radius - use defaults if enabled, otherwise use shape-based default
        var curveRadius: Double = piece.shape == .rightTriangle ? triangleQuarterCircleRadius() : 2
        var curveIsConcave: Bool = false
        var defaultStartCorner: Int = -1
        var defaultEndCorner: Int = -1

        if let defaults = pieceDefaults.first {
            curveRadius = defaults.defaultCurveRadius
            curveIsConcave = defaults.defaultCurveIsConcave
            defaultStartCorner = defaults.defaultCurveStartCorner
            defaultEndCorner = defaults.defaultCurveEndCorner
        }

        // Find the next unclaimed edge segment for the default
        let unclaimed = unclaimedBoundarySegments()
        guard !unclaimed.isEmpty else { return } // No segments left to curve

        let defaultEdge: EdgePosition
        let defaultSpanStart: Int
        let defaultSpanEnd: Int

        // If user-set defaults are valid and don't overlap, use them
        if defaultStartCorner >= 0 && defaultEndCorner >= 0 && defaultStartCorner != defaultEndCorner {
            defaultEdge = unclaimed.first?.edge ?? .top
            defaultSpanStart = defaultStartCorner
            defaultSpanEnd = defaultEndCorner
        } else {
            // Pick the first unclaimed segment
            let seg = unclaimed[0]
            defaultEdge = seg.edge
            defaultSpanStart = seg.startIndex
            defaultSpanEnd = seg.endIndex
        }

        let curve = CurvedEdge(edge: defaultEdge, radius: curveRadius, isConcave: curveIsConcave)
        curve.startCornerIndex = defaultSpanStart
        curve.endCornerIndex = defaultSpanEnd

        // Compute and store edge progress immediately so the curve is fully
        // initialized before SwiftUI re-renders and validCurves() runs.
        // Without this, the new curve enters validCurves with hasSpan==false
        // and usesEdgeProgress==false, causing it to be treated as a full-edge
        // curve that knocks out other curves on the same edge.
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        if defaultSpanStart >= 0 && defaultSpanStart < points.count &&
           defaultSpanEnd >= 0 && defaultSpanEnd < points.count {
            let startPt = points[defaultSpanStart]
            let endPt = points[defaultSpanEnd]
            let dispSize = ShapePathBuilder.displaySize(for: piece)
            let polyBounds: CGRect
            if piece.shape == .rightTriangle {
                polyBounds = CGRect(origin: .zero, size: dispSize)
            } else {
                let xs = points.map(\.x)
                let ys = points.map(\.y)
                polyBounds = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                                    width: (xs.max() ?? 0) - (xs.min() ?? 0),
                                    height: (ys.max() ?? 0) - (ys.min() ?? 0))
            }
            let sp = ShapePathBuilder.edgeProgress(for: startPt, edge: defaultEdge, shape: piece.shape, bounds: polyBounds)
            let ep = ShapePathBuilder.edgeProgress(for: endPt, edge: defaultEdge, shape: piece.shape, bounds: polyBounds)
            curve.startEdgeProgress = Double(sp)
            curve.endEdgeProgress = Double(ep)

            // Also set boundary segment info
            let segments = ShapePathBuilder.boundarySegments(for: piece)
            if let startSeg = segments.first(where: { $0.startIndex == defaultSpanStart || $0.endIndex == defaultSpanStart }) {
                curve.startBoundarySegmentIndex = startSeg.index
                curve.startBoundaryIsEnd = startSeg.endIndex == defaultSpanStart
            }
            if let endSeg = segments.first(where: { $0.startIndex == defaultSpanEnd || $0.endIndex == defaultSpanEnd }) {
                curve.endBoundarySegmentIndex = endSeg.index
                curve.endBoundaryIsEnd = endSeg.endIndex == defaultSpanEnd
            }
        }

        curve.piece = piece
        modelContext.insert(curve)
        if curve.radius > 0 {
            removeCornerRadiiOnEdge(curve.edge)
        }
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
        let usedRadii = Set(piece.cornerRadii.map { $0.cornerIndex })
        var curveBlocked: Set<Int> = []
        let baseCount = ShapePathBuilder.pieceCornerCount(for: piece)
        if baseCount > 0 {
            for index in 0..<baseCount where cornerIsOnCurvedEdge(index, requireConvex: true) {
                curveBlocked.insert(index)
            }
        }
        let avoid = usedRadii.union(curveBlocked)
        
        // Use default corner if set, otherwise find next available
        var index: Int = -1
        var radiusValue: Double = 1
        var isInside: Bool = false
        
        if let defaults = pieceDefaults.first {
            radiusValue = defaults.defaultCornerRadiusValue
            isInside = defaults.defaultCornerRadiusIsInside
            
            if defaults.defaultCornerRadiusCorner >= 0 {
                // Use the default corner if it's not already used
                if !avoid.contains(defaults.defaultCornerRadiusCorner) && defaults.defaultCornerRadiusCorner < cornerCount {
                    index = defaults.defaultCornerRadiusCorner
                } else {
                    index = nextAvailableCornerIndex(count: cornerCount, avoiding: avoid) ?? -1
                }
            } else {
                index = nextAvailableCornerIndex(count: cornerCount, avoiding: avoid) ?? -1
            }
        } else {
            index = nextAvailableCornerIndex(count: cornerCount, avoiding: avoid) ?? -1
        }
        
        if index >= 0 {
            removeAngle(at: index)
        }
        
        let cornerRadius = CornerRadius(cornerIndex: index, radius: radiusValue, isInside: isInside)
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
        let avoid = usedAngles
        
        // Use default corner if set, otherwise find next available
        var defaultCorner: Int = -1
        if piece.angleCuts.isEmpty, !avoid.contains(0) {
            defaultCorner = 0
        } else {
            defaultCorner = nextAvailableCornerIndex(count: cornerCount, avoiding: avoid) ?? -1
        }
        
        let angle = AngleCut(anchorCornerIndex: defaultCorner)
        
        // Apply default sizes and degrees
        if let defaults = pieceDefaults.first {
            angle.anchorOffset = defaults.defaultAngleEdge1
            angle.secondaryOffset = defaults.defaultAngleEdge2
            angle.angleDegrees = defaults.defaultAngleDegrees
        }
        
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

    private func defaultSpanForEdge(edge: EdgePosition) -> (start: Int, end: Int)? {
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        let edgeSegments = segments.filter { $0.edge == edge }
        guard !edgeSegments.isEmpty, !points.isEmpty else { return nil }

        var candidates: [(index: Int, point: CGPoint)] = []
        for segment in edgeSegments {
            if segment.startIndex >= 0 && segment.startIndex < points.count {
                candidates.append((segment.startIndex, points[segment.startIndex]))
            }
            if segment.endIndex >= 0 && segment.endIndex < points.count {
                candidates.append((segment.endIndex, points[segment.endIndex]))
            }
        }
        guard !candidates.isEmpty else { return nil }

        let bounds = bounds(for: points)
        func extremeIndex(by key: (CGPoint) -> CGFloat, pickMax: Bool) -> Int {
            let sorted = candidates.sorted { a, b in
                let av = key(a.point)
                let bv = key(b.point)
                return pickMax ? av > bv : av < bv
            }
            return sorted.first?.index ?? candidates[0].index
        }

        switch edge {
        case .top, .legA, .bottom:
            let minIndex = extremeIndex(by: { $0.x }, pickMax: false)
            let maxIndex = extremeIndex(by: { $0.x }, pickMax: true)
            return (start: minIndex, end: maxIndex)
        case .left, .legB, .right:
            let minIndex = extremeIndex(by: { $0.y }, pickMax: false)
            let maxIndex = extremeIndex(by: { $0.y }, pickMax: true)
            return (start: minIndex, end: maxIndex)
        case .hypotenuse:
            let a = CGPoint(x: bounds.maxX, y: bounds.minY)
            let b = CGPoint(x: bounds.minX, y: bounds.maxY)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let denom = dx * dx + dy * dy
            if denom <= 0 { return (start: candidates[0].index, end: candidates[0].index) }
            func projection(_ p: CGPoint) -> CGFloat {
                ((p.x - a.x) * dx + (p.y - a.y) * dy) / denom
            }
            let minIndex = extremeIndex(by: { projection($0) }, pickMax: false)
            let maxIndex = extremeIndex(by: { projection($0) }, pickMax: true)
            return (start: minIndex, end: maxIndex)
        }
    }

    private func removeCornerRadiiOnEdge(_ edge: EdgePosition) {
        let indices = cornerIndices(on: edge, requireConvex: true)
        guard !indices.isEmpty else { return }
        for index in indices {
            removeCornerRadius(at: index)
        }
    }

    private func cornerIndices(on edge: EdgePosition, requireConvex: Bool) -> Set<Int> {
        let baseCount = ShapePathBuilder.pieceCornerCount(for: piece)
        guard baseCount > 0 else { return [] }
        let points = ShapePathBuilder.displayPolygonPointsForLabeling(for: piece, includeAngles: false)
        guard baseCount <= points.count else { return [] }
        let bounds = bounds(for: points)
        let clockwise = polygonIsClockwise(points)
        var indices = Set<Int>()
        for index in 0..<baseCount {
            if requireConvex && isConcaveCorner(points: points, index: index, clockwise: clockwise) {
                continue
            }
            if pointIsOnEdge(points[index], edge: edge, bounds: bounds, tolerance: 0.5) {
                indices.insert(index)
            }
        }
        return indices
    }

    private func cornerIsOnCurvedEdge(_ cornerIndex: Int, requireConvex: Bool) -> Bool {
        let baseCount = ShapePathBuilder.pieceCornerCount(for: piece)
        guard cornerIndex >= 0, cornerIndex < baseCount else { return false }
        let points = ShapePathBuilder.displayPolygonPointsForLabeling(for: piece, includeAngles: false)
        guard baseCount <= points.count else { return false }
        let bounds = bounds(for: points)
        let clockwise = polygonIsClockwise(points)
        if requireConvex && isConcaveCorner(points: points, index: cornerIndex, clockwise: clockwise) {
            return false
        }
        let point = points[cornerIndex]
        for curve in piece.curvedEdges where curve.radius > 0 {
            if pointIsOnEdge(point, edge: curve.edge, bounds: bounds, tolerance: 0.5) {
                return true
            }
        }
        return false
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

    private func polygonIsClockwise(_ points: [CGPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        var sum: CGFloat = 0
        for index in points.indices {
            let nextIndex = (index + 1) % points.count
            let p1 = points[index]
            let p2 = points[nextIndex]
            sum += (p2.x - p1.x) * (p2.y + p1.y)
        }
        return sum > 0
    }

    private func isConcaveCorner(points: [CGPoint], index: Int, clockwise: Bool) -> Bool {
        guard points.count > 2 else { return false }
        let count = points.count
        let prev = points[(index - 1 + count) % count]
        let curr = points[index]
        let next = points[(index + 1) % count]
        let v1 = CGPoint(x: curr.x - prev.x, y: curr.y - prev.y)
        let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
        let cross = v1.x * v2.y - v1.y * v2.x
        return clockwise ? cross > 0 : cross < 0
    }

    private func pointIsOnEdge(_ point: CGPoint, edge: EdgePosition, bounds: CGRect, tolerance: CGFloat) -> Bool {
        switch edge {
        case .top:
            return abs(point.y - bounds.minY) <= tolerance
        case .bottom:
            return abs(point.y - bounds.maxY) <= tolerance
        case .left:
            return abs(point.x - bounds.minX) <= tolerance
        case .right:
            return abs(point.x - bounds.maxX) <= tolerance
        case .legA:
            return abs(point.x - bounds.minX) <= tolerance
        case .legB:
            return abs(point.y - bounds.minY) <= tolerance
        case .hypotenuse:
            let start = CGPoint(x: bounds.minX, y: bounds.maxY)
            let end = CGPoint(x: bounds.maxX, y: bounds.minY)
            let distance = pointLineDistance(point: point, a: start, b: end)
            if distance > tolerance { return false }
            let minX = min(start.x, end.x) - tolerance
            let maxX = max(start.x, end.x) + tolerance
            let minY = min(start.y, end.y) - tolerance
            let maxY = max(start.y, end.y) + tolerance
            return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }
    }

    private func pointLineDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        if dx == 0 && dy == 0 {
            let px = point.x - a.x
            let py = point.y - a.y
            return sqrt(px * px + py * py)
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        let rx = point.x - proj.x
        let ry = point.y - proj.y
        return sqrt(rx * rx + ry * ry)
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
        curveEdgeOrder(curve.edge)
    }

    private func curveEdgeOrder(_ edge: EdgePosition) -> Int {
        switch piece.shape {
        case .rightTriangle:
            switch edge {
            case .hypotenuse: return 0
            case .legB: return 1
            case .legA: return 2
            default: return 3
            }
        default:
            switch edge {
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
        
        // Apply defaults if available
        if let defaults = pieceDefaults.first {
            // Use default material if set, otherwise fall back to last used material
            if !defaults.defaultMaterialName.isEmpty {
                newPiece.materialName = defaults.defaultMaterialName
            } else if let lastMaterial = project.pieces.last(where: { !$0.materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.materialName {
                newPiece.materialName = lastMaterial
            }
            
            // Apply other basic defaults
            if let thickness = MaterialThickness(rawValue: defaults.defaultThickness) {
                newPiece.thickness = thickness
            }
            if let shape = ShapeKind(rawValue: defaults.defaultShape) {
                newPiece.shape = shape
            }
            newPiece.widthText = defaults.defaultWidth
            newPiece.heightText = defaults.defaultHeight
            newPiece.quantity = defaults.defaultQuantity
        } else {
            // Fallback: use last material if no defaults
            if let lastMaterial = project.pieces.last(where: { !$0.materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.materialName {
                newPiece.materialName = lastMaterial
            }
        }
        
        newPiece.project = project
        modelContext.insert(newPiece)
        markUpdated()
        
        // Navigate via callback to avoid deep navigation stack
        if let onNavigateToPiece {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onNavigateToPiece(newPiece)
            }
        }
    }

    private func deletePiece() {
        modelContext.delete(piece)
        markUpdated()
        dismiss()
    }

    private var selectedTreatment: EdgeTreatment? {
        guard let selectedTreatmentId else { return nil }
        return treatments.first(where: { $0.id == selectedTreatmentId })
    }

    private func markUpdated() {
        piece.project?.updatedAt = Date()
    }

    private func saveMaterialToLibraryIfNeeded() {
        let trimmed = piece.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !materials.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            let newMaterial = MaterialOption(name: trimmed)
            modelContext.insert(newMaterial)
        }
    }

    private var edgeAssignmentsPresent: Bool {
        !piece.edgeAssignments.isEmpty
    }

    private func applySelectedTreatmentToAllEdges() {
        guard let selectedTreatment else { return }
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        let segmentGroups = Dictionary(grouping: segments, by: { $0.edge })
        let hasSplitSegments = segmentGroups.contains { $0.value.count > 1 }
        
        if hasSplitSegments {
            // When edges are split by notches, apply to each segment individually
            for segment in segments {
                piece.setSegmentTreatment(selectedTreatment, for: segment.edge, index: segment.index, context: modelContext)
            }
        } else {
            // No split segments, apply to whole edges
            let edgesPresent = Set(segmentGroups.keys)
            for edge in edgesForShape(piece.shape) where edgesPresent.isEmpty || edgesPresent.contains(edge) {
                piece.setTreatment(selectedTreatment, for: edge, context: modelContext)
            }
        }

        let pieceSize = ShapePathBuilder.pieceSize(for: piece)
        for cutout in piece.cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 {
            let isNotchOrBoundary = cutout.isNotch || ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, size: pieceSize, shape: piece.shape)
            for edge in edgesForCutout(cutout) {
                // Use different logic for notches vs interior cutouts
                let shouldApply: Bool
                if isNotchOrBoundary {
                    shouldApply = isInteriorNotchEdge(cutout: cutout, edge: edge, pieceSize: pieceSize)
                } else {
                    shouldApply = isInteriorCutoutEdge(cutout: cutout, edge: edge, pieceSize: pieceSize)
                }
                guard shouldApply else { continue }
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
            isNotch: cutout.isNotch,
            orientation: cutout.orientation
        )
        let displaySize = CGSize(width: pieceSize.height, height: pieceSize.width)
        let corners = GeometryHelpers.cutoutCornerPoints(cutout: displayCutout, size: displaySize, shape: piece.shape)
        guard corners.count == 4 else { return false }
        let start: CGPoint
        let end: CGPoint
        switch edge {
        case .top:
            start = corners[0]
            end = corners[1]
        case .right:
            start = corners[1]
            end = corners[2]
        case .bottom:
            start = corners[2]
            end = corners[3]
        case .left:
            start = corners[3]
            end = corners[0]
        default:
            return true
        }
        let eps: CGFloat = 0.001
        return pointInsidePiece(start, pieceSize: displaySize, shape: piece.shape, epsilon: eps)
            && pointInsidePiece(end, pieceSize: displaySize, shape: piece.shape, epsilon: eps)
    }

    /// Check if a notch edge is interior (not flush with piece boundary)
    private func isInteriorNotchEdge(cutout: Cutout, edge: EdgePosition, pieceSize: CGSize) -> Bool {
        let displayCutout = Cutout(
            kind: cutout.kind,
            width: cutout.height,
            height: cutout.width,
            centerX: cutout.centerY,
            centerY: cutout.centerX,
            isNotch: cutout.isNotch,
            orientation: cutout.orientation
        )
        let displaySize = CGSize(width: pieceSize.height, height: pieceSize.width)
        let corners = GeometryHelpers.cutoutCornerPoints(cutout: displayCutout, size: displaySize, shape: piece.shape)
        let bounds = GeometryHelpers.bounds(for: corners)
        let edgeEpsilon: CGFloat = 0.01

        switch edge {
        case .left:
            return bounds.minX > edgeEpsilon
        case .right:
            return bounds.maxX < displaySize.width - edgeEpsilon
        case .top:
            return bounds.minY > edgeEpsilon
        case .bottom:
            return bounds.maxY < displaySize.height - edgeEpsilon
        default:
            return true
        }
    }

    private func pointInsidePiece(_ point: CGPoint, pieceSize: CGSize, shape: ShapeKind, epsilon: CGFloat) -> Bool {
        switch shape {
        case .rightTriangle:
            if point.x < -epsilon || point.y < -epsilon { return false }
            return point.x + point.y <= pieceSize.width + epsilon
        case .rectangle:
            return point.x >= -epsilon
                && point.y >= -epsilon
                && point.x <= pieceSize.width + epsilon
                && point.y <= pieceSize.height + epsilon
        case .quarterCircle:
            if point.x < -epsilon || point.y < -epsilon { return false }
            return hypot(point.x, point.y) <= pieceSize.width + epsilon
        case .circle:
            let center = CGPoint(x: pieceSize.width / 2, y: pieceSize.height / 2)
            let radius = pieceSize.width / 2
            return hypot(point.x - center.x, point.y - center.y) <= radius + epsilon
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
    private func collapsibleSection<Content: View>(title: String, isOpen: Binding<Bool>, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    let wasOpen = isOpen.wrappedValue
                    isOpen.wrappedValue.toggle()
                    if wasOpen { onClose?() }
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
                TextField("0", text: $wholeText, prompt: Text("0").foregroundStyle(Theme.secondaryText))
                    .foregroundStyle(Theme.primaryText)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .frame(width: 52)
                    .padding(8)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.divider, lineWidth: 1))
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

                TextField("0", text: $wholeText, prompt: Text("0").foregroundStyle(Theme.secondaryText))
                    .foregroundStyle(Theme.primaryText)
                    #if canImport(UIKit)
                    .keyboardType(allowNegative ? .numbersAndPunctuation : .numberPad)
                    #endif
                    .frame(width: 52)
                    .padding(8)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.divider, lineWidth: 1))
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

private struct KeyboardOverlapModifier: ViewModifier {
    let isKeyboardVisible: Bool
    let keyboardHeight: CGFloat
    let overlapHeight: CGFloat

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        let effectiveOverlap = min(overlapHeight, keyboardHeight * 0.8)
        let bottomPadding = max(0, keyboardHeight - effectiveOverlap)
        content
            .padding(.top, isKeyboardVisible ? -effectiveOverlap : 0)
            .padding(.bottom, isKeyboardVisible ? bottomPadding : 0)
            .zIndex(isKeyboardVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
        #else
        content
        #endif
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
                HStack(spacing: 8) {
                    ForEach(HoleShape.allCases, id: \.self) { shape in
                        let isSelected = (cutout.kind == .circle && shape == .circle) || (cutout.kind != .circle && shape == .rectangle)
                        Button(shape.rawValue) {
                            cutout.kind = (shape == .circle) ? .circle : .rectangle
                            if shape == .circle {
                                selectedCorner = nil
                                cutout.isNotch = false
                                cutout.cornerIndex = -1
                                cutout.cornerAnchorX = -1
                                cutout.cornerAnchorY = -1
                            } else if selectedCorner != nil {
                                updateNotchCorner()
                            }
                        }
                        .buttonStyle(PillButtonStyle(isProminent: isSelected))
                    }
                }

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

                if piece.shape == .rightTriangle, cutout.kind != .circle {
                    Text("Orientation")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    HStack(spacing: 8) {
                        Button("Square to Legs") {
                            cutout.orientation = .legs
                            cutout.customAngleDegrees = 0
                        }
                        .buttonStyle(PillButtonStyle(isProminent: cutout.orientation == .legs))

                        Button("Square to Hypotenuse") {
                            cutout.orientation = .hypotenuse
                            cutout.customAngleDegrees = 0
                        }
                        .buttonStyle(PillButtonStyle(isProminent: cutout.orientation == .hypotenuse))

                        Button("Custom Angle") {
                            cutout.orientation = .custom
                        }
                        .buttonStyle(PillButtonStyle(isProminent: cutout.orientation == .custom))
                    }

                    if cutout.orientation == .custom {
                        HStack {
                            Text("Angle:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText)
                            TextField("0", value: Binding(
                                get: { cutout.customAngleDegrees },
                                set: { cutout.customAngleDegrees = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            Text("°")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                if cutout.kind != .circle {
                    // Snap to Corner - only for non-triangle shapes
                    if piece.shape != .rightTriangle {
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
            isNotch: cutout.isNotch,
            orientation: cutout.orientation
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
                    .foregroundStyle(Theme.primaryText)
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
                        polygonToLabel: polygonToLabel,
                        isStart: true
                    ),
                    labels: labels,
                    dimmedIndices: []
                )
                cornerPickerField(
                    title: "End",
                    selection: spanBinding(
                        polygonIndex: $curve.endCornerIndex,
                        labelToPolygon: labelToPolygon,
                        polygonToLabel: polygonToLabel,
                        isStart: false
                    ),
                    labels: labels,
                    dimmedIndices: []
                )
            }
            let inferredEdge = inferredEdgeFromSpan()
            let isSamePoint = curve.startCornerIndex == curve.endCornerIndex
            let spanIsValid = inferredEdge.map { spanPathIsValid(edge: $0) } ?? false
            let overlaps = spanIsValid && curveOverlapsExisting()
            if isSamePoint || (!isSamePoint && inferredEdge != nil && !spanIsValid) || overlaps {
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
        let polygonPoints = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        let baseCorners = ShapePathBuilder.displayPolygonPointsForLabeling(for: piece, includeAngles: false)
        
        // Map each polygon point to its nearest base corner label
        return polygonPoints.indices.map { polygonIndex in
            let point = polygonPoints[polygonIndex]
            let nearestBaseIndex = nearestCornerIndex(for: point, in: baseCorners)
            return cornerLabel(for: nearestBaseIndex)
        }
    }
    
    private func nearestCornerIndex(for point: CGPoint, in corners: [CGPoint]) -> Int {
        guard !corners.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, corner) in corners.enumerated() {
            let dx = point.x - corner.x
            let dy = point.y - corner.y
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
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

    private var polygonPointCount: Int {
        ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true).count
    }

    private func normalizeSpanSelection() {
        // Use the stable polygon (displayPolygonPoints) instead of the curve-aware
        // labeling polygon. This ensures corner indices are consistent with
        // validCurves() and syncBoundaryEndpoint(), both of which use
        // displayPolygonPoints. Using displayPolygonPointsForLabeling here causes
        // a mismatch when curves reclassify cutouts, shifting indices and producing
        // wrong edge progress values that trigger false overlap detection.
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        let count = points.count
        if count <= 1 {
            curve.startCornerIndex = 0
            curve.endCornerIndex = 0
            curve.startBoundarySegmentIndex = -1
            curve.endBoundarySegmentIndex = -1
            curve.startEdgeProgress = -1
            curve.endEdgeProgress = -1
            return
        }
        if curve.usesEdgeProgress {
            if let startIndex = resolveCornerIndex(for: curve.startEdgeProgress) {
                curve.startCornerIndex = startIndex
            }
            if let endIndex = resolveCornerIndex(for: curve.endEdgeProgress) {
                curve.endCornerIndex = endIndex
            }
        } else if curve.usesBoundaryEndpoints {
            let segments = ShapePathBuilder.boundarySegments(for: piece)
            if let startSegment = segments.first(where: { $0.edge == curve.edge && $0.index == curve.startBoundarySegmentIndex }) {
                curve.startCornerIndex = curve.startBoundaryIsEnd ? startSegment.endIndex : startSegment.startIndex
            }
            if let endSegment = segments.first(where: { $0.edge == curve.edge && $0.index == curve.endBoundarySegmentIndex }) {
                curve.endCornerIndex = curve.endBoundaryIsEnd ? endSegment.endIndex : endSegment.startIndex
            }
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
        let labelToPolygon = spanCornerIndexMap()
        let polygonToLabel = spanPolygonToLabelMap(from: labelToPolygon)
        syncBoundaryEndpoints(polygonToLabel: polygonToLabel)
        updateEdgeFromSpan()
    }

    private func syncBoundaryEndpoints(polygonToLabel: [Int: Int]) {
        _ = polygonToLabel
        syncBoundaryEndpoint(for: curve.startCornerIndex, isStart: true)
        syncBoundaryEndpoint(for: curve.endCornerIndex, isStart: false)
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
            syncBoundaryEndpoint(for: curve.startCornerIndex, isStart: true)
            syncBoundaryEndpoint(for: curve.endCornerIndex, isStart: false)

            // Delete any other curves on the same edge whose span is entirely
            // encompassed by this curve's new span. This lets the user expand a
            // curve's start/end to cover multiple segments without the old
            // per-segment curves blocking it.
            deleteEncompassedCurves(edge: edge)
        }
    }

    /// Deletes other curves on `edge` whose edge-progress range falls entirely
    /// within this curve's range. Called after the user changes start/end points.
    private func deleteEncompassedCurves(edge: EdgePosition) {
        guard curve.usesEdgeProgress else { return }
        let myP0 = min(curve.startEdgeProgress, curve.endEdgeProgress)
        let myP1 = max(curve.startEdgeProgress, curve.endEdgeProgress)
        // Need a meaningful range to encompass anything
        guard myP1 - myP0 > 0.01 else { return }

        let siblings = piece.curvedEdges.filter { $0.edge == edge && $0.id != curve.id && $0.radius > 0 }
        for sibling in siblings {
            guard sibling.usesEdgeProgress else { continue }
            let sP0 = min(sibling.startEdgeProgress, sibling.endEdgeProgress)
            let sP1 = max(sibling.startEdgeProgress, sibling.endEdgeProgress)
            // Sibling is encompassed if its entire range is within this curve's range
            let tol = 0.01
            if sP0 >= myP0 - tol && sP1 <= myP1 + tol {
                modelContext.delete(sibling)
            }
        }
    }

    private func defaultSpanForEdge(points: [CGPoint]) -> (start: Int, end: Int)? {
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        let edgeSegments = segments.filter { $0.edge == curve.edge }
        guard !edgeSegments.isEmpty else { return nil }

        var candidates: [(index: Int, point: CGPoint)] = []
        for segment in edgeSegments {
            if segment.startIndex >= 0 && segment.startIndex < points.count {
                candidates.append((segment.startIndex, points[segment.startIndex]))
            }
            if segment.endIndex >= 0 && segment.endIndex < points.count {
                candidates.append((segment.endIndex, points[segment.endIndex]))
            }
        }
        guard !candidates.isEmpty else { return nil }

        let bounds = bounds(for: points)
        func extremeIndex(by key: (CGPoint) -> CGFloat, pickMax: Bool) -> Int {
            let sorted = candidates.sorted { a, b in
                let av = key(a.point)
                let bv = key(b.point)
                return pickMax ? av > bv : av < bv
            }
            return sorted.first?.index ?? candidates[0].index
        }

        switch curve.edge {
        case .top, .legA:
            let minIndex = extremeIndex(by: { $0.x }, pickMax: false)
            let maxIndex = extremeIndex(by: { $0.x }, pickMax: true)
            return (start: minIndex, end: maxIndex)
        case .bottom:
            let minIndex = extremeIndex(by: { $0.x }, pickMax: false)
            let maxIndex = extremeIndex(by: { $0.x }, pickMax: true)
            return (start: minIndex, end: maxIndex)
        case .left, .legB:
            let minIndex = extremeIndex(by: { $0.y }, pickMax: false)
            let maxIndex = extremeIndex(by: { $0.y }, pickMax: true)
            return (start: minIndex, end: maxIndex)
        case .right:
            let minIndex = extremeIndex(by: { $0.y }, pickMax: false)
            let maxIndex = extremeIndex(by: { $0.y }, pickMax: true)
            return (start: minIndex, end: maxIndex)
        case .hypotenuse:
            let a = CGPoint(x: bounds.maxX, y: bounds.minY)
            let b = CGPoint(x: bounds.minX, y: bounds.maxY)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let denom = dx * dx + dy * dy
            if denom <= 0 { return (start: candidates[0].index, end: candidates[0].index) }
            func projection(_ p: CGPoint) -> CGFloat {
                ((p.x - a.x) * dx + (p.y - a.y) * dy) / denom
            }
            let minIndex = extremeIndex(by: { projection($0) }, pickMax: false)
            let maxIndex = extremeIndex(by: { projection($0) }, pickMax: true)
            return (start: minIndex, end: maxIndex)
        }
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

    /// Checks whether this curve's span overlaps any other curve on the same edge.
    private func curveOverlapsExisting() -> Bool {
        let otherCurves = piece.curvedEdges.filter { $0.id != curve.id && $0.radius > 0 && $0.edge == curve.edge }
        guard !otherCurves.isEmpty else { return false }

        // Resolve this curve's progress range — if not available, can't determine overlap
        guard let myRange = resolvedCurveProgress(curve) else { return false }

        for other in otherCurves {
            // Skip curves that are still being set up (no progress data yet)
            guard let otherRange = resolvedCurveProgress(other) else { continue }

            let overlap = min(myRange.p1, otherRange.p1) - max(myRange.p0, otherRange.p0)
            if overlap > 0.01 { return true }
        }
        return false
    }

    /// Resolve edge progress for a curve, computing from corner indices if needed.
    private func resolvedCurveProgress(_ c: CurvedEdge) -> (p0: CGFloat, p1: CGFloat)? {
        if c.usesEdgeProgress {
            let p0 = CGFloat(min(c.startEdgeProgress, c.endEdgeProgress))
            let p1 = CGFloat(max(c.startEdgeProgress, c.endEdgeProgress))
            if p1 - p0 > 0.001 { return (p0, p1) }
        }
        // Compute from corner indices on the fly
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        if c.usesCornerIndices &&
           c.startCornerIndex != c.endCornerIndex &&
           c.startCornerIndex >= 0 && c.startCornerIndex < points.count &&
           c.endCornerIndex >= 0 && c.endCornerIndex < points.count {
            let startPt = points[c.startCornerIndex]
            let endPt = points[c.endCornerIndex]
            let b = bounds(for: points)
            let sp = ShapePathBuilder.edgeProgress(for: startPt, edge: c.edge, shape: piece.shape, bounds: b)
            let ep = ShapePathBuilder.edgeProgress(for: endPt, edge: c.edge, shape: piece.shape, bounds: b)
            let p0 = min(sp, ep)
            let p1 = max(sp, ep)
            if p1 - p0 > 0.001 { return (p0, p1) }
        }
        return nil
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

    private func curveEdgeOrder(_ edge: EdgePosition) -> Int {
        switch piece.shape {
        case .rightTriangle:
            switch edge {
            case .hypotenuse: return 0
            case .legB: return 1
            case .legA: return 2
            default: return 3
            }
        default:
            switch edge {
            case .top: return 0
            case .right: return 1
            case .bottom: return 2
            case .left: return 3
            default: return 4
            }
        }
    }

    private func spanCornerPolygonIndices() -> [Int] {
        // Only include polygon indices that are boundary segment endpoints.
        // This excludes interior notch teeth and other vertices that don't
        // correspond to labeled corners, preventing duplicate labels in the picker.
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        var indexSet = Set<Int>()
        for seg in segments {
            indexSet.insert(seg.startIndex)
            indexSet.insert(seg.endIndex)
        }
        return indexSet.sorted()
    }

    private func spanCornerPoints() -> [CGPoint] {
        let polygonPoints = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        return spanCornerPolygonIndices().map { polygonPoints[$0] }
    }

    private func spanCornerIndexMap() -> [Int] {
        spanCornerPolygonIndices()
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
        polygonToLabel: [Int: Int],
        isStart: Bool
    ) -> Binding<Int> {
        Binding(
            get: {
                polygonToLabel[polygonIndex.wrappedValue] ?? 0
            },
            set: { newLabelIndex in
                if newLabelIndex >= 0 && newLabelIndex < labelToPolygon.count {
                    polygonIndex.wrappedValue = labelToPolygon[newLabelIndex]
                    syncBoundaryEndpoint(for: polygonIndex.wrappedValue, isStart: isStart)
                }
            }
        )
    }

    private func syncBoundaryEndpoint(for polygonIndex: Int, isStart: Bool) {
        guard let progress = edgeProgress(for: polygonIndex) else {
            if isStart {
                curve.startEdgeProgress = -1
            } else {
                curve.endEdgeProgress = -1
            }
            return
        }
        if isStart {
            curve.startEdgeProgress = Double(progress)
        } else {
            curve.endEdgeProgress = Double(progress)
        }
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        if let segment = segments.first(where: { $0.startIndex == polygonIndex || $0.endIndex == polygonIndex }) {
            let isEnd = segment.endIndex == polygonIndex
            if isStart {
                curve.startBoundarySegmentIndex = segment.index
                curve.startBoundaryIsEnd = isEnd
            } else {
                curve.endBoundarySegmentIndex = segment.index
                curve.endBoundaryIsEnd = isEnd
            }
        } else {
            if isStart {
                curve.startBoundarySegmentIndex = -1
                curve.startBoundaryIsEnd = false
            } else {
                curve.endBoundarySegmentIndex = -1
                curve.endBoundaryIsEnd = false
            }
        }
    }

    private func edgeProgress(for polygonIndex: Int) -> CGFloat? {
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        guard polygonIndex >= 0 && polygonIndex < points.count else { return nil }
        let bounds = bounds(for: points)
        return ShapePathBuilder.edgeProgress(for: points[polygonIndex], edge: curve.edge, shape: piece.shape, bounds: bounds)
    }

    private func resolveCornerIndex(for progress: Double) -> Int? {
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        guard !points.isEmpty else { return nil }
        let bounds = bounds(for: points)
        let segments = ShapePathBuilder.boundarySegments(for: piece).filter { $0.edge == curve.edge }
        guard !segments.isEmpty else { return nil }
        var endpoints: [(index: Int, progress: CGFloat)] = []
        endpoints.reserveCapacity(segments.count * 2)
        for segment in segments {
            endpoints.append((segment.startIndex, ShapePathBuilder.edgeProgress(for: segment.start, edge: curve.edge, shape: piece.shape, bounds: bounds)))
            endpoints.append((segment.endIndex, ShapePathBuilder.edgeProgress(for: segment.end, edge: curve.edge, shape: piece.shape, bounds: bounds)))
        }
        return nearestEndpointIndex(progress: CGFloat(progress), endpoints: endpoints)
    }

    private func nearestEndpointIndex(progress: CGFloat, endpoints: [(index: Int, progress: CGFloat)]) -> Int? {
        guard let first = endpoints.first else { return nil }
        var bestIndex = first.index
        var bestDistance = abs(first.progress - progress)
        for endpoint in endpoints.dropFirst() {
            let distance = abs(endpoint.progress - progress)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = endpoint.index
            }
        }
        return bestIndex
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
    @State private var isUpdatingFromDistance = false
    @State private var isUpdatingFromAngle = false

    var body: some View {
        let labels = cornerLabels()
        return VStack(alignment: .leading, spacing: 8) {
            deleteRow
            cornerRow(labels: labels)
            edgeDistancesRow
            angleDegreesRow
        }
        .onAppear { normalizeCornerSelection(count: labels.count) }
        .onChange(of: labels.count) { _, newValue in
            normalizeCornerSelection(count: newValue)
        }
        .onChange(of: angleCut.anchorOffset) { _, _ in
            updateAngleFromDistances()
        }
        .onChange(of: angleCut.secondaryOffset) { _, _ in
            updateAngleFromDistances()
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
        let disabledCorners = Set(piece.angleCuts.map { $0.anchorCornerIndex })
        return HStack(spacing: 12) {
            cornerPickerField(title: "Corner", selection: $angleCut.anchorCornerIndex, labels: labels, dimmedIndices: disabledCorners)
        }
    }
    
    private var edgeDistancesRow: some View {
        HStack(spacing: 12) {
            labeledField("Along Edge 1 (in)", value: $angleCut.anchorOffset)
            labeledField("Along Edge 2 (in)", value: $angleCut.secondaryOffset)
        }
    }

    private var angleDegreesRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Angle (°)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                TextField("Angle", value: Binding(
                    get: { angleCut.angleDegrees },
                    set: { newValue in
                        guard !isUpdatingFromDistance else { return }
                        angleCut.angleDegrees = newValue
                        updateDistancesFromAngle()
                    }
                ), format: .number)
                .foregroundStyle(Theme.primaryText)
                .padding(8)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
            }
            Spacer()
        }
    }

    private func updateAngleFromDistances() {
        guard !isUpdatingFromAngle else { return }
        isUpdatingFromDistance = true
        
        let edge1 = angleCut.anchorOffset
        let edge2 = angleCut.secondaryOffset
        
        // Calculate angle using arctangent
        // The angle is formed by the cut line relative to edge 1
        if edge1 > 0 {
            let angleRadians = atan(edge2 / edge1)
            angleCut.angleDegrees = angleRadians * 180 / .pi
        }
        
        isUpdatingFromDistance = false
    }

    private func updateDistancesFromAngle() {
        guard !isUpdatingFromDistance else { return }
        
        // Set flag BEFORE modifying distances to prevent .onChange from recalculating angle
        isUpdatingFromAngle = true
        
        let angleRadians = angleCut.angleDegrees * .pi / 180
        
        // Keep the hypotenuse length the same, adjust both edges
        let currentHypotenuse = sqrt(pow(angleCut.anchorOffset, 2) + pow(angleCut.secondaryOffset, 2))
        
        // Use a minimum hypotenuse if both are zero
        let hypotenuse = currentHypotenuse > 0 ? currentHypotenuse : 2.0
        
        // Calculate new edge distances based on angle
        let newEdge1 = hypotenuse * cos(angleRadians)
        let newEdge2 = hypotenuse * sin(angleRadians)
        
        // Only update if values are valid (positive)
        if newEdge1 > 0 && newEdge2 > 0 {
            angleCut.anchorOffset = newEdge1
            angleCut.secondaryOffset = newEdge2
        }
        
        // Reset flag after a short delay to allow .onChange to complete
        DispatchQueue.main.async {
            self.isUpdatingFromAngle = false
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
        let curveOccupied = curveOccupiedBaseCorners()
        let disabledCorners = curveOccupied
        return HStack(spacing: 12) {
            cornerPickerField(title: "Corner", selection: $cornerRadius.cornerIndex, labels: labels, dimmedIndices: disabledCorners)
        }
    }
    
    private func curveOccupiedBaseCorners() -> Set<Int> {
        // Map polygon indices back to base corner indices
        let baseCorners = ShapePathBuilder.displayPolygonPointsForLabeling(for: piece, includeAngles: false)
        let polygonPoints = ShapePathBuilder.displayPolygonPointsForLabeling(for: piece, includeAngles: true)
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

    private func polygonIsClockwise(_ points: [CGPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        var sum: CGFloat = 0
        for index in points.indices {
            let nextIndex = (index + 1) % points.count
            let p1 = points[index]
            let p2 = points[nextIndex]
            sum += (p2.x - p1.x) * (p2.y + p1.y)
        }
        return sum > 0
    }

    private func isConcaveCorner(points: [CGPoint], index: Int, clockwise: Bool) -> Bool {
        guard points.count > 2 else { return false }
        let count = points.count
        let prev = points[(index - 1 + count) % count]
        let curr = points[index]
        let next = points[(index + 1) % count]
        let v1 = CGPoint(x: curr.x - prev.x, y: curr.y - prev.y)
        let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
        let cross = v1.x * v2.y - v1.y * v2.x
        return clockwise ? cross > 0 : cross < 0
    }

    private func pointIsOnEdge(_ point: CGPoint, edge: EdgePosition, bounds: CGRect, tolerance: CGFloat) -> Bool {
        switch edge {
        case .top:
            return abs(point.y - bounds.minY) <= tolerance
        case .bottom:
            return abs(point.y - bounds.maxY) <= tolerance
        case .left:
            return abs(point.x - bounds.minX) <= tolerance
        case .right:
            return abs(point.x - bounds.maxX) <= tolerance
        case .legA:
            return abs(point.x - bounds.minX) <= tolerance
        case .legB:
            return abs(point.y - bounds.minY) <= tolerance
        case .hypotenuse:
            let start = CGPoint(x: bounds.minX, y: bounds.maxY)
            let end = CGPoint(x: bounds.maxX, y: bounds.minY)
            let distance = pointLineDistance(point: point, a: start, b: end)
            if distance > tolerance { return false }
            let minX = min(start.x, end.x) - tolerance
            let maxX = max(start.x, end.x) + tolerance
            let minY = min(start.y, end.y) - tolerance
            let maxY = max(start.y, end.y) + tolerance
            return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }
    }

    private func pointLineDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        if dx == 0 && dy == 0 {
            let px = point.x - a.x
            let py = point.y - a.y
            return sqrt(px * px + py * py)
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        let rx = point.x - proj.x
        let ry = point.y - proj.y
        return sqrt(rx * rx + ry * ry)
    }
}
