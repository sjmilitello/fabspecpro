import SwiftUI
import SwiftData

struct DrawingCanvasView: View {
    @Bindable var piece: Piece
    let selectedTreatment: EdgeTreatment?
    var isReadOnly: Bool = false
    @Environment(\.modelContext) private var modelContext
    
    private var labelFontSize: CGFloat { isReadOnly ? 7 : 9 }
    @State private var lastEdgeTapId = UUID()
    private let lengthYOffsetPoints: CGFloat = -17
    private let lengthYOffsetInches: CGFloat = 0.125
    private let noteYOffsetInches: CGFloat = 2.0
    private let noteYOffsetPoints: CGFloat = 35
    private var lengthLabelPadding: CGFloat { isReadOnly ? 14 : 28 }
    private var widthLabelPadding: CGFloat { isReadOnly ? 21 : 42 }

    var body: some View {
        GeometryReader { proxy in
            let metrics = DrawingMetrics(piece: piece, in: proxy.size)
            let rawPieceSize = ShapePathBuilder.pieceSize(for: piece)

            ZStack {
                Canvas { context, _ in
                    let path = ShapePathBuilder.path(for: piece)

                    context.drawLayer { layerContext in
                        layerContext.translateBy(x: metrics.origin.x, y: metrics.origin.y)
                        layerContext.scaleBy(x: metrics.scale, y: metrics.scale)
                        // Use consistent line width by dividing by scale (so it doesn't change with zoom)
                        let strokeWidth = 1.5 / metrics.scale
                        layerContext.stroke(path, with: .color(Theme.primaryText), lineWidth: strokeWidth)

                    for cutout in piece.cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 && !isEffectiveNotch(cutout, piece: piece, pieceSize: rawPieceSize) {
                        let displayCutout = rotatedCutout(cutout)
                        let angleCuts = localAngleCuts(for: cutout)
                        let cornerRadii = localCornerRadii(for: cutout)
                        // Use rawPieceSize for rotation angle calculation to match notch rendering
                        // The displayCutout has swapped coordinates, and rawPieceSize ensures
                        // the rotation angle is computed consistently with how notches are rendered
                        let cutoutPath = ShapePathBuilder.cutoutPath(
                            displayCutout,
                            angleCuts: angleCuts,
                            cornerRadii: cornerRadii,
                            size: rawPieceSize,
                            shape: piece.shape
                        )
                        layerContext.stroke(cutoutPath, with: .color(Theme.accent), lineWidth: strokeWidth)
                    }
                }

                for cutout in piece.cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 {
                    if isEffectiveNotch(cutout, piece: piece, pieceSize: rawPieceSize) {
                        drawNotchDimensionLabels(in: &context, cutout: cutout, metrics: metrics)
                    } else {
                        drawCutoutDimensionLabels(in: &context, cutout: cutout, metrics: metrics)
                    }
                }

                    drawDimensionLabels(in: &context, metrics: metrics)
                    drawEdgeLabels(in: &context, metrics: metrics, refreshToken: lastEdgeTapId)
                    // Only show corner labels and cutout notes in interactive mode, not in read-only thumbnails
                    if !isReadOnly {
                        drawCornerLabels(in: &context, metrics: metrics)
                    }
                    if !isReadOnly {
                        drawCutoutNotes(in: &context, metrics: metrics)
                    }
                }

                // Only show total dimensions text in interactive mode
                if !isReadOnly {
                    let expanded = expandedDisplayBounds(metrics: metrics)
                    let totalWidth = MeasurementParser.formatInches(Double(expanded.height))
                    let totalLength = MeasurementParser.formatInches(Double(expanded.width))
                    Text("\(totalWidth)\" W x \(totalLength)\" L")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                }

                // Only show interactive overlay in non-read-only mode
                if !isReadOnly {
                    EdgeTapGestureOverlay(
                        metrics: metrics,
                        piece: piece,
                        curves: piece.curvedEdges,
                        cutouts: piece.cutouts,
                        angleSegments: ShapePathBuilder.angleSegments(for: piece),
                        boundarySegments: ShapePathBuilder.boundarySegments(for: piece)
                    ) { target in
                        if piece.shape == .rightTriangle {
                            switch target.edge {
                            case .top, .right, .bottom, .left:
                                return
                            default:
                                break
                            }
                        }
                        if let selectedTreatment {
                            if let segmentIndex = target.segmentIndex {
                                if piece.segmentTreatment(for: target.edge, index: segmentIndex)?.id == selectedTreatment.id {
                                    piece.clearSegmentTreatment(for: target.edge, index: segmentIndex)
                                } else {
                                    piece.setSegmentTreatment(selectedTreatment, for: target.edge, index: segmentIndex, context: modelContext)
                                }
                            } else {
                                if piece.treatment(for: target.edge)?.id == selectedTreatment.id {
                                    piece.clearTreatment(for: target.edge)
                                } else {
                                    piece.setTreatment(selectedTreatment, for: target.edge, context: modelContext)
                                }
                            }
                        } else if let segmentIndex = target.segmentIndex {
                            piece.clearSegmentTreatment(for: target.edge, index: segmentIndex)
                        } else {
                            piece.clearTreatment(for: target.edge)
                        }
                        lastEdgeTapId = UUID()
                    } cutoutEdgeTapped: { cutoutId, edge in
                        if let selectedTreatment {
                            if piece.cutoutTreatment(for: cutoutId, edge: edge)?.id == selectedTreatment.id {
                                piece.clearCutoutTreatment(for: cutoutId, edge: edge)
                            } else {
                                piece.setCutoutTreatment(selectedTreatment, for: cutoutId, edge: edge, context: modelContext)
                            }
                        } else {
                            piece.clearCutoutTreatment(for: cutoutId, edge: edge)
                        }
                        lastEdgeTapId = UUID()
                    } angleEdgeTapped: { angleId in
                        if let selectedTreatment {
                            if piece.angleTreatment(for: angleId)?.id == selectedTreatment.id {
                                piece.clearAngleTreatment(for: angleId)
                            } else {
                                piece.setAngleTreatment(selectedTreatment, for: angleId, context: modelContext)
                            }
                        } else {
                            piece.clearAngleTreatment(for: angleId)
                        }
                        lastEdgeTapId = UUID()
                    }
                }

            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }

    private func drawDimensionLabels(in context: inout GraphicsContext, metrics: DrawingMetrics) {
        let expanded = expandedDisplayBounds(metrics: metrics)
        let curvedWidth = MeasurementParser.formatInches(Double(expanded.width))
        let curvedHeight = MeasurementParser.formatInches(Double(expanded.height))
        let lengthText = curvedWidth
        let depthText = curvedHeight
        let lengthLabel = Text("\(lengthText)\"")
            .font(.system(size: labelFontSize, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
        let depthLabel = Text("\(depthText)\"")
            .font(.system(size: labelFontSize, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
        let width = metrics.pieceSize.width * metrics.scale
        let height = metrics.pieceSize.height * metrics.scale
        let origin = metrics.origin
        let left = origin.x + expanded.minX * metrics.scale
        let right = origin.x + expanded.maxX * metrics.scale
        let top = origin.y + expanded.minY * metrics.scale
        let bottom = origin.y + expanded.maxY * metrics.scale
        switch piece.shape {
        case .rectangle, .circle, .quarterCircle:
            let sideMetrics = rectangleSideMetrics()
            let topRight = CGPoint(
                x: origin.x + width - 12,
                y: top - lengthLabelPadding + lengthYOffsetPoints - (metrics.scale * lengthYOffsetInches)
            )
            let leftBottom = CGPoint(
                x: left - widthLabelPadding,
                y: origin.y + height - 2
            )
            if piece.shape == .circle {
                let lengthPoint = CGPoint(x: origin.x + width / 2, y: top - lengthLabelPadding)
                let widthPoint = CGPoint(x: left - widthLabelPadding, y: origin.y + height / 2)
                context.draw(lengthLabel, at: lengthPoint, anchor: .center)
                context.draw(depthLabel, at: widthPoint, anchor: .center)
            } else if piece.shape == .rectangle {
                drawSegmentDimensionLabels(in: &context, metrics: metrics)
                let segmentGroups = Dictionary(grouping: ShapePathBuilder.boundarySegments(for: piece), by: { $0.edge })
                let segmentCounts: [EdgePosition: Int] = [
                    .top: segmentGroups[.top]?.count ?? (segmentGroups.isEmpty ? 1 : 0),
                    .right: segmentGroups[.right]?.count ?? (segmentGroups.isEmpty ? 1 : 0),
                    .bottom: segmentGroups[.bottom]?.count ?? (segmentGroups.isEmpty ? 1 : 0),
                    .left: segmentGroups[.left]?.count ?? (segmentGroups.isEmpty ? 1 : 0)
                ]
                let fullWidth = metrics.pieceSize.width
                let fullHeight = metrics.pieceSize.height
                if segmentCounts[.left] == 1, let leftMetric = sideMetrics[.left] {
                    let widthLabelText = "\(MeasurementParser.formatInches(Double(leftMetric.length)))\""
                    let adjustedWidthLabel = Text(widthLabelText)
                        .font(.system(size: labelFontSize, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    let centerY = origin.y + leftMetric.center.y * metrics.scale
                    context.draw(adjustedWidthLabel, at: CGPoint(x: leftBottom.x, y: centerY), anchor: .center)
                } else {
                    if segmentCounts[.left] == 1 {
                        let widthPoint = CGPoint(x: left - widthLabelPadding, y: origin.y + height / 2)
                        context.draw(depthLabel, at: widthPoint, anchor: .center)
                    }
                }

                if segmentCounts[.top] == 1, let topMetric = sideMetrics[.top] {
                    let lengthLabelText = "\(MeasurementParser.formatInches(Double(topMetric.length)))\""
                    let adjustedLengthLabel = Text(lengthLabelText)
                        .font(.system(size: labelFontSize, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    let centerX = origin.x + topMetric.center.x * metrics.scale
                    context.draw(adjustedLengthLabel, at: CGPoint(x: centerX, y: topRight.y), anchor: .center)
                } else {
                    if segmentCounts[.top] == 1 {
                        let lengthPoint = CGPoint(x: origin.x + width / 2, y: top - lengthLabelPadding)
                        context.draw(lengthLabel, at: lengthPoint, anchor: .center)
                    }
                }

                if segmentCounts[.right] == 1, let rightMetric = sideMetrics[.right], abs(rightMetric.length - fullHeight) > 0.01 {
                    let widthLabelText = "\(MeasurementParser.formatInches(Double(rightMetric.length)))\""
                    let adjustedWidthLabel = Text(widthLabelText)
                        .font(.system(size: labelFontSize, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    let centerY = origin.y + rightMetric.center.y * metrics.scale
                    let rightPoint = CGPoint(x: right + widthLabelPadding, y: centerY)
                    context.draw(adjustedWidthLabel, at: rightPoint, anchor: .center)
                }

                if segmentCounts[.bottom] == 1, let bottomMetric = sideMetrics[.bottom], abs(bottomMetric.length - fullWidth) > 0.01 {
                    let lengthLabelText = "\(MeasurementParser.formatInches(Double(bottomMetric.length)))\""
                    let adjustedLengthLabel = Text(lengthLabelText)
                        .font(.system(size: labelFontSize, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    let centerX = origin.x + bottomMetric.center.x * metrics.scale
                    let bottomPoint = CGPoint(x: centerX, y: bottom + lengthLabelPadding)
                    context.draw(adjustedLengthLabel, at: bottomPoint, anchor: .center)
                }
            } else {
                let lengthPoint = CGPoint(x: origin.x + width / 2, y: top - lengthLabelPadding)
                let widthPoint = CGPoint(x: left - widthLabelPadding, y: origin.y + height / 2)
                context.draw(lengthLabel, at: lengthPoint, anchor: .center)
                context.draw(depthLabel, at: widthPoint, anchor: .center)
            }
        case .rightTriangle:
            // Draw segment labels for split edges (when notches create multiple segments)
            drawSegmentDimensionLabels(in: &context, metrics: metrics)
            
            // Check if edges are split into multiple segments by notches
            let segmentGroups = Dictionary(grouping: ShapePathBuilder.boundarySegments(for: piece), by: { $0.edge })
            let segmentCounts: [EdgePosition: Int] = [
                .legA: segmentGroups[.legA]?.count ?? (segmentGroups.isEmpty ? 1 : 0),
                .legB: segmentGroups[.legB]?.count ?? (segmentGroups.isEmpty ? 1 : 0),
                .hypotenuse: segmentGroups[.hypotenuse]?.count ?? (segmentGroups.isEmpty ? 1 : 0)
            ]
            
            // Only draw full leg labels if the edge is not split into multiple segments
            if segmentCounts[.legA] == 1 {
                let legALabel = lengthLabel
                let lengthPoint = CGPoint(x: origin.x + width / 2, y: top - lengthLabelPadding)
                context.draw(legALabel, at: lengthPoint, anchor: .center)
            }
            
            if segmentCounts[.legB] == 1 {
                let legBLabel = depthLabel
                let widthPoint = CGPoint(x: left - widthLabelPadding, y: origin.y + height / 2)
                context.draw(legBLabel, at: widthPoint, anchor: .center)
            }
        }
    }

    private func expandedDisplayBounds(metrics: DrawingMetrics) -> CGRect {
        if piece.shape == .circle || piece.shape == .quarterCircle {
            let size = ShapePathBuilder.displaySize(for: piece)
            return CGRect(origin: .zero, size: size)
        }
        let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        guard !polygon.isEmpty else { return .zero }
        var bounds = bounds(for: polygon)
        let convexCurves = piece.curvedEdges.filter { $0.radius > 0 && !$0.isConcave }
        if convexCurves.isEmpty { return bounds }
        let baseBounds = piece.shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : nil
        for curve in convexCurves {
            guard let geometry = edgeGeometryFromPolygon(edge: curve.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds) else { continue }
            let control = controlPointDisplay(for: geometry, curve: curve)
            for index in 0...24 {
                let t = CGFloat(index) / 24
                let point = quadBezierPoint(t: t, start: geometry.start, control: control, end: geometry.end)
                bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
            }
        }
        return bounds
    }

    private func curveOutset(for edge: EdgePosition) -> CGFloat {
        piece.curvedEdges
            .filter { $0.edge == edge && !$0.isConcave }
            .map { CGFloat($0.radius) }
            .max() ?? 0
    }

    private func drawCornerLabels(in context: inout GraphicsContext, metrics: DrawingMetrics) {
        let pieceCorners = ShapePathBuilder.cornerPoints(for: piece, includeAngles: false)
        guard !pieceCorners.isEmpty else { return }
        let origin = metrics.origin
        let scale = metrics.scale
        let baseLabelOffset: CGFloat = 10
        let hypotenuseLabelOffset: CGFloat = 16  // Extra offset for points on the hypotenuse

        let pieceBounds = bounds(for: pieceCorners)
        let baseCorners = baseShapeCorners()
        let pieceCenter = CGPoint(x: (pieceBounds.minX + pieceBounds.maxX) / 2, y: (pieceBounds.minY + pieceBounds.maxY) / 2)
        let basePolygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: false, includeNotches: false)
        let baseBounds = basePolygon.isEmpty ? pieceBounds : bounds(for: basePolygon)
        let baseCenter = CGPoint(x: (baseBounds.minX + baseBounds.maxX) / 2, y: (baseBounds.minY + baseBounds.maxY) / 2)
        let isPieceClockwise = polygonIsClockwise(pieceCorners)

        for (index, point) in pieceCorners.enumerated() {
            let label = Text(cornerLabel(for: index))
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            let isConcave = isConcaveCorner(points: pieceCorners, index: index, clockwise: isPieceClockwise)
            
            // Check if this is a notch corner first - notch corners get special diagonal directions
            let notchDirection = notchCornerDirectionIfApplicable(point: point)
            let concaveDirection = concaveCornerDirection(
                point: point,
                bounds: pieceBounds,
                shape: piece.shape,
                isConcave: isConcave
            )
            let baseDirection = isBaseCorner(point: point, baseCorners: baseCorners, tolerance: 0.5)
                ? unitVector(from: baseCenter, to: point)
                : nil
            let direction = notchDirection
                ?? concaveDirection
                ?? baseDirection
                ?? cornerLabelDirection(points: pieceCorners, index: index, center: pieceCenter, clockwise: isPieceClockwise)
            
            // For points on the hypotenuse that are NOT notch corners or concave corners,
            // use the hypotenuse outward normal direction to push the label perpendicular to the line.
            // Concave corners (like F and G from notch cutouts) should use their diagonal direction instead.
            var finalDirection = direction
            var labelOffset: CGFloat = baseLabelOffset
            var basePoint = point

            let boundaryEdges = edgesContaining(point: point, bounds: pieceBounds, shape: piece.shape, tolerance: 0.5)
            if let curvedEdge = boundaryEdges.first(where: { piece.curve(for: $0)?.radius ?? 0 > 0 }),
               let curve = piece.curve(for: curvedEdge),
               let geometry = fullEdgeGeometryDisplay(edge: curvedEdge) {
                let t = edgeProgress(point: point, geometry: geometry, edge: curvedEdge)
                let control = controlPointDisplay(for: geometry, curve: curve)
                let curvePoint = quadBezierPoint(t: t, start: geometry.start, control: control, end: geometry.end)
                let normal = normalized(geometry.normal)
                finalDirection = curve.isConcave ? CGPoint(x: -normal.x, y: -normal.y) : normal
                labelOffset = curvedEdge == .hypotenuse ? hypotenuseLabelOffset : baseLabelOffset
                basePoint = curvePoint
            } else {
                var curveOffset = curveOffsetVector(
                    for: point,
                    points: pieceCorners,
                    baseCorners: baseCorners,
                    bounds: pieceBounds,
                    shape: piece.shape
                )
                var overrideDirection: CGPoint?
                if notchDirection != nil {
                    if !boundaryEdges.isEmpty {
                        var sum = CGPoint.zero
                        for edge in boundaryEdges {
                            let normal = edgeNormal(for: edge, shape: piece.shape)
                            sum.x += normal.x
                            sum.y += normal.y
                        }
                        overrideDirection = normalized(sum)
                    }
                }
                if let overrideDirection {
                    finalDirection = overrideDirection
                    labelOffset = 8
                    curveOffset = .zero
                } else if piece.shape == .rightTriangle && notchDirection == nil && concaveDirection == nil && isPointOnHypotenuse(point: point, pieceSize: metrics.pieceSize) {
                    // Hypotenuse normal points outward (toward bottom-right)
                    finalDirection = hypotenuseOutwardNormal(pieceSize: metrics.pieceSize)
                    labelOffset = hypotenuseLabelOffset
                }
                basePoint = CGPoint(x: basePoint.x + curveOffset.x, y: basePoint.y + curveOffset.y)
            }

            let displayPoint = CGPoint(
                x: origin.x + basePoint.x * scale + finalDirection.x * labelOffset,
                y: origin.y + basePoint.y * scale + finalDirection.y * labelOffset
            )
            context.draw(label, at: displayPoint, anchor: .center)
        }

        for entry in ShapePathBuilder.cutoutCornerRanges(for: piece) {
            let displayCutout = rotatedCutout(entry.cutout)
            let corners = cutoutCornerPoints(for: displayCutout)
            let bounds = bounds(for: corners)
            let center = CGPoint(x: (bounds.minX + bounds.maxX) / 2, y: (bounds.minY + bounds.maxY) / 2)
            _ = polygonIsClockwise(corners)
            for (localIndex, point) in corners.enumerated() {
                let labelIndex = entry.range.lowerBound + localIndex
                let label = Text(cornerLabel(for: labelIndex))
                    .font(.system(size: labelFontSize, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                let direction = unitVector(from: center, to: point)
                let labelOffset = baseLabelOffset
                let displayPoint = CGPoint(
                    x: origin.x + point.x * scale + direction.x * labelOffset,
                    y: origin.y + point.y * scale + direction.y * labelOffset
                )
                context.draw(label, at: displayPoint, anchor: .center)
            }
        }
    }

    private func curveOffsetVector(for point: CGPoint, points: [CGPoint], baseCorners: [CGPoint], bounds: CGRect, shape: ShapeKind) -> CGPoint {
        if isBaseCorner(point: point, baseCorners: baseCorners, tolerance: 0.5) {
            return .zero
        }
        let edges = edgesContaining(point: point, bounds: bounds, shape: shape, tolerance: 0.5)
        guard !edges.isEmpty else { return .zero }
        var offset = CGPoint.zero
        for edge in edges {
            let radius = maxConvexCurveRadius(for: edge, point: point, points: points, baseCorners: baseCorners, bounds: bounds, shape: shape)
            if radius <= 0 { continue }
            let normal = edgeNormal(for: edge, shape: shape)
            offset.x += normal.x * radius
            offset.y += normal.y * radius
        }
        return offset
    }

    private func isBaseCorner(point: CGPoint, baseCorners: [CGPoint], tolerance: CGFloat) -> Bool {
        for corner in baseCorners {
            if abs(point.x - corner.x) <= tolerance, abs(point.y - corner.y) <= tolerance {
                return true
            }
        }
        return false
    }

    private func baseShapeCorners() -> [CGPoint] {
        let size = ShapePathBuilder.pieceSize(for: piece)
        switch piece.shape {
        case .rectangle:
            let rawPoints = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: size.width, y: 0),
                CGPoint(x: size.width, y: size.height),
                CGPoint(x: 0, y: size.height)
            ]
            return rawPoints.map { ShapePathBuilder.displayPoint(fromRaw: $0) }
        case .rightTriangle:
            let rawPoints = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: size.width, y: 0),
                CGPoint(x: 0, y: size.height)
            ]
            return rawPoints.map { ShapePathBuilder.displayPoint(fromRaw: $0) }
        default:
            return []
        }
    }

    private func maxConvexCurveRadius(for edge: EdgePosition, point: CGPoint, points: [CGPoint], baseCorners: [CGPoint], bounds: CGRect, shape: ShapeKind) -> CGFloat {
        var maxRadius: CGFloat = 0
        for curve in piece.curvedEdges where curve.edge == edge && curve.radius > 0 && !curve.isConcave {
            if curve.hasSpan, !curveSpanContains(point: point, curve: curve, points: points, baseCorners: baseCorners, bounds: bounds, shape: shape) {
                continue
            }
            maxRadius = max(maxRadius, CGFloat(curve.radius))
        }
        return maxRadius
    }

    private func curveSpanContains(point: CGPoint, curve: CurvedEdge, points: [CGPoint], baseCorners: [CGPoint], bounds: CGRect, shape: ShapeKind) -> Bool {
        guard curve.hasSpan else { return true }
        guard let range = curveSpanProgressRange(curve: curve, baseCorners: baseCorners, bounds: bounds, shape: shape) else { return true }
        let progress = ShapePathBuilder.edgeProgress(for: point, edge: curve.edge, shape: shape, bounds: bounds)
        let minProgress = min(range.start, range.end) - 0.001
        let maxProgress = max(range.start, range.end) + 0.001
        return progress >= minProgress && progress <= maxProgress
    }

    private func curveSpanProgressRange(curve: CurvedEdge, baseCorners: [CGPoint], bounds: CGRect, shape: ShapeKind) -> (start: CGFloat, end: CGFloat)? {
        if curve.usesEdgeProgress {
            return (CGFloat(curve.startEdgeProgress), CGFloat(curve.endEdgeProgress))
        }
        if curve.usesBoundaryEndpoints {
            let segments = ShapePathBuilder.boundarySegments(for: piece)
            guard let startSegment = segments.first(where: { $0.edge == curve.edge && $0.index == curve.startBoundarySegmentIndex }),
                  let endSegment = segments.first(where: { $0.edge == curve.edge && $0.index == curve.endBoundarySegmentIndex }) else {
                return nil
            }
            let startPoint = curve.startBoundaryIsEnd ? startSegment.end : startSegment.start
            let endPoint = curve.endBoundaryIsEnd ? endSegment.end : endSegment.start
            let startProgress = ShapePathBuilder.edgeProgress(for: startPoint, edge: curve.edge, shape: shape, bounds: bounds)
            let endProgress = ShapePathBuilder.edgeProgress(for: endPoint, edge: curve.edge, shape: shape, bounds: bounds)
            return (startProgress, endProgress)
        }
        if curve.usesCornerIndices {
            guard curve.startCornerIndex >= 0,
                  curve.startCornerIndex < baseCorners.count,
                  curve.endCornerIndex >= 0,
                  curve.endCornerIndex < baseCorners.count else {
                return nil
            }
            let startPoint = baseCorners[curve.startCornerIndex]
            let endPoint = baseCorners[curve.endCornerIndex]
            let startProgress = ShapePathBuilder.edgeProgress(for: startPoint, edge: curve.edge, shape: shape, bounds: bounds)
            let endProgress = ShapePathBuilder.edgeProgress(for: endPoint, edge: curve.edge, shape: shape, bounds: bounds)
            return (startProgress, endProgress)
        }
        return nil
    }

    private func edgesContaining(point: CGPoint, bounds: CGRect, shape: ShapeKind, tolerance: CGFloat) -> [EdgePosition] {
        switch shape {
        case .rectangle:
            var edges: [EdgePosition] = []
            if abs(point.y - bounds.minY) <= tolerance { edges.append(.top) }
            if abs(point.y - bounds.maxY) <= tolerance { edges.append(.bottom) }
            if abs(point.x - bounds.minX) <= tolerance { edges.append(.left) }
            if abs(point.x - bounds.maxX) <= tolerance { edges.append(.right) }
            return edges
        case .rightTriangle:
            var edges: [EdgePosition] = []
            if abs(point.y - bounds.minY) <= tolerance { edges.append(.legA) }
            if abs(point.x - bounds.minX) <= tolerance { edges.append(.legB) }
            let a = CGPoint(x: bounds.maxX, y: bounds.minY)
            let b = CGPoint(x: bounds.minX, y: bounds.maxY)
            let distanceToHypotenuse = pointLineDistance(point: point, a: a, b: b)
            if distanceToHypotenuse <= tolerance {
                let minX = min(a.x, b.x) - tolerance
                let maxX = max(a.x, b.x) + tolerance
                let minY = min(a.y, b.y) - tolerance
                let maxY = max(a.y, b.y) + tolerance
                if point.x >= minX, point.x <= maxX, point.y >= minY, point.y <= maxY {
                    edges.append(.hypotenuse)
                }
            }
            return edges
        default:
            return []
        }
    }

    private func edgeNormal(for edge: EdgePosition, shape: ShapeKind) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: 0, y: -1)
        case .right: return CGPoint(x: 1, y: 0)
        case .bottom: return CGPoint(x: 0, y: 1)
        case .left: return CGPoint(x: -1, y: 0)
        case .legA: return CGPoint(x: 0, y: -1)
        case .legB: return CGPoint(x: -1, y: 0)
        case .hypotenuse: return CGPoint(x: 0.7071, y: 0.7071)
        }
    }

    private func notchCornerDirectionIfApplicable(point: CGPoint) -> CGPoint? {
        let pieceSize = ShapePathBuilder.pieceSize(for: piece)
        // Use a more lenient tolerance to account for floating-point precision in polygon merging
        let tolerance: CGFloat = 2.0
        for cutout in piece.cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 {
            guard isEffectiveNotch(cutout, piece: piece, pieceSize: pieceSize) else { continue }
            let displayCutout = rotatedCutout(cutout)
            let corners = cutoutCornerPoints(for: displayCutout)
            
            // Check if point matches any of the cutout's corners (works for rectangles and leg notches)
            for corner in corners {
                if abs(point.x - corner.x) <= tolerance, abs(point.y - corner.y) <= tolerance {
                    let center = CGPoint(x: displayCutout.centerX, y: displayCutout.centerY)
                    return unitVector(from: center, to: point)
                }
            }
            
            // For hypotenuse notches on triangles, the actual polygon corners may not match
            // the cutout corners (they're clipped by the hypotenuse). Check if point is
            // within the cutout's bounding box with some tolerance.
            if piece.shape == .rightTriangle && isNotchOnHypotenuse(cutout: cutout, pieceSize: pieceSize) {
                let halfWidth = displayCutout.width / 2
                let halfHeight = displayCutout.height / 2
                let minX = displayCutout.centerX - halfWidth - tolerance
                let maxX = displayCutout.centerX + halfWidth + tolerance
                let minY = displayCutout.centerY - halfHeight - tolerance
                let maxY = displayCutout.centerY + halfHeight + tolerance
                
                if point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY {
                    // For hypotenuse notch corners, use diagonal directions like a rectangle
                    // Determine which corner of the notch this point is closest to
                    let isLeftHalf = point.x < displayCutout.centerX
                    let isTopHalf = point.y < displayCutout.centerY
                    
                    // Return diagonal direction based on corner position (like rectangle corners)
                    let dirX: CGFloat = isLeftHalf ? -1 : 1
                    let dirY: CGFloat = isTopHalf ? -1 : 1
                    let length = sqrt(2.0)
                    return CGPoint(x: dirX / length, y: dirY / length)
                }
            }
        }
        return nil
    }
    
    private func isNotchOnHypotenuse(cutout: Cutout, pieceSize: CGSize) -> Bool {
        let corners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: pieceSize, shape: .rightTriangle)
        let width = pieceSize.width
        let height = pieceSize.height
        let edgeEpsilon: CGFloat = 0.5
        
        // Check if cutout touches hypotenuse but not top or left edges
        let bounds = GeometryHelpers.bounds(for: corners)
        let touchesTop = bounds.minY <= edgeEpsilon
        let touchesLeft = bounds.minX <= edgeEpsilon
        
        // Check if any corner is near the hypotenuse or spans across it
        var minValue = CGFloat.greatestFiniteMagnitude
        var maxValue = -CGFloat.greatestFiniteMagnitude
        for corner in corners {
            let value = (corner.x / width) + (corner.y / height) - 1
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
        }
        
        // Touches hypotenuse if rectangle spans across hypotenuse line
        let touchesHypotenuse = minValue < -0.001 && maxValue > 0.001
        
        return touchesHypotenuse && !touchesTop && !touchesLeft
    }
    
    /// Check if a point lies on or very near the hypotenuse line of a right triangle
    private func isPointOnHypotenuse(point: CGPoint, pieceSize: CGSize) -> Bool {
        let width = pieceSize.width
        let height = pieceSize.height
        guard width > 0 && height > 0 else { return false }
        
        // Hypotenuse line equation: x/width + y/height = 1
        // A point is on the hypotenuse if this value is close to 1
        let value = (point.x / width) + (point.y / height)
        let tolerance: CGFloat = 0.05  // Allow some tolerance for floating point
        return abs(value - 1.0) < tolerance
    }
    
    /// Returns the outward normal direction for the hypotenuse (perpendicular, pointing away from triangle interior)
    private func hypotenuseOutwardNormal(pieceSize: CGSize) -> CGPoint {
        let width = pieceSize.width
        let height = pieceSize.height
        // Hypotenuse goes from (width, 0) to (0, height)
        // Direction vector: (-width, height)
        // Outward normal (90° clockwise): (height, width) - points toward bottom-right, away from triangle
        let nx = height
        let ny = width
        let length = sqrt(nx * nx + ny * ny)
        guard length > 0 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: nx / length, y: ny / length)
    }

    private func concaveCornerDirection(point: CGPoint, bounds: CGRect, shape: ShapeKind, isConcave: Bool) -> CGPoint? {
        guard isConcave else { return nil }
        let edges = edgesContaining(point: point, bounds: bounds, shape: shape, tolerance: 0.5)
        guard !edges.isEmpty else { return nil }
        var sum = CGPoint.zero
        for edge in edges {
            let normal = edgeNormal(for: edge, shape: shape)
            sum.x += normal.x
            sum.y += normal.y
        }
        return normalized(sum)
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

    private func cutoutCornerPoints(for cutout: Cutout, displaySize: CGSize) -> [CGPoint] {
        GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: displaySize, shape: piece.shape)
    }
    
    private func cutoutCornerPoints(for cutout: Cutout) -> [CGPoint] {
        let displaySize = ShapePathBuilder.pieceSize(for: piece)
        return GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: displaySize, shape: piece.shape)
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

    private struct SideMetric {
        let length: CGFloat
        let center: CGPoint
    }

    private func rectangleSideMetrics() -> [EdgePosition: SideMetric] {
        let points = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        guard points.count >= 2 else { return [:] }
        let eps: CGFloat = 0.001
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0

        var lengths: [EdgePosition: CGFloat] = [.top: 0, .bottom: 0, .left: 0, .right: 0]
        var weightedCenters: [EdgePosition: CGPoint] = [.top: .zero, .bottom: .zero, .left: .zero, .right: .zero]

        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            if abs(dy) < eps {
                if abs(a.y - minY) < eps {
                    let len = abs(dx)
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: minY)
                    lengths[.top, default: 0] += len
                    weightedCenters[.top, default: .zero].x += mid.x * len
                    weightedCenters[.top, default: .zero].y += mid.y * len
                } else if abs(a.y - maxY) < eps {
                    let len = abs(dx)
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: maxY)
                    lengths[.bottom, default: 0] += len
                    weightedCenters[.bottom, default: .zero].x += mid.x * len
                    weightedCenters[.bottom, default: .zero].y += mid.y * len
                }
            } else if abs(dx) < eps {
                if abs(a.x - minX) < eps {
                    let len = abs(dy)
                    let mid = CGPoint(x: minX, y: (a.y + b.y) / 2)
                    lengths[.left, default: 0] += len
                    weightedCenters[.left, default: .zero].x += mid.x * len
                    weightedCenters[.left, default: .zero].y += mid.y * len
                } else if abs(a.x - maxX) < eps {
                    let len = abs(dy)
                    let mid = CGPoint(x: maxX, y: (a.y + b.y) / 2)
                    lengths[.right, default: 0] += len
                    weightedCenters[.right, default: .zero].x += mid.x * len
                    weightedCenters[.right, default: .zero].y += mid.y * len
                }
            }
        }

        var metrics: [EdgePosition: SideMetric] = [:]
        for edge in [EdgePosition.top, .bottom, .left, .right] {
            let total = lengths[edge, default: 0]
            guard total > 0 else { continue }
            let weighted = weightedCenters[edge, default: .zero]
            let center = CGPoint(x: weighted.x / total, y: weighted.y / total)
            metrics[edge] = SideMetric(length: total, center: center)
        }
        return metrics
    }

    private func unitVector(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        return CGPoint(x: dx / length, y: dy / length)
    }

    private func cornerLabelDirection(points: [CGPoint], index: Int, center: CGPoint, clockwise: Bool) -> CGPoint {
        let count = points.count
        guard count >= 3 else { return unitVector(from: center, to: points[index]) }
        let prev = points[(index - 1 + count) % count]
        let curr = points[index]
        let next = points[(index + 1) % count]

        let cross = (curr.x - prev.x) * (next.y - curr.y) - (curr.y - prev.y) * (next.x - curr.x)
        let isConcave = clockwise ? cross > 0 : cross < 0
        if isConcave {
            return unitVector(from: center, to: curr)
        }
        return unitVector(from: curr, to: center)
    }

    private func polygonIsClockwise(_ points: [CGPoint]) -> Bool {
        guard points.count >= 3 else { return true }
        var area: CGFloat = 0
        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]
            area += (p1.x * p2.y) - (p2.x * p1.y)
        }
        return area > 0
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

    private func drawEdgeLabels(in context: inout GraphicsContext, metrics: DrawingMetrics, refreshToken: UUID) {
        _ = refreshToken
        let boundarySegments = ShapePathBuilder.boundarySegments(for: piece)
        let segmentCounts = Dictionary(grouping: boundarySegments, by: { $0.edge }).mapValues { $0.count }
        let angleSegments = ShapePathBuilder.angleSegments(for: piece)
        for assignment in piece.edgeAssignments {
            let code = assignment.treatmentAbbreviation
            guard !code.isEmpty else { continue }
            guard assignment.cutoutEdge == nil, assignment.angleEdgeId == nil else { continue }
            // Check for segment assignments BEFORE the right triangle edge filter
            // because segment edgeRaw is "segment:edge:index" which doesn't parse as EdgePosition
            if let segmentEdge = assignment.segmentEdge {
                if let segment = boundarySegments.first(where: { $0.edge == segmentEdge.edge && $0.index == segmentEdge.index }) {
                    let label = Text(code)
                        .font(.system(size: labelFontSize, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    let position = segmentEdgeLabelPosition(segment: segment, metrics: metrics)
                    context.draw(label, at: position, anchor: .center)
                }
                continue
            }
            if piece.shape == .rightTriangle {
                switch assignment.edge {
                case .top, .right, .bottom, .left:
                    continue
                default:
                    break
                }
            }
            // Skip whole-edge treatments when segments exist and there are segment assignments
            let edgeSegmentCount = segmentCounts[assignment.edge] ?? 0
            let hasSegmentAssignments = piece.edgeAssignments.contains { $0.segmentEdge?.edge == assignment.edge }
            if hasSegmentAssignments {
                // If there are segment-specific treatments for this edge, skip the whole-edge treatment
                continue
            }
            // Also skip whole-edge treatments for edges with multiple segments (unless curved)
            if edgeSegmentCount > 1 && (piece.curve(for: assignment.edge)?.radius ?? 0) <= 0 {
                continue
            }
            let label = Text(code)
                .font(.system(size: labelFontSize, weight: .bold))
                .foregroundStyle(Theme.accent)
            let position = edgeLabelPosition(for: assignment.edge, metrics: metrics, shape: piece.shape, curves: piece.curvedEdges)
            context.draw(label, at: position, anchor: .center)
        }

        let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        for assignment in piece.edgeAssignments {
            let code = assignment.treatmentAbbreviation
            guard !code.isEmpty else { continue }
            guard let angleId = assignment.angleEdgeId else { continue }
            guard let segment = angleSegments.first(where: { $0.id == angleId }) else { continue }
            let center = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
            let offsetDistance = 8 / max(metrics.scale, 0.01)
            let positionPoint = offsetOutsidePolygon(
                point: center,
                segmentStart: segment.start,
                segmentEnd: segment.end,
                polygon: polygon,
                distance: offsetDistance
            )
            let position = metrics.toCanvas(positionPoint)
            let label = Text(code)
                .font(.system(size: labelFontSize, weight: .bold))
                .foregroundStyle(Theme.accent)
            context.draw(label, at: position, anchor: .center)
        }

        for assignment in piece.edgeAssignments {
            let code = assignment.treatmentAbbreviation
            guard !code.isEmpty else { continue }
            guard let cutoutEdge = assignment.cutoutEdge else { continue }
            guard let cutout = piece.cutouts.first(where: { $0.id == cutoutEdge.id }) else { continue }
            guard cutout.centerX >= 0 && cutout.centerY >= 0 else { continue }
            let outerPolygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true, includeNotches: false)
            let displayCutout = rotatedCutout(cutout)
            let displaySize = ShapePathBuilder.displaySize(for: piece)
            if let edgeInfo = visibleCutoutEdgeInfo(displayCutout: displayCutout, edge: cutoutEdge.edge, displaySize: displaySize, polygon: outerPolygon),
               edgeInfo.length > 0.0001 {
                let label = Text(code)
                    .font(.system(size: labelFontSize, weight: .bold))
                    .foregroundStyle(Theme.accent)
                let position = cutoutEdgeLabelPosition(cutout: cutout, edge: cutoutEdge.edge, metrics: metrics)
                context.draw(label, at: position, anchor: .center)
            }
            continue
        }
    }

    private func drawCutoutNotes(in context: inout GraphicsContext, metrics: DrawingMetrics) {
        let visibleCutouts = piece.cutouts.filter { $0.centerX >= 0 && $0.centerY >= 0 && !isEffectiveNotch($0, piece: piece, pieceSize: ShapePathBuilder.pieceSize(for: piece)) }
        guard !visibleCutouts.isEmpty else { return }
        let origin = metrics.origin
        let height = metrics.pieceSize.height * metrics.scale
        let noteStart = CGPoint(
            x: metrics.size.width / 2,
            y: origin.y + height + (metrics.scale * noteYOffsetInches) + noteYOffsetPoints
        )

        let lines = cutoutNoteLines(from: visibleCutouts)
        for (index, line) in lines.enumerated() {
            let text = Text(line)
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            let y = noteStart.y + CGFloat(index) * 12
            context.draw(text, at: CGPoint(x: noteStart.x, y: y), anchor: .center)
        }
    }

    private func cutoutNoteLines(from cutouts: [Cutout]) -> [String] {
        var lines: [String] = []
        // Curves are stored with display edge positions
        let displayLeftCurveOffset = curveEdgeOffset(edge: .left)
        let displayTopCurveOffset = curveEdgeOffset(edge: .top)

        for cutout in cutouts {
            let displayCutout = rotatedCutout(cutout)
            let widthText = MeasurementParser.formatInches(cutout.width)
            let heightText = MeasurementParser.formatInches(cutout.height)
            let label: String
            if cutout.kind == .circle {
                label = abs(cutout.width - cutout.height) < 0.001 ? "Circle Cutout" : "Oval Cutout"
            } else {
                label = abs(cutout.width - cutout.height) < 0.001 ? "Square Cutout" : "Rectangular Cutout"
            }
            let sizeText = "\(widthText)\" Wide x \(heightText)\" Long"
            let fromLeftValue = max(displayCutout.centerX + displayLeftCurveOffset, 0)
            let fromTopValue = max(displayCutout.centerY + displayTopCurveOffset, 0)
            let fromLeft = MeasurementParser.formatInches(fromLeftValue)
            let fromTop = MeasurementParser.formatInches(fromTopValue)
            // Add "Apex" suffix when curve affects the measurement
            let leftSuffix = displayLeftCurveOffset != 0 ? " Apex" : ""
            let topSuffix = displayTopCurveOffset != 0 ? " Apex" : ""
            lines.append("\(label): \(sizeText) - \(fromLeft)\" From Left\(leftSuffix) to Center, \(fromTop)\" From Top\(topSuffix) to Center")
        }

        return wrapLines(lines, maxLength: 55)
    }

    private func curveEdgeOffset(edge: EdgePosition) -> Double {
        guard piece.shape == .rectangle else { return 0 }
        guard let curve = piece.curve(for: edge), curve.radius > 0 else { return 0 }
        return curve.isConcave ? -curve.radius : curve.radius
    }

    private func letter(for index: Int) -> String {
        let scalar = UnicodeScalar(65 + (index % 26))!
        return String(Character(scalar))
    }

    private func drawNotchDimensionLabels(in context: inout GraphicsContext, cutout: Cutout, metrics: DrawingMetrics) {
        let displayCutout = rotatedCutout(cutout)
        let outerPolygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true, includeNotches: false)
        let metricsInfo = notchInteriorEdgeMetrics(cutout: cutout, metrics: metrics, polygon: outerPolygon)

        let center = CGPoint(x: displayCutout.centerX, y: displayCutout.centerY)
        let halfWidth = displayCutout.width / 2
        let halfHeight = displayCutout.height / 2
        let basePaddingMultiplier: CGFloat = 0.75
        let apexWidthPaddingMultiplier: CGFloat = 1.05
        let apexLengthPaddingMultiplier: CGFloat = 1.0
        let widthPadding = (isReadOnly ? 9 : 12) * basePaddingMultiplier / max(metrics.scale, 0.01)
        let heightPadding = (isReadOnly ? 5 : 6) * basePaddingMultiplier / max(metrics.scale, 0.01)
        let labelPadding = max(widthPadding, heightPadding)
        let apexWidthLabelPadding = labelPadding * (apexWidthPaddingMultiplier / basePaddingMultiplier)
        let apexLengthLabelPadding = labelPadding * (apexLengthPaddingMultiplier / basePaddingMultiplier)
        let minX = center.x - halfWidth
        let maxX = center.x + halfWidth
        let minY = center.y - halfHeight
        let maxY = center.y + halfHeight
        let pieceWidth = metrics.pieceSize.width
        let pieceHeight = metrics.pieceSize.height
        let edgeEpsilon: CGFloat = 0.01

        // Determine which edges the notch touches in display coordinates
        let touchesDisplayLeft = minX <= edgeEpsilon
        let touchesDisplayRight = maxX >= pieceWidth - edgeEpsilon
        let touchesDisplayTop = minY <= edgeEpsilon
        let touchesDisplayBottom = maxY >= pieceHeight - edgeEpsilon

        // Check for curves on touched edges and add "to Apex" suffix
        // Curves are stored with display edge positions
        // For left/right edge notches, the horizontal distance (lengthValue) is affected by the curve
        // For top/bottom edge notches, the vertical distance (widthValue) is affected by the curve
        var widthFromApex = false
        var lengthFromApex = false
        var widthCurveDepth: CGFloat = 0
        var lengthCurveDepth: CGFloat = 0

        if piece.shape == .rightTriangle {
            if touchesDisplayLeft {
                // Leg B notch - check for curve on leg B
                if let curve = piece.curve(for: .legB), curve.radius > 0 {
                    lengthCurveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    lengthFromApex = true
                }
            }
            if touchesDisplayTop {
                // Leg A notch - check for curve on leg A
                if let curve = piece.curve(for: .legA), curve.radius > 0 {
                    widthCurveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    widthFromApex = true
                }
            }
        } else {
            if touchesDisplayLeft {
                // Left edge notch - check for curve on left edge
                if let curve = piece.curve(for: .left), curve.radius > 0 {
                    lengthCurveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    lengthFromApex = true
                }
            } else if touchesDisplayRight {
                // Right edge notch - check for curve on right edge
                if let curve = piece.curve(for: .right), curve.radius > 0 {
                    lengthCurveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    lengthFromApex = true
                }
            }

            if touchesDisplayTop {
                // Top edge notch - check for curve on top edge
                if let curve = piece.curve(for: .top), curve.radius > 0 {
                    widthCurveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    widthFromApex = true
                }
            } else if touchesDisplayBottom {
                // Bottom edge notch - check for curve on bottom edge
                if let curve = piece.curve(for: .bottom), curve.radius > 0 {
                    widthCurveDepth = curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
                    widthFromApex = true
                }
            }
        }

        let displaySize = ShapePathBuilder.displaySize(for: piece)

        func edgeInfo(for edge: EdgePosition, fallback: CGPoint) -> (edge: EdgePosition, mid: CGPoint, length: CGFloat) {
            if let info = visibleCutoutEdgeInfo(displayCutout: displayCutout, edge: edge, displaySize: displaySize, polygon: outerPolygon) {
                return (edge: edge, mid: info.mid, length: info.length)
            }
            return (edge: edge, mid: fallback, length: 0)
        }

        let leftInfo = edgeInfo(for: .left, fallback: CGPoint(x: center.x - halfWidth, y: center.y))
        let rightInfo = edgeInfo(for: .right, fallback: CGPoint(x: center.x + halfWidth, y: center.y))
        let topInfo = edgeInfo(for: .top, fallback: CGPoint(x: center.x, y: center.y - halfHeight))
        let bottomInfo = edgeInfo(for: .bottom, fallback: CGPoint(x: center.x, y: center.y + halfHeight))

        let leftDistance = distanceToPolygonBoundary(from: leftInfo.mid, polygon: outerPolygon)
        let rightDistance = distanceToPolygonBoundary(from: rightInfo.mid, polygon: outerPolygon)
        let topDistance = distanceToPolygonBoundary(from: topInfo.mid, polygon: outerPolygon)
        let bottomDistance = distanceToPolygonBoundary(from: bottomInfo.mid, polygon: outerPolygon)

        let boundaryTolerance: CGFloat = 0.01
        func chooseEdgeInfo(primary: (info: (edge: EdgePosition, mid: CGPoint, length: CGFloat), distance: CGFloat), secondary: (info: (edge: EdgePosition, mid: CGPoint, length: CGFloat), distance: CGFloat)) -> (edge: EdgePosition, mid: CGPoint, length: CGFloat) {
            let primaryInside = primary.distance > boundaryTolerance && primary.info.length > 0
            let secondaryInside = secondary.distance > boundaryTolerance && secondary.info.length > 0
            if primaryInside != secondaryInside {
                return primaryInside ? primary.info : secondary.info
            }
            if primary.info.length > 0 && secondary.info.length == 0 {
                return primary.info
            }
            if secondary.info.length > 0 && primary.info.length == 0 {
                return secondary.info
            }
            return primary.distance >= secondary.distance ? primary.info : secondary.info
        }

        let widthEdgeInfo = chooseEdgeInfo(
            primary: (info: rightInfo, distance: rightDistance),
            secondary: (info: leftInfo, distance: leftDistance)
        )
        let lengthEdgeInfo = chooseEdgeInfo(
            primary: (info: bottomInfo, distance: bottomDistance),
            secondary: (info: topInfo, distance: topDistance)
        )

        var widthEdgeMid = widthEdgeInfo.mid
        var lengthEdgeMid = lengthEdgeInfo.mid
        func curveDepth(for edge: EdgePosition) -> CGFloat? {
            guard let curve = piece.curve(for: edge), curve.radius > 0 else { return nil }
            return curve.isConcave ? -CGFloat(curve.radius) : CGFloat(curve.radius)
        }
        if piece.shape == .rightTriangle {
            if touchesDisplayTop, let depth = curveDepth(for: .legA) {
                widthCurveDepth = depth
                widthFromApex = true
            }
            if touchesDisplayLeft, let depth = curveDepth(for: .legB) {
                lengthCurveDepth = depth
                lengthFromApex = true
            }
            if isNotchOnHypotenuse(cutout: displayCutout, pieceSize: displaySize),
               let hypDepth = curveDepth(for: .hypotenuse) {
                let hypStart = CGPoint(x: displaySize.width, y: 0)
                let hypEnd = CGPoint(x: 0, y: displaySize.height)
                let distWidth = GeometryHelpers.pointLineDistance(point: widthEdgeMid, a: hypStart, b: hypEnd)
                let distLength = GeometryHelpers.pointLineDistance(point: lengthEdgeMid, a: hypStart, b: hypEnd)
                if distWidth <= distLength {
                    widthCurveDepth = hypDepth
                    widthFromApex = true
                } else {
                    lengthCurveDepth = hypDepth
                    lengthFromApex = true
                }
            }
        }

        // For hypotenuse-oriented cutouts, width/height are NOT swapped in displayCutout.
        // For custom angles and legs, width/height ARE swapped in displayCutout.
        let isHypotenuseOriented = piece.shape == .rightTriangle && cutout.orientation == .hypotenuse
        let expectedWidth = isHypotenuseOriented ? displayCutout.width : displayCutout.height
        let expectedLength = isHypotenuseOriented ? displayCutout.height : displayCutout.width
        let lengthEpsilon: CGFloat = 0.001
        var widthValue = expectedWidth
        var lengthValue = expectedLength

        // For rotated cutouts (hypotenuse or custom angle with non-zero rotation), use corner-based measurement
        if piece.shape == .rightTriangle, (cutout.orientation == .hypotenuse || (cutout.orientation == .custom && abs(cutout.customAngleDegrees) > 0.001)) {
            let corners = GeometryHelpers.cutoutCornerPoints(cutout: displayCutout, size: displaySize, shape: piece.shape)
            if corners.count == 4 {
                struct RotatedEdgeInfo {
                    let mid: CGPoint
                    let length: CGFloat
                    let distance: CGFloat
                    let fullLength: CGFloat
                }

                func visibleEdgeInfo(start: CGPoint, end: CGPoint, fullLength: CGFloat) -> RotatedEdgeInfo? {
                    let startInside = pointIsInsideOrOnPolygon(start, polygon: outerPolygon)
                    let endInside = pointIsInsideOrOnPolygon(end, polygon: outerPolygon)
                    if startInside && endInside {
                        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                        let length = distance(start, end)
                        let dist = distanceToPolygonBoundary(from: mid, polygon: outerPolygon)
                        return RotatedEdgeInfo(mid: mid, length: length, distance: dist, fullLength: fullLength)
                    }
                    if let clipped = clippedSegmentInfo(start: start, end: end, polygon: outerPolygon) {
                        let dist = distanceToPolygonBoundary(from: clipped.mid, polygon: outerPolygon)
                        return RotatedEdgeInfo(mid: clipped.mid, length: clipped.length, distance: dist, fullLength: fullLength)
                    }
                    return nil
                }

                // Corners are ordered: [0]=top-left, [1]=top-right, [2]=bottom-right, [3]=bottom-left (before rotation)
                // Edge pairs (before rotation):
                // - Top/bottom edges (0-1 and 2-3): span cutout.width (which is displayCutout.width due to coordinate swap)
                // - Left/right edges (1-2 and 3-0): span cutout.height (which is displayCutout.height due to coordinate swap)
                //
                // In display coordinates:
                // - Width dimension = displayCutout.height (the original cutout.width)
                // - Length dimension = displayCutout.width (the original cutout.height)
                //
                // So for correct mapping:
                // - "Width" label uses edges spanning displayCutout.height → left/right edges (1-2 and 3-0)
                // - "Length" label uses edges spanning displayCutout.width → top/bottom edges (0-1 and 2-3)
                let widthEdge0 = (start: corners[1], end: corners[2])   // right edge - spans displayCutout.height (width dimension)
                let widthEdge1 = (start: corners[3], end: corners[0])   // left edge - spans displayCutout.height (width dimension)
                let lengthEdge0 = (start: corners[0], end: corners[1])  // top edge - spans displayCutout.width (length dimension)
                let lengthEdge1 = (start: corners[2], end: corners[3])  // bottom edge - spans displayCutout.width (length dimension)

                let widthInfo0 = visibleEdgeInfo(start: widthEdge0.start, end: widthEdge0.end, fullLength: expectedWidth)
                let widthInfo1 = visibleEdgeInfo(start: widthEdge1.start, end: widthEdge1.end, fullLength: expectedWidth)
                let lengthInfo0 = visibleEdgeInfo(start: lengthEdge0.start, end: lengthEdge0.end, fullLength: expectedLength)
                let lengthInfo1 = visibleEdgeInfo(start: lengthEdge1.start, end: lengthEdge1.end, fullLength: expectedLength)

                // Pick the best visible edge from each pair based on distance (farthest from boundary)
                // For boundary-crossing notches, show visible edge length; otherwise show full dimension
                let bestWidth: RotatedEdgeInfo?
                switch (widthInfo0, widthInfo1) {
                case let (a?, b?):
                    bestWidth = a.distance >= b.distance ? a : b
                case let (a?, nil):
                    bestWidth = a
                case let (nil, b?):
                    bestWidth = b
                default:
                    bestWidth = nil
                }

                let bestLength: RotatedEdgeInfo?
                switch (lengthInfo0, lengthInfo1) {
                case let (a?, b?):
                    bestLength = a.distance >= b.distance ? a : b
                case let (a?, nil):
                    bestLength = a
                case let (nil, b?):
                    bestLength = b
                default:
                    bestLength = nil
                }

                if let best = bestWidth {
                    widthEdgeMid = best.mid
                    // Show visible edge length (clipped) if crossing boundary, otherwise full dimension
                    widthValue = best.length < best.fullLength - lengthEpsilon ? best.length : best.fullLength
                }

                if let best = bestLength {
                    lengthEdgeMid = best.mid
                    // Show visible edge length (clipped) if crossing boundary, otherwise full dimension
                    lengthValue = best.length < best.fullLength - lengthEpsilon ? best.length : best.fullLength
                }
            }
        } else {
            if widthEdgeInfo.length > 0, widthEdgeInfo.length < expectedWidth - lengthEpsilon {
                let widthStart = segmentStartPoint(for: widthEdgeInfo.edge, cutout: displayCutout, displaySize: displaySize)
                let widthEnd = segmentEndPoint(for: widthEdgeInfo.edge, cutout: displayCutout, displaySize: displaySize)
                let widthInside = pointIsInsideOrOnPolygon(widthStart, polygon: outerPolygon)
                    && pointIsInsideOrOnPolygon(widthEnd, polygon: outerPolygon)
                widthValue = widthInside ? expectedWidth : widthEdgeInfo.length
            } else if let metricsWidth = metricsInfo?.width, metricsWidth > 0, metricsWidth < expectedWidth - lengthEpsilon {
                widthValue = metricsWidth
            }
            if lengthEdgeInfo.length > 0, lengthEdgeInfo.length < expectedLength - lengthEpsilon {
                let lengthStart = segmentStartPoint(for: lengthEdgeInfo.edge, cutout: displayCutout, displaySize: displaySize)
                let lengthEnd = segmentEndPoint(for: lengthEdgeInfo.edge, cutout: displayCutout, displaySize: displaySize)
                let lengthInside = pointIsInsideOrOnPolygon(lengthStart, polygon: outerPolygon)
                    && pointIsInsideOrOnPolygon(lengthEnd, polygon: outerPolygon)
                lengthValue = lengthInside ? expectedLength : lengthEdgeInfo.length
            } else if let metricsLength = metricsInfo?.length, metricsLength > 0, metricsLength < expectedLength - lengthEpsilon {
                lengthValue = metricsLength
            }
        }
        if piece.shape == .rightTriangle,
           let hypCurve = piece.curve(for: .hypotenuse),
           hypCurve.radius > 0,
           isNotchOnHypotenuse(cutout: displayCutout, pieceSize: displaySize) {
            let hypStart = CGPoint(x: displaySize.width, y: 0)
            let hypEnd = CGPoint(x: 0, y: displaySize.height)
            let distWidth = GeometryHelpers.pointLineDistance(point: widthEdgeMid, a: hypStart, b: hypEnd)
            let distLength = GeometryHelpers.pointLineDistance(point: lengthEdgeMid, a: hypStart, b: hypEnd)
            let hypDepth = hypCurve.isConcave ? -CGFloat(hypCurve.radius) : CGFloat(hypCurve.radius)
            let tolerance = max(0.05, max(displaySize.width, displaySize.height) * 0.002)
            if distWidth <= distLength, distWidth <= tolerance {
                widthCurveDepth = hypDepth
                widthFromApex = true
            } else if distLength <= tolerance {
                lengthCurveDepth = hypDepth
                lengthFromApex = true
            }
        }
        widthValue += widthCurveDepth
        lengthValue += lengthCurveDepth

        let widthText = MeasurementParser.formatInches(Double(widthValue))
        let heightText = MeasurementParser.formatInches(Double(lengthValue))

        let cutoutCorners = cutoutCornerPoints(for: displayCutout, displaySize: displaySize)
        func apexLabelPoint(edgeMid: CGPoint, offset: CGFloat) -> (point: CGPoint, angle: CGFloat)? {
            guard cutoutCorners.count == 4 else { return nil }
            var closestMid = edgeMid
            var closestStart = cutoutCorners[0]
            var closestEnd = cutoutCorners[1]
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for index in 0..<cutoutCorners.count {
                let start = cutoutCorners[index]
                let end = cutoutCorners[(index + 1) % cutoutCorners.count]
                let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                let distance = GeometryHelpers.distance(mid, edgeMid)
                if distance < bestDistance {
                    bestDistance = distance
                    closestMid = mid
                    closestStart = start
                    closestEnd = end
                }
            }
            let edgeVector = CGPoint(x: closestEnd.x - closestStart.x, y: closestEnd.y - closestStart.y)
            let normal = normalized(CGPoint(x: -edgeVector.y, y: edgeVector.x))
            let centerVector = CGPoint(x: closestMid.x - center.x, y: closestMid.y - center.y)
            let dot = normal.x * centerVector.x + normal.y * centerVector.y
            let outward = dot < 0 ? CGPoint(x: -normal.x, y: -normal.y) : normal
            let point = CGPoint(x: closestMid.x + outward.x * offset, y: closestMid.y + outward.y * offset)
            let angle = atan2(edgeVector.y, edgeVector.x)
            return (point, angle)
        }

        let minClearance = 10 / max(metrics.scale, 0.01)
        let widthPoint = outsidePointWithClearance(
            edgeMid: widthEdgeMid,
            center: center,
            baseOffset: widthFromApex ? apexWidthLabelPadding : labelPadding,
            minClearance: minClearance,
            polygon: outerPolygon
        )
        let lengthPoint = outsidePointWithClearance(
            edgeMid: lengthEdgeMid,
            center: center,
            baseOffset: lengthFromApex ? apexLengthLabelPadding : labelPadding,
            minClearance: minClearance,
            polygon: outerPolygon
        )

        // Draw width label (for top/bottom edge notches - widthFromApex)
        // Position: to the right of the notch edge
        if widthFromApex {
            // Two-line label: "X\" from" on top, "Apex" below
            // Position along the notch interior edge
            let shouldAlignToEdge = abs(widthCurveDepth) > 0.0001
            let apexInfo = shouldAlignToEdge ? (apexLabelPoint(edgeMid: widthEdgeMid, offset: apexWidthLabelPadding)) : nil
            let apexPoint = apexInfo?.point ?? widthPoint
            let line1 = Text("\(widthText)\" to")
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            let line2 = Text("Apex")
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            let canvasPoint = metrics.toCanvas(apexPoint)
            let lineSpacing: CGFloat = 10
            if let apexInfo, abs(widthCurveDepth) > 0.0001 {
                var rotation = apexInfo.angle
                if rotation > .pi / 2 || rotation < -.pi / 2 {
                    rotation += .pi
                }
                context.drawLayer { layer in
                    layer.translateBy(x: canvasPoint.x, y: canvasPoint.y)
                    layer.rotate(by: .radians(rotation))
                    layer.draw(line1, at: CGPoint(x: 0, y: -lineSpacing / 2), anchor: .center)
                    layer.draw(line2, at: CGPoint(x: 0, y: lineSpacing / 2), anchor: .center)
                }
            } else {
                context.draw(line1, at: CGPoint(x: canvasPoint.x, y: canvasPoint.y - lineSpacing / 2), anchor: .center)
                context.draw(line2, at: CGPoint(x: canvasPoint.x, y: canvasPoint.y + lineSpacing / 2), anchor: .center)
            }
        } else {
            let widthLabel = Text("\(widthText)\"")
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            context.draw(widthLabel, at: metrics.toCanvas(widthPoint), anchor: .center)
        }

        // Draw length label (for left/right edge notches - lengthFromApex)
        // Position: below the notch
        if lengthFromApex {
            // Two-line label: "X\" from" on top, "Apex" below
            // Position along the notch interior edge
            let shouldAlignToEdge = abs(lengthCurveDepth) > 0.0001
            let apexInfo = shouldAlignToEdge ? apexLabelPoint(edgeMid: lengthEdgeMid, offset: apexLengthLabelPadding) : nil
            let apexPoint = apexInfo?.point ?? lengthPoint
            let line1 = Text("\(heightText)\" to")
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            let line2 = Text("Apex")
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            let canvasPoint = metrics.toCanvas(apexPoint)
            let lineSpacing: CGFloat = 10
            context.draw(line1, at: CGPoint(x: canvasPoint.x, y: canvasPoint.y - lineSpacing / 2), anchor: .center)
            context.draw(line2, at: CGPoint(x: canvasPoint.x, y: canvasPoint.y + lineSpacing / 2), anchor: .center)
        } else {
            let lengthLabel = Text("\(heightText)\"")
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            context.draw(lengthLabel, at: metrics.toCanvas(lengthPoint), anchor: .center)
        }
    }

    private func drawCutoutDimensionLabels(in context: inout GraphicsContext, cutout: Cutout, metrics: DrawingMetrics) {
        // Skip circles - they only have diameter, not width/length
        guard cutout.kind != .circle else { return }
        
        // Get display cutout (with swapped coordinates for display)
        let displayCutout = rotatedCutout(cutout)
        let center = CGPoint(x: displayCutout.centerX, y: displayCutout.centerY)

        let displaySize = ShapePathBuilder.displaySize(for: piece)
        let outerPolygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true, includeNotches: false)
        let padding: CGFloat = 4 * 0.75 / max(metrics.scale, 0.01)

        // In display coordinates with swapped width/height:
        // - Left/right edges (3→0 and 1→2) span displayCutout.height = user's WIDTH
        // - Top/bottom edges (0→1 and 2→3) span displayCutout.width = user's LENGTH
        let widthEdgeInfo = visibleCutoutEdgeInfo(
            displayCutout: displayCutout,
            edge: .left,
            displaySize: displaySize,
            polygon: outerPolygon
        ) ?? visibleCutoutEdgeInfo(
            displayCutout: displayCutout,
            edge: .right,
            displaySize: displaySize,
            polygon: outerPolygon
        )

        let lengthEdgeInfo = visibleCutoutEdgeInfo(
            displayCutout: displayCutout,
            edge: .top,
            displaySize: displaySize,
            polygon: outerPolygon
        ) ?? visibleCutoutEdgeInfo(
            displayCutout: displayCutout,
            edge: .bottom,
            displaySize: displaySize,
            polygon: outerPolygon
        )

        let widthEdgeMid = widthEdgeInfo?.mid ?? CGPoint(x: center.x, y: center.y - displayCutout.height / 2)
        let lengthEdgeMid = lengthEdgeInfo?.mid ?? CGPoint(x: center.x - displayCutout.width / 2, y: center.y)

        let minClearance = 10 / max(metrics.scale, 0.01)
        let widthPoint = outsidePointWithClearance(
            edgeMid: widthEdgeMid,
            center: center,
            baseOffset: padding,
            minClearance: minClearance,
            polygon: outerPolygon
        )
        let lengthPoint = outsidePointWithClearance(
            edgeMid: lengthEdgeMid,
            center: center,
            baseOffset: padding,
            minClearance: minClearance,
            polygon: outerPolygon
        )

        // For hypotenuse-oriented cutouts, width/height are NOT swapped in displayCutout.
        // For custom angles and legs, width/height ARE swapped in displayCutout.
        let isHypotenuseOriented = piece.shape == .rightTriangle && cutout.orientation == .hypotenuse
        let widthValue = CGFloat(isHypotenuseOriented ? displayCutout.width : displayCutout.height)
        let lengthValue = CGFloat(isHypotenuseOriented ? displayCutout.height : displayCutout.width)
        let widthText = MeasurementParser.formatInches(Double(widthValue))
        let lengthText = MeasurementParser.formatInches(Double(lengthValue))

        let widthLabel = Text("\(widthText)\"")
            .font(.system(size: labelFontSize, weight: .semibold))
            .foregroundStyle(Theme.accent)
        let lengthLabel = Text("\(lengthText)\"")
            .font(.system(size: labelFontSize, weight: .semibold))
            .foregroundStyle(Theme.accent)
        
        // Use center anchors for consistent positioning on rotated cutouts
        context.draw(widthLabel, at: metrics.toCanvas(widthPoint), anchor: .center)
        context.draw(lengthLabel, at: metrics.toCanvas(lengthPoint), anchor: .center)
    }

    private func notchInteriorEdgeMetrics(cutout: Cutout, metrics: DrawingMetrics, polygon: [CGPoint]) -> (width: CGFloat, length: CGFloat, widthCenterY: CGFloat, lengthCenterX: CGFloat)? {
        guard polygon.count >= 2 else { return nil }
        let displayCutout = rotatedCutout(cutout)
        let halfWidth = displayCutout.width / 2
        let halfHeight = displayCutout.height / 2
        let minX = displayCutout.centerX - halfWidth
        let maxX = displayCutout.centerX + halfWidth
        let minY = displayCutout.centerY - halfHeight
        let maxY = displayCutout.centerY + halfHeight
        let pieceWidth = metrics.pieceSize.width
        let pieceHeight = metrics.pieceSize.height
        let edgeEpsilon: CGFloat = 0.01

        let touchesLeft = minX <= edgeEpsilon
        let touchesRight = maxX >= pieceWidth - edgeEpsilon
        let touchesTop = minY <= edgeEpsilon
        let touchesBottom = maxY >= pieceHeight - edgeEpsilon

        let interiorX: CGFloat?
        if touchesLeft {
            interiorX = maxX
        } else if touchesRight {
            interiorX = minX
        } else {
            interiorX = nil
        }

        let interiorY: CGFloat?
        if touchesTop {
            interiorY = maxY
        } else if touchesBottom {
            interiorY = minY
        } else {
            interiorY = nil
        }

        var verticalLen: CGFloat = 0
        var verticalCenterY: CGFloat = displayCutout.centerY
        if let interiorX {
            verticalLen = segmentLengthOnLine(points: polygon, isVertical: true, value: interiorX, rangeMin: minY, rangeMax: maxY)
            if verticalLen > 0 {
                verticalCenterY = segmentCenterOnLine(points: polygon, isVertical: true, value: interiorX, rangeMin: minY, rangeMax: maxY)
            }
        } else if touchesTop || touchesBottom {
            // For notches that touch top/bottom but not left/right, calculate the visible vertical length
            // as the portion of the cutout that's inside the piece bounds
            let clippedMinY = max(minY, 0)
            let clippedMaxY = min(maxY, pieceHeight)
            verticalLen = clippedMaxY - clippedMinY
            verticalCenterY = (clippedMinY + clippedMaxY) / 2
        }
        var horizontalLen: CGFloat = 0
        var horizontalCenterX: CGFloat = displayCutout.centerX
        if let interiorY {
            horizontalLen = segmentLengthOnLine(points: polygon, isVertical: false, value: interiorY, rangeMin: minX, rangeMax: maxX)
            if horizontalLen > 0 {
                horizontalCenterX = segmentCenterOnLine(points: polygon, isVertical: false, value: interiorY, rangeMin: minX, rangeMax: maxX)
            }
        } else if touchesLeft || touchesRight {
            // For notches that touch left/right but not top/bottom, calculate the visible horizontal length
            // as the portion of the cutout that's inside the piece bounds
            let clippedMinX = max(minX, 0)
            let clippedMaxX = min(maxX, pieceWidth)
            horizontalLen = clippedMaxX - clippedMinX
            horizontalCenterX = (clippedMinX + clippedMaxX) / 2
        }

        guard verticalLen > 0 || horizontalLen > 0 else { return nil }
        return (width: verticalLen > 0 ? verticalLen : CGFloat(displayCutout.height),
                length: horizontalLen > 0 ? horizontalLen : CGFloat(displayCutout.width),
                widthCenterY: verticalCenterY,
                lengthCenterX: horizontalCenterX)
    }

    private func segmentLengthOnLine(points: [CGPoint], isVertical: Bool, value: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat) -> CGFloat {
        let eps: CGFloat = 0.01
        var total: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            if isVertical {
                guard abs(a.x - value) < eps, abs(b.x - value) < eps else { continue }
                let segMin = min(a.y, b.y)
                let segMax = max(a.y, b.y)
                let overlapMin = max(segMin, min(rangeMin, rangeMax))
                let overlapMax = min(segMax, max(rangeMin, rangeMax))
                if overlapMax > overlapMin {
                    total += overlapMax - overlapMin
                }
            } else {
                guard abs(a.y - value) < eps, abs(b.y - value) < eps else { continue }
                let segMin = min(a.x, b.x)
                let segMax = max(a.x, b.x)
                let overlapMin = max(segMin, min(rangeMin, rangeMax))
                let overlapMax = min(segMax, max(rangeMin, rangeMax))
                if overlapMax > overlapMin {
                    total += overlapMax - overlapMin
                }
            }
        }
        return total
    }

    private func segmentCenterOnLine(points: [CGPoint], isVertical: Bool, value: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat) -> CGFloat {
        let eps: CGFloat = 0.01
        var weightedSum: CGFloat = 0
        var total: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            if isVertical {
                guard abs(a.x - value) < eps, abs(b.x - value) < eps else { continue }
                let segMin = min(a.y, b.y)
                let segMax = max(a.y, b.y)
                let overlapMin = max(segMin, min(rangeMin, rangeMax))
                let overlapMax = min(segMax, max(rangeMin, rangeMax))
                if overlapMax > overlapMin {
                    let len = overlapMax - overlapMin
                    let mid = (overlapMin + overlapMax) / 2
                    weightedSum += mid * len
                    total += len
                }
            } else {
                guard abs(a.y - value) < eps, abs(b.y - value) < eps else { continue }
                let segMin = min(a.x, b.x)
                let segMax = max(a.x, b.x)
                let overlapMin = max(segMin, min(rangeMin, rangeMax))
                let overlapMax = min(segMax, max(rangeMin, rangeMax))
                if overlapMax > overlapMin {
                    let len = overlapMax - overlapMin
                    let mid = (overlapMin + overlapMax) / 2
                    weightedSum += mid * len
                    total += len
                }
            }
        }
        guard total > 0 else { return (rangeMin + rangeMax) / 2 }
        return weightedSum / total
    }



    private func wrapLines(_ lines: [String], maxLength: Int) -> [String] {
        var wrapped: [String] = []
        for line in lines {
            if line.count <= maxLength {
                wrapped.append(line)
                continue
            }
            let words = line.split(separator: " ")
            var current = ""
            for word in words {
                let next = current.isEmpty ? String(word) : "\(current) \(word)"
                if next.count > maxLength {
                    wrapped.append(current)
                    current = String(word)
                } else {
                    current = next
                }
            }
            if !current.isEmpty {
                wrapped.append(current)
            }
        }
        return wrapped
    }

    private func drawSegmentDimensionLabels(in context: inout GraphicsContext, metrics: DrawingMetrics) {
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        guard !segments.isEmpty else { return }

        let grouped = Dictionary(grouping: segments, by: { $0.edge })
        for (edge, edgeSegments) in grouped where edgeSegments.count > 1 {
            for segment in edgeSegments {
                let lengthValue: CGFloat
                // For horizontal edges (top, bottom, legA), use x-coordinate difference
                // For vertical edges (left, right, legB), use y-coordinate difference
                if edge == .top || edge == .bottom || edge == .legA {
                    lengthValue = abs(segment.end.x - segment.start.x)
                } else if edge == .left || edge == .right || edge == .legB {
                    lengthValue = abs(segment.end.y - segment.start.y)
                } else {
                    // For hypotenuse or other diagonal edges, calculate actual distance
                    let dx = segment.end.x - segment.start.x
                    let dy = segment.end.y - segment.start.y
                    lengthValue = sqrt(dx * dx + dy * dy)
                }
                let text = MeasurementParser.formatInches(Double(lengthValue))
                let label = Text("\(text)\"")
                    .font(.system(size: labelFontSize, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                let position = segmentLabelPosition(segment: segment, metrics: metrics)
                context.draw(label, at: position, anchor: .center)
            }
        }
    }

    private func edgeLabelPosition(for edge: EdgePosition, metrics: DrawingMetrics, shape: ShapeKind, curves: [CurvedEdge]) -> CGPoint {
        let width = metrics.pieceSize.width * metrics.scale
        let height = metrics.pieceSize.height * metrics.scale
        let origin = metrics.origin
        let curveMap = Dictionary(grouping: curves, by: { $0.edge }).compactMapValues { $0.first }
        let left = origin.x
        let right = origin.x + width
        let top = origin.y
        let bottom = origin.y + height
        if shape == .circle {
            let center = CGPoint(x: origin.x + width / 2, y: origin.y + height / 2)
            let radiusY = height / 2
            return CGPoint(x: center.x, y: center.y - radiusY - 8)
        }

        if shape == .rectangle, curveMap[edge]?.radius == nil {
            if let sideMetric = rectangleSideMetrics()[edge] {
                let centerX = origin.x + sideMetric.center.x * metrics.scale
                let centerY = origin.y + sideMetric.center.y * metrics.scale
                switch edge {
                case .top:
                    return CGPoint(x: centerX, y: top - 6)
                case .bottom:
                    return CGPoint(x: centerX, y: bottom + 6)
                case .left:
                    return CGPoint(x: left - 6, y: centerY)
                case .right:
                    return CGPoint(x: right + 6, y: centerY)
                default:
                    break
                }
            }
        }

        if shape == .quarterCircle && edge == .hypotenuse {
            let center = origin
            let radius = width
            let direction = normalized(CGPoint(x: 1, y: 1))
            return CGPoint(x: center.x + direction.x * (radius + 8), y: center.y + direction.y * (radius + 8))
        }

        if let curve = curveMap[edge], curve.radius > 0 {
            let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
            let baseBounds = shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : nil
            let geometry: (start: CGPoint, end: CGPoint, normal: CGPoint)?
            if edge == .hypotenuse, shape == .rightTriangle {
                geometry = fullHypotenuseGeometry()
            } else {
                geometry = edgeGeometryFromPolygon(edge: edge, polygon: polygon, shape: shape, baseBounds: baseBounds)
            }
            if let geometry {
                let mid = quadBezierPoint(t: 0.5, start: geometry.start, control: controlPointDisplay(for: geometry, curve: curve), end: geometry.end)
                let baseOffset = CGFloat(edge == .hypotenuse ? 12 : 8)
                var offsetDistance = baseOffset / max(metrics.scale, 0.01)
                if edge == .bottom {
                    offsetDistance += 4 / max(metrics.scale, 0.01)
                }
                let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))
                let outward = normalized(CGPoint(x: mid.x - center.x, y: mid.y - center.y))
                let adjusted = offsetRelativeToPolygon(
                    point: mid,
                    segmentStart: geometry.start,
                    segmentEnd: geometry.end,
                    polygon: polygon,
                    distance: offsetDistance,
                    preferInside: false,
                    preferredDirection: outward
                )
                return metrics.toCanvas(adjusted)
            }
        }

        if shape == .rightTriangle, edge == .legA || edge == .legB || edge == .hypotenuse {
            let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
            let baseBounds = CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece))
            let geometry: (start: CGPoint, end: CGPoint, normal: CGPoint)?
            if edge == .hypotenuse {
                geometry = fullHypotenuseGeometry()
            } else {
                geometry = edgeGeometryFromPolygon(edge: edge, polygon: polygon, shape: shape, baseBounds: baseBounds)
            }
            if let geometry {
                let mid = CGPoint(x: (geometry.start.x + geometry.end.x) / 2, y: (geometry.start.y + geometry.end.y) / 2)
                let offsetDistance = 10 / max(metrics.scale, 0.01)
                let outward = normalized(geometry.normal)
                let adjusted = offsetRelativeToPolygon(
                    point: mid,
                    segmentStart: geometry.start,
                    segmentEnd: geometry.end,
                    polygon: polygon,
                    distance: offsetDistance,
                    preferInside: false,
                    preferredDirection: outward
                )
                return metrics.toCanvas(adjusted)
            }
        }

        switch edge {
        case .top:
            return CGPoint(x: origin.x + width / 2, y: origin.y - 6)
        case .right:
            return CGPoint(x: origin.x + width + 6, y: origin.y + height / 2)
        case .bottom:
            return CGPoint(x: origin.x + width / 2, y: origin.y + height + 10)
        case .left:
            return CGPoint(x: origin.x - 6, y: origin.y + height / 2)
        case .hypotenuse:
            return CGPoint(x: origin.x + width * 0.6, y: origin.y + height * 0.6)
        case .legA:
            return CGPoint(x: origin.x + width / 2, y: origin.y - 6)
        case .legB:
            return CGPoint(x: origin.x - 6, y: origin.y + height / 2)
        }
    }

    private func segmentLabelPosition(segment: BoundarySegment, metrics: DrawingMetrics) -> CGPoint {
        let mid = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
        if let curve = piece.curve(for: segment.edge), curve.radius > 0 {
            let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
            let geometry = fullEdgeGeometryDisplay(edge: segment.edge)
            if let geometry {
                let t = edgeProgress(point: mid, geometry: geometry, edge: segment.edge)
                let clampedT = min(max(t, 0), 1)
                let control = controlPointDisplay(for: geometry, curve: curve)
                let curvePoint = quadBezierPoint(t: clampedT, start: geometry.start, control: control, end: geometry.end)
                let curveBaseOffset = CGFloat(segment.edge == .hypotenuse ? 12 : 8) / max(metrics.scale, 0.01)
                var curveOffsetDistance = curveBaseOffset
                if segment.edge == .top || segment.edge == .bottom {
                    curveOffsetDistance += 10 / max(metrics.scale, 0.01)
                }
                if segment.edge == .left || segment.edge == .right {
                    curveOffsetDistance += (20 / max(metrics.scale, 0.01))
                }
                let edgeNotationOffset = 6 / max(metrics.scale, 0.01)
                let minGap = (segment.edge == .hypotenuse ? 12 : 10) / max(metrics.scale, 0.01)
                curveOffsetDistance = max(curveOffsetDistance, edgeNotationOffset + minGap)
                let normal = normalized(geometry.normal)
                let direction = curve.isConcave ? CGPoint(x: -normal.x, y: -normal.y) : normal
                var adjusted = offsetRelativeToPolygon(
                    point: curvePoint,
                    segmentStart: geometry.start,
                    segmentEnd: geometry.end,
                    polygon: polygon,
                    distance: curveOffsetDistance,
                    preferInside: false,
                    preferredDirection: direction
                )
                if pointIsInsidePolygon(adjusted, polygon: polygon) {
                    adjusted = CGPoint(
                        x: curvePoint.x - direction.x * curveOffsetDistance,
                        y: curvePoint.y - direction.y * curveOffsetDistance
                    )
                }
                return metrics.toCanvas(adjusted)
            }
        }
        let baseOffset = 12 / max(metrics.scale, 0.01)
        let sideBoost = 18 / max(metrics.scale, 0.01)
        let extraPadding = 10 / max(metrics.scale, 0.01)
        let direction: CGPoint
        switch segment.edge {
        case .top:
            direction = CGPoint(x: 0, y: -1)
        case .bottom:
            direction = CGPoint(x: 0, y: 1)
        case .left:
            direction = CGPoint(x: -1, y: 0)
        case .right:
            direction = CGPoint(x: 1, y: 0)
        case .legA:
            direction = CGPoint(x: 0, y: -1)  // legA is horizontal at top, label goes up
        case .legB:
            direction = CGPoint(x: -1, y: 0)  // legB is vertical at left, label goes left
        case .hypotenuse:
            // Hypotenuse outward normal points toward bottom-right (outside the triangle)
            let norm = 1.0 / sqrt(2.0)
            direction = CGPoint(x: norm, y: norm)
        }
                let offsetDistance: CGFloat
                if segment.edge == .left || segment.edge == .right || segment.edge == .legB {
                    offsetDistance = baseOffset + sideBoost + extraPadding + (10 / max(metrics.scale, 0.01))
                } else if segment.edge == .top || segment.edge == .bottom || segment.edge == .legA {
                    offsetDistance = baseOffset + extraPadding
                } else if segment.edge == .hypotenuse {
                    // Hypotenuse needs extra padding to avoid interfering with edge notations
                    offsetDistance = baseOffset + sideBoost + extraPadding
                } else {
                    offsetDistance = baseOffset
                }
        let adjusted = CGPoint(x: mid.x + direction.x * offsetDistance, y: mid.y + direction.y * offsetDistance)
        return metrics.toCanvas(adjusted)
    }

    private func segmentEdgeLabelPosition(segment: BoundarySegment, metrics: DrawingMetrics) -> CGPoint {
        let mid = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
        if let curve = piece.curve(for: segment.edge), curve.radius > 0 {
            let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
            let geometry = fullEdgeGeometryDisplay(edge: segment.edge)
            if let geometry {
                let t = edgeProgress(point: mid, geometry: geometry, edge: segment.edge)
                let clampedT = min(max(t, 0), 1)
                let control = controlPointDisplay(for: geometry, curve: curve)
                let curvePoint = quadBezierPoint(t: clampedT, start: geometry.start, control: control, end: geometry.end)
                let offsetDistance = 6 / max(metrics.scale, 0.01)
                let normal = normalized(geometry.normal)
                let direction = curve.isConcave ? CGPoint(x: -normal.x, y: -normal.y) : normal
                let adjusted = offsetRelativeToPolygon(
                    point: curvePoint,
                    segmentStart: geometry.start,
                    segmentEnd: geometry.end,
                    polygon: polygon,
                    distance: offsetDistance,
                    preferInside: false,
                    preferredDirection: direction
                )
                return metrics.toCanvas(adjusted)
            }
        }
        // Use polygon-aware positioning for all shapes
        let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        let offsetDistance = 8 / max(metrics.scale, 0.01)
        let adjusted = offsetOutsidePolygon(
            point: mid,
            segmentStart: segment.start,
            segmentEnd: segment.end,
            polygon: polygon,
            distance: offsetDistance
        )
        return metrics.toCanvas(adjusted)
    }

    private func cutoutEdgeLabelPosition(cutout: Cutout, edge: EdgePosition, metrics: DrawingMetrics) -> CGPoint {
        let displayCutout = rotatedCutout(cutout)
        let displaySize = ShapePathBuilder.displaySize(for: piece)
        let corners = cutoutCornerPoints(for: displayCutout, displaySize: displaySize)
        let bounds = bounds(for: corners)
        let halfWidth = bounds.width / 2
        let halfHeight = bounds.height / 2
        let center = CGPoint(x: displayCutout.centerX, y: displayCutout.centerY)
        if cutout.kind == .circle {
            return metrics.toCanvas(center)
        }

        let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        let offsetDistance = 6 / max(metrics.scale, 0.01)
        let fallbackMid: CGPoint
        switch edge {
        case .top:
            fallbackMid = CGPoint(x: center.x, y: center.y - halfHeight)
        case .bottom:
            fallbackMid = CGPoint(x: center.x, y: center.y + halfHeight)
        case .left:
            fallbackMid = CGPoint(x: center.x - halfWidth, y: center.y)
        case .right:
            fallbackMid = CGPoint(x: center.x + halfWidth, y: center.y)
        default:
            fallbackMid = center
        }

        let edgeMid = visibleCutoutEdgeInfo(
            displayCutout: displayCutout,
            edge: edge,
            displaySize: displaySize,
            polygon: polygon
        )?.mid ?? fallbackMid

        let inwardNormal = normalized(CGPoint(x: center.x - edgeMid.x, y: center.y - edgeMid.y))
        let adjusted = CGPoint(
            x: edgeMid.x + inwardNormal.x * offsetDistance,
            y: edgeMid.y + inwardNormal.y * offsetDistance
        )
        return metrics.toCanvas(adjusted)
    }
    
    /// Find the midpoint of a cutout edge that may be clipped by the triangle hypotenuse
    private func findClippedCutoutEdgeMidpoint(cutout: Cutout, edge: EdgePosition, corners: [CGPoint], polygon: [CGPoint], displaySize: CGSize) -> CGPoint? {
        guard corners.count == 4, polygon.count >= 3 else { return nil }
        
        // Get the cutout edge endpoints
        let edgeCorners = cutoutEdgeCorners(corners: corners, edge: edge)
        let edgeStart = edgeCorners.start
        let edgeEnd = edgeCorners.end
        
        // Hypotenuse line: from (displaySize.width, 0) to (0, displaySize.height)
        // Line equation: x/width + y/height = 1, or: x*height + y*width = width*height
        let width = displaySize.width
        let height = displaySize.height
        
        // Check if either endpoint is outside the triangle (beyond hypotenuse)
        let startValue = edgeStart.x / width + edgeStart.y / height
        let endValue = edgeEnd.x / width + edgeEnd.y / height
        let eps: CGFloat = 0.01
        
        let startOutside = startValue > 1 + eps
        let endOutside = endValue > 1 + eps
        
        // If neither endpoint is outside, no clipping needed
        if !startOutside && !endOutside {
            return nil
        }
        
        // If both endpoints are outside, edge is not visible
        if startOutside && endOutside {
            return nil
        }
        
        // One endpoint is inside, one is outside - calculate intersection with hypotenuse
        // Parametric line: P = edgeStart + t*(edgeEnd - edgeStart)
        // Hypotenuse: x/width + y/height = 1
        // Substitute: (edgeStart.x + t*dx)/width + (edgeStart.y + t*dy)/height = 1
        let dx = edgeEnd.x - edgeStart.x
        let dy = edgeEnd.y - edgeStart.y
        
        // (edgeStart.x/width + edgeStart.y/height) + t*(dx/width + dy/height) = 1
        let a = edgeStart.x / width + edgeStart.y / height
        let b = dx / width + dy / height
        
        guard abs(b) > 0.0001 else { return nil }
        
        let t = (1 - a) / b
        let intersectPoint = CGPoint(
            x: edgeStart.x + t * dx,
            y: edgeStart.y + t * dy
        )
        
        // Calculate the midpoint of the visible portion
        let visibleStart = startOutside ? intersectPoint : edgeStart
        let visibleEnd = endOutside ? intersectPoint : edgeEnd
        
        return CGPoint(
            x: (visibleStart.x + visibleEnd.x) / 2,
            y: (visibleStart.y + visibleEnd.y) / 2
        )
    }

    private func visibleCutoutEdgeInfo(displayCutout: Cutout, edge: EdgePosition, displaySize: CGSize, polygon: [CGPoint]) -> (mid: CGPoint, length: CGFloat)? {
        let start = segmentStartPoint(for: edge, cutout: displayCutout, displaySize: displaySize)
        let end = segmentEndPoint(for: edge, cutout: displayCutout, displaySize: displaySize)
        return clippedSegmentInfo(start: start, end: end, polygon: polygon)
    }

    private func clippedSegmentInfo(start: CGPoint, end: CGPoint, polygon: [CGPoint]) -> (mid: CGPoint, length: CGFloat)? {
        guard polygon.count >= 3 else { return nil }
        let epsilon: CGFloat = 0.0001
        var hits: [(t: CGFloat, point: CGPoint)] = []
        var bestColinear: (mid: CGPoint, length: CGFloat)?

        if pointIsInsideOrOnPolygon(start, polygon: polygon) {
            hits.append((t: 0, point: start))
        }
        if pointIsInsideOrOnPolygon(end, polygon: polygon) {
            hits.append((t: 1, point: end))
        }

        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            if let t = segmentIntersectionParameter(p: start, p2: end, q: a, q2: b) {
                let point = pointAlongSegment(start: start, end: end, t: t)
                hits.append((t: t, point: point))
            }

            // Handle colinear overlap with polygon edges.
            if segmentIsColinear(start: start, end: end, a: a, b: b, tolerance: 0.0005) {
                if let overlap = colinearOverlap(start: start, end: end, a: a, b: b) {
                    if overlap.length > (bestColinear?.length ?? 0) {
                        bestColinear = overlap
                    }
                }
            }
        }

        guard !hits.isEmpty else { return nil }
        hits.sort { $0.t < $1.t }

        var unique: [(t: CGFloat, point: CGPoint)] = []
        for hit in hits {
            if let last = unique.last, abs(hit.t - last.t) <= epsilon {
                continue
            }
            unique.append(hit)
        }

        var bestMid: CGPoint?
        var bestLength: CGFloat = 0

        if unique.count == 1 {
            if let bestColinear, bestColinear.length > epsilon {
                return bestColinear
            }
            return nil
        }

        for index in 0..<(unique.count - 1) {
            let t0 = unique[index].t
            let t1 = unique[index + 1].t
            if t1 - t0 <= epsilon { continue }
            let midT = (t0 + t1) / 2
            let mid = pointAlongSegment(start: start, end: end, t: midT)
            if pointIsInsideOrOnPolygon(mid, polygon: polygon) {
                let p0 = pointAlongSegment(start: start, end: end, t: t0)
                let p1 = pointAlongSegment(start: start, end: end, t: t1)
                let length = distance(p0, p1)
                if length > bestLength {
                    bestLength = length
                    bestMid = mid
                }
            }
        }

        if let bestMid, bestLength > 0.000001 {
            return (mid: bestMid, length: bestLength)
        }

        if let bestColinear, bestColinear.length > epsilon {
            return bestColinear
        }

        return nil
    }

    private func pointIsInsideOrOnPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        if pointIsInsidePolygon(point, polygon: polygon) { return true }
        let tolerance: CGFloat = 0.0005
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            if GeometryHelpers.pointSegmentDistance(point: point, a: a, b: b) <= tolerance {
                return true
            }
        }
        return false
    }

    private func distanceToPolygonBoundary(from point: CGPoint, polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 2 else { return 0 }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let dist = GeometryHelpers.pointSegmentDistance(point: point, a: a, b: b)
            best = min(best, dist)
        }
        return best == .greatestFiniteMagnitude ? 0 : best
    }

    private func outsidePointWithClearance(edgeMid: CGPoint, center: CGPoint, baseOffset: CGFloat, minClearance: CGFloat, polygon: [CGPoint]) -> CGPoint {
        let normal = normalized(CGPoint(x: edgeMid.x - center.x, y: edgeMid.y - center.y))
        let point = CGPoint(
            x: edgeMid.x + normal.x * baseOffset,
            y: edgeMid.y + normal.y * baseOffset
        )
        return point
    }

    private func pointAlongSegment(start: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }

    private func segmentIsColinear(start: CGPoint, end: CGPoint, a: CGPoint, b: CGPoint, tolerance: CGFloat) -> Bool {
        let lineDistStart = GeometryHelpers.pointLineDistance(point: start, a: a, b: b)
        let lineDistEnd = GeometryHelpers.pointLineDistance(point: end, a: a, b: b)
        return lineDistStart <= tolerance && lineDistEnd <= tolerance
    }

    private func colinearOverlap(start: CGPoint, end: CGPoint, a: CGPoint, b: CGPoint) -> (mid: CGPoint, length: CGFloat)? {
        if abs(start.x - end.x) >= abs(start.y - end.y) {
            let segMin = min(start.x, end.x)
            let segMax = max(start.x, end.x)
            let edgeMin = min(a.x, b.x)
            let edgeMax = max(a.x, b.x)
            let overlapMin = max(segMin, edgeMin)
            let overlapMax = min(segMax, edgeMax)
            guard overlapMax > overlapMin else { return nil }
            let midX = (overlapMin + overlapMax) / 2
            let y = (start.y + end.y) / 2
            return (mid: CGPoint(x: midX, y: y), length: overlapMax - overlapMin)
        }
        let segMin = min(start.y, end.y)
        let segMax = max(start.y, end.y)
        let edgeMin = min(a.y, b.y)
        let edgeMax = max(a.y, b.y)
        let overlapMin = max(segMin, edgeMin)
        let overlapMax = min(segMax, edgeMax)
        guard overlapMax > overlapMin else { return nil }
        let midY = (overlapMin + overlapMax) / 2
        let x = (start.x + end.x) / 2
        return (mid: CGPoint(x: x, y: midY), length: overlapMax - overlapMin)
    }

    private func segmentIntersectionParameter(p: CGPoint, p2: CGPoint, q: CGPoint, q2: CGPoint) -> CGFloat? {
        let r = CGPoint(x: p2.x - p.x, y: p2.y - p.y)
        let s = CGPoint(x: q2.x - q.x, y: q2.y - q.y)
        let rxs = r.x * s.y - r.y * s.x
        let epsilon: CGFloat = 0.0001
        if abs(rxs) < epsilon { return nil }
        let qmp = CGPoint(x: q.x - p.x, y: q.y - p.y)
        let t = (qmp.x * s.y - qmp.y * s.x) / rxs
        let u = (qmp.x * r.y - qmp.y * r.x) / rxs
        if t >= -epsilon && t <= 1 + epsilon && u >= -epsilon && u <= 1 + epsilon {
            return min(max(t, 0), 1)
        }
        return nil
    }

    private func fullHypotenuseGeometry() -> (start: CGPoint, end: CGPoint, normal: CGPoint)? {
        guard piece.shape == .rightTriangle else { return nil }
        let size = ShapePathBuilder.displaySize(for: piece)
        let start = CGPoint(x: size.width, y: 0)
        let end = CGPoint(x: 0, y: size.height)
        let direction = normalized(CGPoint(x: end.x - start.x, y: end.y - start.y))
        let normal = CGPoint(x: direction.y, y: -direction.x)
        return (start: start, end: end, normal: normal)
    }

    private func edgeGeometryFromPolygon(edge: EdgePosition, polygon: [CGPoint], shape: ShapeKind, baseBounds: CGRect?) -> (start: CGPoint, end: CGPoint, normal: CGPoint)? {
        guard polygon.count >= 2 else { return nil }
        let bounds = bounds(for: polygon)
        let hypotenuseBounds = baseBounds ?? bounds
        let eps: CGFloat = 0.01

        var best: (start: CGPoint, end: CGPoint, length: CGFloat)?
        var bestDiagonal: (start: CGPoint, end: CGPoint, length: CGFloat)?
        var bestLegA: (start: CGPoint, end: CGPoint, length: CGFloat)?
        var bestLegB: (start: CGPoint, end: CGPoint, length: CGFloat)?
        var bestLegADistance: CGFloat?
        var bestLegBDistance: CGFloat?
        var bestDiagonalDistance: CGFloat?
        let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))

        for i in 0..<polygon.count {
            let start = polygon[i]
            let end = polygon[(i + 1) % polygon.count]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = distance(start, end)
            if length <= 0.0001 { continue }

            let isHorizontal = abs(dy) < eps
            let isVertical = abs(dx) < eps

            if shape == .rightTriangle {
                if isHorizontal {
                    let distanceToLeg = abs(((start.y + end.y) / 2) - bounds.minY)
                    if bestLegA == nil || distanceToLeg < (bestLegADistance ?? .greatestFiniteMagnitude) ||
                        (abs(distanceToLeg - (bestLegADistance ?? .greatestFiniteMagnitude)) < 0.001 && length > (bestLegA?.length ?? 0)) {
                        bestLegA = (start, end, length)
                        bestLegADistance = distanceToLeg
                    }
                } else if isVertical {
                    let distanceToLeg = abs(((start.x + end.x) / 2) - bounds.minX)
                    if bestLegB == nil || distanceToLeg < (bestLegBDistance ?? .greatestFiniteMagnitude) ||
                        (abs(distanceToLeg - (bestLegBDistance ?? .greatestFiniteMagnitude)) < 0.001 && length > (bestLegB?.length ?? 0)) {
                        bestLegB = (start, end, length)
                        bestLegBDistance = distanceToLeg
                    }
                } else {
                    let distanceToHypotenuse = (pointLineDistance(point: start, a: CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY), b: CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY))
                        + pointLineDistance(point: end, a: CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY), b: CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY))) / 2
                    if bestDiagonal == nil || distanceToHypotenuse < (bestDiagonalDistance ?? .greatestFiniteMagnitude) {
                        bestDiagonal = (start, end, length)
                        bestDiagonalDistance = distanceToHypotenuse
                    }
                }
                continue
            }

            switch edge {
            case .top:
                if isHorizontal, abs(((start.y + end.y) / 2) - bounds.minY) < eps,
                   best == nil || length > (best?.length ?? 0) {
                    best = (start, end, length)
                }
            case .bottom:
                if isHorizontal, abs(((start.y + end.y) / 2) - bounds.maxY) < eps,
                   best == nil || length > (best?.length ?? 0) {
                    best = (start, end, length)
                }
            case .left:
                if isVertical, abs(((start.x + end.x) / 2) - bounds.minX) < eps,
                   best == nil || length > (best?.length ?? 0) {
                    best = (start, end, length)
                }
            case .right:
                if isVertical, abs(((start.x + end.x) / 2) - bounds.maxX) < eps,
                   best == nil || length > (best?.length ?? 0) {
                    best = (start, end, length)
                }
            default:
                break
            }
        }

        if shape == .rightTriangle {
            func outwardNormal(for segment: (start: CGPoint, end: CGPoint)) -> CGPoint {
                let dx = segment.end.x - segment.start.x
                let dy = segment.end.y - segment.start.y
                var normal = normalized(CGPoint(x: dy, y: -dx))
                let mid = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
                let toMid = CGPoint(x: mid.x - center.x, y: mid.y - center.y)
                if normal.x * toMid.x + normal.y * toMid.y < 0 {
                    normal = CGPoint(x: -normal.x, y: -normal.y)
                }
                return normal
            }
            switch edge {
            case .legA:
                if let segment = bestLegA {
                    return (segment.start, segment.end, outwardNormal(for: (segment.start, segment.end)))
                }
                return nil
            case .legB:
                if let segment = bestLegB {
                    return (segment.start, segment.end, outwardNormal(for: (segment.start, segment.end)))
                }
                return nil
            case .hypotenuse:
                if let diag = bestDiagonal {
                    let normal = outwardNormal(for: (diag.start, diag.end))
                    return (diag.start, diag.end, normal)
                }
                return nil
            default:
                break
            }
        }

        guard let segment = best else { return nil }
        let normal: CGPoint
        switch edge {
        case .top:
            normal = CGPoint(x: 0, y: -1)
        case .bottom:
            normal = CGPoint(x: 0, y: 1)
        case .left:
            normal = CGPoint(x: -1, y: 0)
        case .right:
            normal = CGPoint(x: 1, y: 0)
        case .legA:
            normal = CGPoint(x: 0, y: -1)
        case .legB:
            normal = CGPoint(x: -1, y: 0)
        case .hypotenuse:
            normal = normalized(CGPoint(x: segment.end.y - segment.start.y, y: -(segment.end.x - segment.start.x)))
        }
        return (segment.start, segment.end, normal)
    }

    private func fullEdgeGeometryDisplay(edge: EdgePosition) -> (start: CGPoint, end: CGPoint, normal: CGPoint)? {
        let size = ShapePathBuilder.displaySize(for: piece)
        switch piece.shape {
        case .rectangle:
            switch edge {
            case .top:
                return (CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: -1))
            case .right:
                return (CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 1, y: 0))
            case .bottom:
                return (CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 1))
            case .left:
                return (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
            default:
                return nil
            }
        case .rightTriangle:
            switch edge {
            case .legA:
                return (CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: -1))
            case .legB:
                return (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
            case .hypotenuse:
                return fullHypotenuseGeometry()
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func edgeProgress(point: CGPoint, geometry: (start: CGPoint, end: CGPoint, normal: CGPoint), edge: EdgePosition) -> CGFloat {
        switch edge {
        case .top, .bottom, .legA:
            let denom = geometry.end.x - geometry.start.x
            if abs(denom) < 0.0001 { return 0.5 }
            return (point.x - geometry.start.x) / denom
        case .left, .right, .legB:
            let denom = geometry.end.y - geometry.start.y
            if abs(denom) < 0.0001 { return 0.5 }
            return (point.y - geometry.start.y) / denom
        case .hypotenuse:
            let dx = geometry.end.x - geometry.start.x
            let dy = geometry.end.y - geometry.start.y
            let denom = dx * dx + dy * dy
            if denom < 0.0001 { return 0.5 }
            return ((point.x - geometry.start.x) * dx + (point.y - geometry.start.y) * dy) / denom
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func controlPointDisplay(for geometry: (start: CGPoint, end: CGPoint, normal: CGPoint), curve: CurvedEdge) -> CGPoint {
        let mid = CGPoint(x: (geometry.start.x + geometry.end.x) / 2, y: (geometry.start.y + geometry.end.y) / 2)
        let direction: CGFloat = curve.isConcave ? -1 : 1
        let normal = normalized(geometry.normal)
        return CGPoint(x: mid.x + normal.x * curve.radius * 2 * direction, y: mid.y + normal.y * curve.radius * 2 * direction)
    }

    private func segmentIsOnHypotenuse(start: CGPoint, end: CGPoint, bounds: CGRect) -> Bool {
        let a = CGPoint(x: bounds.maxX, y: bounds.minY)
        let b = CGPoint(x: bounds.minX, y: bounds.maxY)
        let tolerance = hypotenuseTolerance(for: bounds)
        return pointLineDistance(point: start, a: a, b: b) <= tolerance &&
            pointLineDistance(point: end, a: a, b: b) <= tolerance
    }

    private func hypotenuseTolerance(for bounds: CGRect) -> CGFloat {
        let scale = max(max(bounds.width, bounds.height), 1)
        return max(0.05, scale * 0.002)
    }

    private func pointLineDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let denom = max(sqrt(dx * dx + dy * dy), 0.0001)
        return abs(dy * point.x - dx * point.y + b.x * a.y - b.y * a.x) / denom
    }

    private func segmentStartPoint(for edge: EdgePosition, cutout: Cutout, displaySize: CGSize) -> CGPoint {
        let corners = cutoutCornerPoints(for: cutout, displaySize: displaySize)
        guard corners.count == 4 else { return CGPoint(x: cutout.centerX, y: cutout.centerY) }
        switch edge {
        case .top:
            return corners[0]
        case .right:
            return corners[1]
        case .bottom:
            return corners[2]
        case .left:
            return corners[3]
        default:
            return CGPoint(x: cutout.centerX, y: cutout.centerY)
        }
    }

    private func segmentEndPoint(for edge: EdgePosition, cutout: Cutout, displaySize: CGSize) -> CGPoint {
        let corners = cutoutCornerPoints(for: cutout, displaySize: displaySize)
        guard corners.count == 4 else { return CGPoint(x: cutout.centerX, y: cutout.centerY) }
        switch edge {
        case .top:
            return corners[1]
        case .right:
            return corners[2]
        case .bottom:
            return corners[3]
        case .left:
            return corners[0]
        default:
            return CGPoint(x: cutout.centerX, y: cutout.centerY)
        }
    }

    private func offsetOutsidePolygon(point: CGPoint, segmentStart: CGPoint, segmentEnd: CGPoint, polygon: [CGPoint], distance: CGFloat) -> CGPoint {
        offsetRelativeToPolygon(
            point: point,
            segmentStart: segmentStart,
            segmentEnd: segmentEnd,
            polygon: polygon,
            distance: distance,
            preferInside: false,
            preferredDirection: nil
        )
    }

    private func offsetRelativeToPolygon(point: CGPoint, segmentStart: CGPoint, segmentEnd: CGPoint, polygon: [CGPoint], distance: CGFloat, preferInside: Bool, preferredDirection: CGPoint?) -> CGPoint {
        let dx = segmentEnd.x - segmentStart.x
        let dy = segmentEnd.y - segmentStart.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let candidateA = CGPoint(x: point.x + normal.x * distance, y: point.y + normal.y * distance)
        let candidateB = CGPoint(x: point.x - normal.x * distance, y: point.y - normal.y * distance)
        let insideA = pointIsInsidePolygon(candidateA, polygon: polygon)
        let insideB = pointIsInsidePolygon(candidateB, polygon: polygon)
        if preferInside {
            if let preferredDirection {
                let dir = normalized(preferredDirection)
                let dotA = (candidateA.x - point.x) * dir.x + (candidateA.y - point.y) * dir.y
                let dotB = (candidateB.x - point.x) * dir.x + (candidateB.y - point.y) * dir.y
                let preferred = dotA >= dotB ? candidateA : candidateB
                let alternate = dotA >= dotB ? candidateB : candidateA
                let preferredInside = dotA >= dotB ? insideA : insideB
                let alternateInside = dotA >= dotB ? insideB : insideA
                if preferredInside { return preferred }
                if alternateInside { return alternate }
                return preferred
            }
            if insideA && insideB {
                let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))
                let distA = hypot(candidateA.x - center.x, candidateA.y - center.y)
                let distB = hypot(candidateB.x - center.x, candidateB.y - center.y)
                return distA >= distB ? candidateA : candidateB
            }
            if insideA { return candidateA }
            if insideB { return candidateB }
            let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))
            let distA = hypot(candidateA.x - center.x, candidateA.y - center.y)
            let distB = hypot(candidateB.x - center.x, candidateB.y - center.y)
            return distA <= distB ? candidateA : candidateB
        }
        if let preferredDirection {
            let dir = normalized(preferredDirection)
            let dotA = (candidateA.x - point.x) * dir.x + (candidateA.y - point.y) * dir.y
            let dotB = (candidateB.x - point.x) * dir.x + (candidateB.y - point.y) * dir.y
            let preferred = dotA >= dotB ? candidateA : candidateB
            let alternate = dotA >= dotB ? candidateB : candidateA
            let preferredOutside = dotA >= dotB ? !insideA : !insideB
            let alternateOutside = dotA >= dotB ? !insideB : !insideA
            if preferredOutside { return preferred }
            if alternateOutside { return alternate }
            return preferred
        }
        return insideA ? candidateB : candidateA
    }

    private func pointIsInsidePolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            let intersect = ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y + 0.000001) + pi.x)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    private func edgeGeometry(for edge: EdgePosition, width: CGFloat, height: CGFloat, origin: CGPoint) -> (start: CGPoint, end: CGPoint, normal: CGPoint)? {
        switch edge {
        case .top:
            return (CGPoint(x: origin.x, y: origin.y), CGPoint(x: origin.x + width, y: origin.y), CGPoint(x: 0, y: -1))
        case .right:
            return (CGPoint(x: origin.x + width, y: origin.y), CGPoint(x: origin.x + width, y: origin.y + height), CGPoint(x: 1, y: 0))
        case .bottom:
            return (CGPoint(x: origin.x + width, y: origin.y + height), CGPoint(x: origin.x, y: origin.y + height), CGPoint(x: 0, y: 1))
        case .left:
            return (CGPoint(x: origin.x, y: origin.y + height), CGPoint(x: origin.x, y: origin.y), CGPoint(x: -1, y: 0))
        case .legA:
            return (CGPoint(x: origin.x, y: origin.y), CGPoint(x: origin.x + width, y: origin.y), CGPoint(x: 0, y: -1))
        case .legB:
            return (CGPoint(x: origin.x, y: origin.y + height), CGPoint(x: origin.x, y: origin.y), CGPoint(x: -1, y: 0))
        case .hypotenuse:
            return (CGPoint(x: origin.x + width, y: origin.y), CGPoint(x: origin.x, y: origin.y + height), CGPoint(x: 0.7, y: 0.7))
        }
    }

    private func controlPoint(for geometry: (start: CGPoint, end: CGPoint, normal: CGPoint), curve: CurvedEdge, scale: CGFloat) -> CGPoint {
        let mid = CGPoint(x: (geometry.start.x + geometry.end.x) / 2, y: (geometry.start.y + geometry.end.y) / 2)
        let direction: CGFloat = curve.isConcave ? -1 : 1
        let normal = normalized(geometry.normal)
        return CGPoint(
            x: mid.x + normal.x * curve.radius * scale * direction,
            y: mid.y + normal.y * curve.radius * scale * direction
        )
    }

    private func quadBezierPoint(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let oneMinus = 1 - t
        let x = oneMinus * oneMinus * start.x + 2 * oneMinus * t * control.x + t * t * end.x
        let y = oneMinus * oneMinus * start.y + 2 * oneMinus * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    private func quadBezierTangent(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let oneMinus = 1 - t
        let dx = 2 * oneMinus * (control.x - start.x) + 2 * t * (end.x - control.x)
        let dy = 2 * oneMinus * (control.y - start.y) + 2 * t * (end.y - control.y)
        return CGPoint(x: dx, y: dy)
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        let length = max(sqrt(point.x * point.x + point.y * point.y), 0.0001)
        return CGPoint(x: point.x / length, y: point.y / length)
    }

    private func cutoutCornerRange(for cutout: Cutout) -> Range<Int>? {
        ShapePathBuilder.cutoutCornerRanges(for: piece)
            .first { $0.cutout.id == cutout.id }?
            .range
    }

    private func localAngleCuts(for cutout: Cutout) -> [AngleCut] {
        guard let range = cutoutCornerRange(for: cutout) else { return [] }
        return piece.angleCuts.compactMap { cut in
            guard range.contains(cut.anchorCornerIndex) else { return nil }
            let local = AngleCut(
                anchorCornerIndex: cut.anchorCornerIndex - range.lowerBound,
                anchorOffset: cut.anchorOffset,
                secondaryCornerIndex: cut.secondaryCornerIndex,
                secondaryOffset: cut.secondaryOffset,
                usesSecondPoint: cut.usesSecondPoint,
                angleDegrees: cut.angleDegrees
            )
            local.id = cut.id
            return local
        }
    }

    private func localCornerRadii(for cutout: Cutout) -> [CornerRadius] {
        guard let range = cutoutCornerRange(for: cutout) else { return [] }
        return piece.cornerRadii.compactMap { radius in
            guard range.contains(radius.cornerIndex) else { return nil }
            let local = CornerRadius(cornerIndex: radius.cornerIndex - range.lowerBound, radius: radius.radius, isInside: radius.isInside)
            local.id = radius.id
            return local
        }
    }

}

struct EdgeTapTarget {
    let edge: EdgePosition
    let segmentIndex: Int?
}

struct EdgeTapGestureOverlay: View {
    let metrics: DrawingMetrics
    let piece: Piece
    let curves: [CurvedEdge]
    let cutouts: [Cutout]
    let angleSegments: [AngleSegment]
    let boundarySegments: [BoundarySegment]
    let edgeTapped: (EdgeTapTarget) -> Void

    var shape: ShapeKind { piece.shape }
    let cutoutEdgeTapped: (UUID, EdgePosition) -> Void
    let angleEdgeTapped: (UUID) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let rect = CGRect(
                            x: metrics.origin.x,
                            y: metrics.origin.y,
                            width: metrics.pieceSize.width * metrics.scale,
                            height: metrics.pieceSize.height * metrics.scale
                        )
                        let hasCurves = curves.contains(where: { $0.radius > 0 })
                        let segmentGroups = Dictionary(grouping: boundarySegments, by: { $0.edge })
                        let hasSplitSegments = segmentGroups.contains { $0.value.count > 1 }
                        let hasMissingEdges = shape == .rectangle && segmentGroups.keys.count < 4
                        let usesCurvedHitTest = shape != .rectangle || hasCurves || hasSplitSegments || hasMissingEdges
                        if rect.contains(value.location) {
                            if let angleId = hitTestAngleEdge(at: value.location) {
                                angleEdgeTapped(angleId)
                                return
                            }
                            if let hit = hitTestCutoutEdge(at: value.location) {
                                cutoutEdgeTapped(hit.cutoutId, hit.edge)
                                return
                            }
                            if let hit = hitTestNotchEdge(at: value.location) {
                                cutoutEdgeTapped(hit.cutoutId, hit.edge)
                                return
                            }
                            if usesCurvedHitTest, let target = hitTestEdge(at: value.location) {
                                edgeTapped(target)
                            }
                            return
                        }
                        if usesCurvedHitTest, let target = hitTestEdge(at: value.location) {
                            edgeTapped(target)
                            return
                        }
                        if shape == .rectangle {
                            let segmentGroups = Dictionary(grouping: boundarySegments, by: { $0.edge })
                            let hasSplitSegments = segmentGroups.contains { $0.value.count > 1 }
                            let hasMissingEdges = segmentGroups.keys.count < 4
                            if hasSplitSegments || hasMissingEdges {
                                return
                            }
                        }
                        if let edge = edgeForOutsideTap(location: value.location, rect: rect, shape: shape) {
                            edgeTapped(EdgeTapTarget(edge: edge, segmentIndex: nil))
                            return
                        }
                    }
            )
    }
}

private extension EdgeTapGestureOverlay {
    func hitTestCutoutEdge(at point: CGPoint) -> (cutoutId: UUID, edge: EdgePosition)? {
        let threshold: CGFloat = 20
        var best: (UUID, EdgePosition, CGFloat)?

        for cutout in cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 {
            if cutout.isNotch || (cutout.kind != .circle && ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, piece: piece, size: metrics.pieceSize)) {
                continue
            }
            let displayCutout = rotatedCutout(cutout)
            let center = metrics.toCanvas(CGPoint(x: displayCutout.centerX, y: displayCutout.centerY))
            let width = max(displayCutout.width * metrics.scale, 1)

            if cutout.kind == .circle {
                let radius = width / 2
                let distanceToCenter = hypot(point.x - center.x, point.y - center.y)
                let distanceFromEdge: CGFloat = abs(distanceToCenter - radius)
                if distanceToCenter <= radius + threshold {
                    let distance = distanceFromEdge
                    if distance < (best?.2 ?? .greatestFiniteMagnitude) {
                        best = (cutout.id, .top, distance)
                    }
                }
                continue
            }

            let corners = GeometryHelpers.cutoutCornerPoints(cutout: displayCutout, size: metrics.pieceSize, shape: shape)
            let edges: [(EdgePosition, CGPoint, CGPoint)] = [
                (.top, corners[0], corners[1]),
                (.right, corners[1], corners[2]),
                (.bottom, corners[2], corners[3]),
                (.left, corners[3], corners[0])
            ]

            for (edge, start, end) in edges {
                if !isInteriorNotchEdge(cutout: cutout, edge: edge, pieceSize: metrics.pieceSize, shape: shape) {
                    continue
                }
                let startCanvas = metrics.toCanvas(start)
                let endCanvas = metrics.toCanvas(end)
                let distance = distanceToSegment(point: point, a: startCanvas, b: endCanvas)
                if distance > threshold { continue }
                if distance < (best?.2 ?? .greatestFiniteMagnitude) {
                    best = (cutout.id, edge, distance)
                }
            }
        }

        if let best {
            return (best.0, best.1)
        }
        return nil
    }

    func hitTestNotchEdge(at point: CGPoint) -> (cutoutId: UUID, edge: EdgePosition)? {
        let threshold: CGFloat = 30
        var best: (UUID, EdgePosition, CGFloat)?

        for cutout in cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 {
            // Only process notches and boundary-touching cutouts
            let isNotchOrBoundary = cutout.isNotch || (cutout.kind != .circle && ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, piece: piece, size: metrics.pieceSize))
            guard isNotchOrBoundary else { continue }
            guard cutout.kind != .circle else { continue }
            
            let displayCutout = rotatedCutout(cutout)
            let corners = GeometryHelpers.cutoutCornerPoints(cutout: displayCutout, size: metrics.pieceSize, shape: shape)
            let edges: [(EdgePosition, CGPoint, CGPoint)] = [
                (.top, corners[0], corners[1]),
                (.right, corners[1], corners[2]),
                (.bottom, corners[2], corners[3]),
                (.left, corners[3], corners[0])
            ]

            for (edge, start, end) in edges {
                if !isInteriorNotchEdge(cutout: cutout, edge: edge, pieceSize: metrics.pieceSize, shape: shape) {
                    continue
                }
                let startCanvas = metrics.toCanvas(start)
                let endCanvas = metrics.toCanvas(end)
                let distance = distanceToSegment(point: point, a: startCanvas, b: endCanvas)
                if distance > threshold { continue }
                if distance < (best?.2 ?? .greatestFiniteMagnitude) {
                    best = (cutout.id, edge, distance)
                }
            }
        }

        if let best {
            return (best.0, best.1)
        }
        return nil
    }

    func hitTestAngleEdge(at point: CGPoint) -> UUID? {
        let threshold: CGFloat = 16
        var best: (UUID, CGFloat)?
        for segment in angleSegments {
            let start = metrics.toCanvas(segment.start)
            let end = metrics.toCanvas(segment.end)
            let distance = distanceToSegment(point: point, a: start, b: end)
            if distance <= threshold, distance < (best?.1 ?? .greatestFiniteMagnitude) {
                best = (segment.id, distance)
            }
        }
        return best?.0
    }

    func hitTestEdge(at point: CGPoint) -> EdgeTapTarget? {
        let origin = metrics.origin
        let width = metrics.pieceSize.width * metrics.scale
        let height = metrics.pieceSize.height * metrics.scale
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        let threshold: CGFloat = 28
        let curveMap = Dictionary(grouping: curves, by: { $0.edge }).compactMapValues { $0.first }

        switch shape {
        case .rectangle:
            let segmentGroups = Dictionary(grouping: boundarySegments, by: { $0.edge })
            let hasSplitSegments = segmentGroups.contains { $0.value.count > 1 }
            let hasMissingEdges = segmentGroups.keys.count < 4
            if hasSplitSegments || hasMissingEdges {
                if let targetEdge = bestEdge(from: [
                    (.top, abs(point.y - rect.minY)),
                    (.bottom, abs(point.y - rect.maxY)),
                    (.left, abs(point.x - rect.minX)),
                    (.right, abs(point.x - rect.maxX))
                ], curveMap: curveMap, point: point, rect: rect, threshold: threshold) {
                    let edgeSegments = boundarySegments.filter { $0.edge == targetEdge }
                    if let closest = edgeSegments.min(by: { lhs, rhs in
                        let lhsMid = CGPoint(x: (lhs.start.x + lhs.end.x) / 2, y: (lhs.start.y + lhs.end.y) / 2)
                        let rhsMid = CGPoint(x: (rhs.start.x + rhs.end.x) / 2, y: (rhs.start.y + rhs.end.y) / 2)
                        let pointPiece = metrics.toPiece(point)
                        let lhsAxis: CGFloat
                        let rhsAxis: CGFloat
                        switch targetEdge {
                        case .left, .right, .legB:
                            lhsAxis = abs(pointPiece.y - lhsMid.y)
                            rhsAxis = abs(pointPiece.y - rhsMid.y)
                        case .top, .bottom, .legA:
                            lhsAxis = abs(pointPiece.x - lhsMid.x)
                            rhsAxis = abs(pointPiece.x - rhsMid.x)
                        case .hypotenuse:
                            lhsAxis = abs(pointPiece.x - lhsMid.x) + abs(pointPiece.y - lhsMid.y)
                            rhsAxis = abs(pointPiece.x - rhsMid.x) + abs(pointPiece.y - rhsMid.y)
                        }
                        if abs(lhsAxis - rhsAxis) < 0.0001 {
                            let lhsStart = metrics.toCanvas(lhs.start)
                            let lhsEnd = metrics.toCanvas(lhs.end)
                            let rhsStart = metrics.toCanvas(rhs.start)
                            let rhsEnd = metrics.toCanvas(rhs.end)
                            let lhsDistance = distanceToSegment(point: point, a: lhsStart, b: lhsEnd)
                            let rhsDistance = distanceToSegment(point: point, a: rhsStart, b: rhsEnd)
                            return lhsDistance < rhsDistance
                        }
                        return lhsAxis < rhsAxis
                    }) {
                        let segmentIndex = hasSplitSegments ? closest.index : nil
                        return EdgeTapTarget(edge: closest.edge, segmentIndex: segmentIndex)
                    }
                }
            }
            let distances: [(EdgePosition, CGFloat)] = [
                (.top, abs(point.y - rect.minY)),
                (.bottom, abs(point.y - rect.maxY)),
                (.left, abs(point.x - rect.minX)),
                (.right, abs(point.x - rect.maxX))
            ]
            if let edge = bestEdge(from: distances, curveMap: curveMap, point: point, rect: rect, threshold: threshold) {
                return EdgeTapTarget(edge: edge, segmentIndex: nil)
            }
            return nil
        case .circle:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            let distanceToCenter = hypot(point.x - center.x, point.y - center.y)
            let distanceFromEdge = abs(distanceToCenter - radius)
            let edgeThreshold = max(threshold, radius * 0.1)
            if distanceToCenter <= radius + edgeThreshold && distanceFromEdge <= edgeThreshold {
                return EdgeTapTarget(edge: .top, segmentIndex: nil)
            }
            return nil
        case .rightTriangle:
            let hypDistance = distanceToLine(
                point: point,
                a: CGPoint(x: rect.maxX, y: rect.minY),
                b: CGPoint(x: rect.minX, y: rect.maxY)
            )
            let distances: [(EdgePosition, CGFloat)] = [
                (.legA, abs(point.y - rect.minY)),
                (.legB, abs(point.x - rect.minX)),
                (.hypotenuse, hypDistance)
            ]
            // Check for split segments (from notches) similar to rectangle case
            let segmentGroups = Dictionary(grouping: boundarySegments, by: { $0.edge })
            let hasMissingEdges = segmentGroups.keys.count < 3
            if let targetEdge = bestEdge(from: distances, curveMap: curveMap, point: point, rect: rect, threshold: threshold) {
                let edgeSegments = boundarySegments.filter { $0.edge == targetEdge }
                let edgeHasMultipleSegments = edgeSegments.count > 1
                if edgeHasMultipleSegments || hasMissingEdges {
                    if let closest = edgeSegments.min(by: { lhs, rhs in
                        let lhsMid = CGPoint(x: (lhs.start.x + lhs.end.x) / 2, y: (lhs.start.y + lhs.end.y) / 2)
                        let rhsMid = CGPoint(x: (rhs.start.x + rhs.end.x) / 2, y: (rhs.start.y + rhs.end.y) / 2)
                        let pointPiece = metrics.toPiece(point)
                        let lhsAxis: CGFloat
                        let rhsAxis: CGFloat
                        switch targetEdge {
                        case .left, .right, .legB:
                            lhsAxis = abs(pointPiece.y - lhsMid.y)
                            rhsAxis = abs(pointPiece.y - rhsMid.y)
                        case .top, .bottom, .legA:
                            lhsAxis = abs(pointPiece.x - lhsMid.x)
                            rhsAxis = abs(pointPiece.x - rhsMid.x)
                        case .hypotenuse:
                            lhsAxis = abs(pointPiece.x - lhsMid.x) + abs(pointPiece.y - lhsMid.y)
                            rhsAxis = abs(pointPiece.x - rhsMid.x) + abs(pointPiece.y - rhsMid.y)
                        }
                        if abs(lhsAxis - rhsAxis) < 0.0001 {
                            let lhsStart = metrics.toCanvas(lhs.start)
                            let lhsEnd = metrics.toCanvas(lhs.end)
                            let rhsStart = metrics.toCanvas(rhs.start)
                            let rhsEnd = metrics.toCanvas(rhs.end)
                            let lhsDistance = distanceToSegment(point: point, a: lhsStart, b: lhsEnd)
                            let rhsDistance = distanceToSegment(point: point, a: rhsStart, b: rhsEnd)
                            return lhsDistance < rhsDistance
                        }
                        return lhsAxis < rhsAxis
                    }) {
                        let segmentIndex = edgeHasMultipleSegments ? closest.index : nil
                        return EdgeTapTarget(edge: closest.edge, segmentIndex: segmentIndex)
                    }
                }
                // Edge doesn't have multiple segments, return without segment index
                return EdgeTapTarget(edge: targetEdge, segmentIndex: nil)
            }
            return nil
        case .quarterCircle:
            let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
            let radius = rect.width
            let arcDistance = abs(hypot(local.x, local.y) - radius)
            let distances: [(EdgePosition, CGFloat)] = [
                (.top, abs(point.y - rect.minY)),
                (.left, abs(point.x - rect.minX)),
                (.hypotenuse, arcDistance)
            ]
            if let edge = bestEdge(from: distances, curveMap: curveMap, point: point, rect: rect, threshold: threshold) {
                return EdgeTapTarget(edge: edge, segmentIndex: nil)
            }
            return nil
        }
    }

    func distanceToSegment(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: point.x - a.x, y: point.y - a.y)
        let abLen2 = ab.x * ab.x + ab.y * ab.y
        if abLen2 == 0 { return hypot(point.x - a.x, point.y - a.y) }
        var t = (ap.x * ab.x + ap.y * ab.y) / abLen2
        t = min(max(t, 0), 1)
        let closest = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
        return hypot(point.x - closest.x, point.y - closest.y)
    }

    func edgeForOutsideTap(location: CGPoint, rect: CGRect, shape: ShapeKind) -> EdgePosition? {
        if shape == .circle {
            return rect.contains(location) ? nil : .top
        }
        if shape == .rightTriangle {
            let p0 = CGPoint(x: rect.minX, y: rect.minY)
            let p1 = CGPoint(x: rect.minX, y: rect.maxY)
            let p2 = CGPoint(x: rect.maxX, y: rect.minY)
            let distances: [(EdgePosition, CGFloat)] = [
                (.legA, distanceToSegment(point: location, a: p0, b: p2)),
                (.legB, distanceToSegment(point: location, a: p1, b: p0)),
                (.hypotenuse, distanceToSegment(point: location, a: p1, b: p2))
            ]
            return distances.min(by: { $0.1 < $1.1 })?.0
        }
        let leftDist = rect.minX - location.x
        let rightDist = location.x - rect.maxX
        let topDist = rect.minY - location.y
        let bottomDist = location.y - rect.maxY

        let outsideLeft = leftDist > 0
        let outsideRight = rightDist > 0
        let outsideTop = topDist > 0
        let outsideBottom = bottomDist > 0

        var candidates: [(EdgePosition, CGFloat)] = []
        if outsideLeft { candidates.append((.left, leftDist)) }
        if outsideRight { candidates.append((.right, rightDist)) }
        if outsideTop { candidates.append((.top, topDist)) }
        if outsideBottom { candidates.append((.bottom, bottomDist)) }

        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    func bestEdge(from distances: [(EdgePosition, CGFloat)], curveMap: [EdgePosition: CurvedEdge], point: CGPoint, rect: CGRect, threshold: CGFloat) -> EdgePosition? {
        var candidates = distances.filter { $0.1 <= threshold }
        if !curveMap.isEmpty {
            for (edge, curve) in curveMap {
                guard curve.radius > 0, let geometry = edgeGeometry(for: edge, rect: rect) else { continue }
                let control = controlPoint(for: geometry, curve: curve, scale: metrics.scale)
                let curveDistance = distanceToCurve(point: point, start: geometry.start, control: control, end: geometry.end)
                candidates.append((edge, curveDistance))
            }
        }
        return candidates.filter { $0.1 <= threshold }.min(by: { $0.1 < $1.1 })?.0
    }

    func edgeGeometry(for edge: EdgePosition, rect: CGRect) -> (start: CGPoint, end: CGPoint, normal: CGPoint)? {
        switch edge {
        case .top:
            return (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: 0, y: -1))
        case .right:
            return (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: 1, y: 0))
        case .bottom:
            return (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: 0, y: 1))
        case .left:
            return (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: -1, y: 0))
        case .legA:
            return (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: 0, y: -1))
        case .legB:
            return (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: -1, y: 0))
        case .hypotenuse:
            return (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: 0.7, y: 0.7))
        }
    }

    func controlPoint(for geometry: (start: CGPoint, end: CGPoint, normal: CGPoint), curve: CurvedEdge, scale: CGFloat) -> CGPoint {
        let mid = CGPoint(x: (geometry.start.x + geometry.end.x) / 2, y: (geometry.start.y + geometry.end.y) / 2)
        let direction: CGFloat = curve.isConcave ? -1 : 1
        let normal = normalized(geometry.normal)
        return CGPoint(x: mid.x + normal.x * curve.radius * scale * direction, y: mid.y + normal.y * curve.radius * scale * direction)
    }

    func distanceToCurve(point: CGPoint, start: CGPoint, control: CGPoint, end: CGPoint) -> CGFloat {
        let samples = 20
        var minDistance = CGFloat.greatestFiniteMagnitude
        for index in 0...samples {
            let t = CGFloat(index) / CGFloat(samples)
            let curvePoint = quadBezierPoint(t: t, start: start, control: control, end: end)
            let distance = hypot(point.x - curvePoint.x, point.y - curvePoint.y)
            minDistance = min(minDistance, distance)
        }
        return minDistance
    }

    func distanceToCurveSegment(point: CGPoint, segmentStart: CGPoint, segmentEnd: CGPoint, edge: EdgePosition, rect: CGRect, curve: CurvedEdge) -> CGFloat {
        guard let geometry = edgeGeometry(for: edge, rect: rect) else {
            return distanceToSegment(point: point, a: segmentStart, b: segmentEnd)
        }
        let tStart = tForEdge(point: segmentStart, geometry: geometry, edge: edge)
        let tEnd = tForEdge(point: segmentEnd, geometry: geometry, edge: edge)
        let tMin = min(tStart, tEnd)
        let tMax = max(tStart, tEnd)
        if tMax - tMin < 0.0001 {
            let control = controlPoint(for: geometry, curve: curve, scale: metrics.scale)
            let curvePoint = quadBezierPoint(t: tMin, start: geometry.start, control: control, end: geometry.end)
            return hypot(point.x - curvePoint.x, point.y - curvePoint.y)
        }
        let samples = 6
        let control = controlPoint(for: geometry, curve: curve, scale: metrics.scale)
        var minDistance = CGFloat.greatestFiniteMagnitude
        for index in 0...samples {
            let t = tMin + (tMax - tMin) * (CGFloat(index) / CGFloat(samples))
            let curvePoint = quadBezierPoint(t: t, start: geometry.start, control: control, end: geometry.end)
            let distance = hypot(point.x - curvePoint.x, point.y - curvePoint.y)
            minDistance = min(minDistance, distance)
        }
        return minDistance
    }

    func tForEdge(point: CGPoint, geometry: (start: CGPoint, end: CGPoint, normal: CGPoint), edge: EdgePosition) -> CGFloat {
        switch edge {
        case .top, .bottom, .legA:
            let denom = geometry.end.x - geometry.start.x
            if abs(denom) < 0.0001 { return 0.5 }
            return (point.x - geometry.start.x) / denom
        case .left, .right, .legB:
            let denom = geometry.end.y - geometry.start.y
            if abs(denom) < 0.0001 { return 0.5 }
            return (point.y - geometry.start.y) / denom
        case .hypotenuse:
            let total = hypot(geometry.end.x - geometry.start.x, geometry.end.y - geometry.start.y)
            if total < 0.0001 { return 0.5 }
            let dist = hypot(point.x - geometry.start.x, point.y - geometry.start.y)
            return dist / total
        }
    }

    func quadBezierPoint(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let oneMinus = 1 - t
        let x = oneMinus * oneMinus * start.x + 2 * oneMinus * t * control.x + t * t * end.x
        let y = oneMinus * oneMinus * start.y + 2 * oneMinus * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    func normalized(_ point: CGPoint) -> CGPoint {
        let length = max(sqrt(point.x * point.x + point.y * point.y), 0.0001)
        return CGPoint(x: point.x / length, y: point.y / length)
    }

    func distanceToLine(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let numerator = abs(dy * point.x - dx * point.y + b.x * a.y - b.y * a.x)
        let denominator = max(sqrt(dx * dx + dy * dy), 0.0001)
        return numerator / denominator
    }

    func isPointInsideNotchSpan(point: CGPoint, edge: EdgePosition, cutouts: [Cutout], metrics: DrawingMetrics) -> Bool {
        let edgeEpsilon: CGFloat = 0.01
        let edgeThreshold: CGFloat = 10
        let pieceOrigin = metrics.origin
        let pieceWidth = metrics.pieceSize.width * metrics.scale
        let pieceHeight = metrics.pieceSize.height * metrics.scale

        for cutout in cutouts where (cutout.isNotch || ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, piece: piece, size: metrics.pieceSize)) && cutout.centerX >= 0 && cutout.centerY >= 0 {
            let displayCutout = rotatedCutout(cutout)
            let corners = GeometryHelpers.cutoutCornerPoints(cutout: displayCutout, size: metrics.pieceSize, shape: shape)
            let bounds = GeometryHelpers.bounds(for: corners)
            let minX = bounds.minX
            let maxX = bounds.maxX
            let minY = bounds.minY
            let maxY = bounds.maxY

            switch edge {
            case .top where minY <= edgeEpsilon:
                let edgeY = pieceOrigin.y
                if abs(point.y - edgeY) > edgeThreshold { continue }
                let left = metrics.toCanvas(CGPoint(x: minX, y: minY)).x
                let right = metrics.toCanvas(CGPoint(x: maxX, y: minY)).x
                if point.x >= min(left, right) && point.x <= max(left, right) { return true }
            case .bottom where maxY >= metrics.pieceSize.height - edgeEpsilon:
                let edgeY = pieceOrigin.y + pieceHeight
                if abs(point.y - edgeY) > edgeThreshold { continue }
                let left = metrics.toCanvas(CGPoint(x: minX, y: maxY)).x
                let right = metrics.toCanvas(CGPoint(x: maxX, y: maxY)).x
                if point.x >= min(left, right) && point.x <= max(left, right) { return true }
            case .left where minX <= edgeEpsilon:
                let edgeX = pieceOrigin.x
                if abs(point.x - edgeX) > edgeThreshold { continue }
                let top = metrics.toCanvas(CGPoint(x: minX, y: minY)).y
                let bottom = metrics.toCanvas(CGPoint(x: minX, y: maxY)).y
                if point.y >= min(top, bottom) && point.y <= max(top, bottom) { return true }
            case .right where maxX >= metrics.pieceSize.width - edgeEpsilon:
                let edgeX = pieceOrigin.x + pieceWidth
                if abs(point.x - edgeX) > edgeThreshold { continue }
                let top = metrics.toCanvas(CGPoint(x: maxX, y: minY)).y
                let bottom = metrics.toCanvas(CGPoint(x: maxX, y: maxY)).y
                if point.y >= min(top, bottom) && point.y <= max(top, bottom) { return true }
            default:
                continue
            }
        }
        return false
    }
}

private func rotatedCutout(_ cutout: Cutout) -> Cutout {
    // For hypotenuse-aligned cutouts, do NOT swap width/height here.
    // The dimension swap happens inside cutoutCornerPoints for hypotenuse.
    // For custom angles and legs, swap width/height here for the coordinate transform.
    // This ensures consistent behavior: custom angle at 0° looks like legs orientation.
    let isHypotenuseOriented = cutout.orientation == .hypotenuse
    return Cutout(
        kind: cutout.kind,
        width: isHypotenuseOriented ? cutout.width : cutout.height,
        height: isHypotenuseOriented ? cutout.height : cutout.width,
        centerX: cutout.centerY,
        centerY: cutout.centerX,
        isNotch: cutout.isNotch,
        orientation: cutout.orientation,
        customAngleDegrees: cutout.customAngleDegrees
    )
}

private func rotatedPointToRaw(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.y, y: point.x)
}

private func isEffectiveNotch(_ cutout: Cutout, piece: Piece, pieceSize: CGSize) -> Bool {
    if cutout.isNotch { return true }
    guard cutout.kind != .circle else { return false }
    return ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, piece: piece, size: pieceSize)
}

private func isInteriorNotchEdge(cutout: Cutout, edge: EdgePosition, pieceSize: CGSize, shape: ShapeKind) -> Bool {
    let displayCutout = rotatedCutout(cutout)
    let displaySize = CGSize(width: pieceSize.height, height: pieceSize.width)
    let corners = GeometryHelpers.cutoutCornerPoints(cutout: displayCutout, size: displaySize, shape: shape)
    let bounds = GeometryHelpers.bounds(for: corners)
    let minX = bounds.minX
    let maxX = bounds.maxX
    let minY = bounds.minY
    let maxY = bounds.maxY
    let edgeEpsilon: CGFloat = 0.01

    // For right triangles, also check if the edge crosses the hypotenuse
    if shape == .rightTriangle {
        // Get the actual corner points of the cutout edge
        let edgeCorners = cutoutEdgeCorners(corners: corners, edge: edge)
        let start = edgeCorners.start
        let end = edgeCorners.end
        
        // Check if both endpoints of this edge are outside the triangle (beyond hypotenuse)
        // Hypotenuse line: x + y = displaySize.width (in display coordinates)
        let startValue = start.x + start.y
        let endValue = end.x + end.y
        let hypotenuseValue = displaySize.width
        
        // If both endpoints are beyond the hypotenuse, this edge is not interior
        if startValue > hypotenuseValue + edgeEpsilon && endValue > hypotenuseValue + edgeEpsilon {
            return false
        }
        
        // If one endpoint is beyond the hypotenuse and one is inside, the edge is clipped
        // We should still show it if part of it is visible
    }

    switch edge {
    case .left:
        return minX > edgeEpsilon
    case .right:
        return maxX < displaySize.width - edgeEpsilon
    case .top:
        return minY > edgeEpsilon
    case .bottom:
        return maxY < displaySize.height - edgeEpsilon
    default:
        return true
    }
}

private func cutoutEdgeCorners(corners: [CGPoint], edge: EdgePosition) -> (start: CGPoint, end: CGPoint) {
    guard corners.count == 4 else {
        return (CGPoint.zero, CGPoint.zero)
    }
    switch edge {
    case .top:
        return (corners[0], corners[1])
    case .right:
        return (corners[1], corners[2])
    case .bottom:
        return (corners[2], corners[3])
    case .left:
        return (corners[3], corners[0])
    default:
        return (CGPoint.zero, CGPoint.zero)
    }
}
