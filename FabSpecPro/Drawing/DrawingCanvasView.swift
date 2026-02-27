import SwiftUI
import SwiftData

struct DrawingCanvasView: View {
    @Bindable var piece: Piece
    let selectedTreatment: EdgeTreatment?
    @Environment(\.modelContext) private var modelContext
    @State private var lastEdgeTapId = UUID()
    private let lengthYOffsetPoints: CGFloat = -17
    private let lengthYOffsetInches: CGFloat = 0.125
    private let noteYOffsetInches: CGFloat = 2.0
    private let noteYOffsetPoints: CGFloat = 30
    private let lengthLabelPadding: CGFloat = 15
    private let widthLabelPadding: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let metrics = DrawingMetrics(piece: piece, in: proxy.size)

            ZStack {
                Canvas { context, _ in
                    let path = ShapePathBuilder.path(for: piece)

                    context.drawLayer { layerContext in
                        layerContext.translateBy(x: metrics.origin.x, y: metrics.origin.y)
                        layerContext.scaleBy(x: metrics.scale, y: metrics.scale)
                        layerContext.stroke(path, with: .color(Theme.primaryText), lineWidth: 0.5)

                    for cutout in piece.cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 && !isEffectiveNotch(cutout, piece: piece, pieceSize: metrics.pieceSize) {
                        let displayCutout = rotatedCutout(cutout)
                        let angleCuts = localAngleCuts(for: cutout)
                        let cornerRadii = localCornerRadii(for: cutout)
                        let cutoutPath = ShapePathBuilder.cutoutPath(displayCutout, angleCuts: angleCuts, cornerRadii: cornerRadii)
                        layerContext.stroke(cutoutPath, with: .color(Theme.accent), lineWidth: 0.5)
                    }
                }

                for cutout in piece.cutouts where cutout.centerX >= 0 && cutout.centerY >= 0 {
                    if isEffectiveNotch(cutout, piece: piece, pieceSize: metrics.pieceSize) {
                        drawNotchDimensionLabels(in: &context, cutout: cutout, metrics: metrics)
                    }
                }

                    drawDimensionLabels(in: &context, metrics: metrics)
                    drawEdgeLabels(in: &context, metrics: metrics, refreshToken: lastEdgeTapId)
                    drawCornerLabels(in: &context, metrics: metrics)
                    drawCutoutNotes(in: &context, metrics: metrics)
                }

                let expanded = expandedDisplayBounds(metrics: metrics)
                let totalWidth = MeasurementParser.formatInches(Double(expanded.height))
                let totalLength = MeasurementParser.formatInches(Double(expanded.width))
                Text("\(totalWidth) in W x \(totalLength) in L")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)

                EdgeTapGestureOverlay(
                    metrics: metrics,
                    shape: piece.shape,
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
        let lengthLabel = Text("\(lengthText) in")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
        let depthLabel = Text("\(depthText) in")
            .font(.system(size: 11, weight: .semibold))
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
                    let widthLabelText = "\(MeasurementParser.formatInches(Double(leftMetric.length))) in"
                    let adjustedWidthLabel = Text(widthLabelText)
                        .font(.system(size: 11, weight: .semibold))
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
                    let lengthLabelText = "\(MeasurementParser.formatInches(Double(topMetric.length))) in"
                    let adjustedLengthLabel = Text(lengthLabelText)
                        .font(.system(size: 11, weight: .semibold))
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
                    let widthLabelText = "\(MeasurementParser.formatInches(Double(rightMetric.length))) in"
                    let adjustedWidthLabel = Text(widthLabelText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    let centerY = origin.y + rightMetric.center.y * metrics.scale
                    let rightPoint = CGPoint(x: right + widthLabelPadding, y: centerY)
                    context.draw(adjustedWidthLabel, at: rightPoint, anchor: .center)
                }

                if segmentCounts[.bottom] == 1, let bottomMetric = sideMetrics[.bottom], abs(bottomMetric.length - fullWidth) > 0.01 {
                    let lengthLabelText = "\(MeasurementParser.formatInches(Double(bottomMetric.length))) in"
                    let adjustedLengthLabel = Text(lengthLabelText)
                        .font(.system(size: 11, weight: .semibold))
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
            let legALabel = lengthLabel
            let legBLabel = depthLabel
            let lengthPoint = CGPoint(x: origin.x + width / 2, y: top - lengthLabelPadding)
            let widthPoint = CGPoint(x: left - widthLabelPadding, y: origin.y + height / 2)
            context.draw(legALabel, at: lengthPoint, anchor: .center)
            context.draw(legBLabel, at: widthPoint, anchor: .center)
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
        let labelOffset: CGFloat = 12

        let pieceBounds = bounds(for: pieceCorners)
        let pieceCenter = CGPoint(x: (pieceBounds.minX + pieceBounds.maxX) / 2, y: (pieceBounds.minY + pieceBounds.maxY) / 2)
        let isPieceClockwise = polygonIsClockwise(pieceCorners)

        for (index, point) in pieceCorners.enumerated() {
            let label = Text(cornerLabel(for: index))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            let direction = cornerLabelDirection(points: pieceCorners, index: index, center: pieceCenter, clockwise: isPieceClockwise)
            let displayPoint = CGPoint(
                x: origin.x + point.x * scale + direction.x * labelOffset,
                y: origin.y + point.y * scale + direction.y * labelOffset
            )
            context.draw(label, at: displayPoint, anchor: .center)
        }

        for entry in ShapePathBuilder.cutoutCornerRanges(for: piece) {
            let displayCutout = rotatedCutout(entry.cutout)
            let corners = cutoutCornerPoints(for: displayCutout)
            let bounds = bounds(for: corners)
            let center = CGPoint(x: (bounds.minX + bounds.maxX) / 2, y: (bounds.minY + bounds.maxY) / 2)
            let isClockwise = polygonIsClockwise(corners)
            for (localIndex, point) in corners.enumerated() {
                let labelIndex = entry.range.lowerBound + localIndex
                let label = Text(cornerLabel(for: labelIndex))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                let direction = cornerLabelDirection(points: corners, index: localIndex, center: center, clockwise: isClockwise)
                let displayPoint = CGPoint(
                    x: origin.x + point.x * scale + direction.x * labelOffset,
                    y: origin.y + point.y * scale + direction.y * labelOffset
                )
                context.draw(label, at: displayPoint, anchor: .center)
            }
        }
    }

    private func cutoutCornerPoints(for cutout: Cutout) -> [CGPoint] {
        let halfWidth = cutout.width / 2
        let halfHeight = cutout.height / 2
        let center = CGPoint(x: cutout.centerX, y: cutout.centerY)
        return [
            CGPoint(x: center.x - halfWidth, y: center.y - halfHeight),
            CGPoint(x: center.x + halfWidth, y: center.y - halfHeight),
            CGPoint(x: center.x + halfWidth, y: center.y + halfHeight),
            CGPoint(x: center.x - halfWidth, y: center.y + halfHeight)
        ]
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
            if piece.shape == .rightTriangle {
                switch assignment.edge {
                case .top, .right, .bottom, .left:
                    continue
                default:
                    break
                }
            }
            if let segmentEdge = assignment.segmentEdge {
                if let segment = boundarySegments.first(where: { $0.edge == segmentEdge.edge && $0.index == segmentEdge.index }) {
                    let label = Text(code)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    let position = segmentEdgeLabelPosition(segment: segment, metrics: metrics)
                    context.draw(label, at: position, anchor: .center)
                }
                continue
            }
            if piece.shape == .rectangle, (segmentCounts[assignment.edge] ?? 0) > 1 {
                let hasSegmentAssignments = piece.edgeAssignments.contains { $0.segmentEdge?.edge == assignment.edge }
                if hasSegmentAssignments {
                    continue
                }
                if (piece.curve(for: assignment.edge)?.radius ?? 0) <= 0 {
                    continue
                }
            }
            let label = Text(code)
                .font(.system(size: 11, weight: .bold))
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
            context.draw(label, at: position, anchor: .center)
        }

        for assignment in piece.edgeAssignments {
            let code = assignment.treatmentAbbreviation
            guard !code.isEmpty else { continue }
            guard let cutoutEdge = assignment.cutoutEdge else { continue }
            guard let cutout = piece.cutouts.first(where: { $0.id == cutoutEdge.id }) else { continue }
            guard cutout.centerX >= 0 && cutout.centerY >= 0 else { continue }
            guard isInteriorNotchEdge(cutout: cutout, edge: cutoutEdge.edge, pieceSize: metrics.pieceSize) else { continue }
            let label = Text(code)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.accent)
            let position = cutoutEdgeLabelPosition(cutout: cutout, edge: cutoutEdge.edge, metrics: metrics)
            context.draw(label, at: position, anchor: .center)
        }
    }

    private func drawCutoutNotes(in context: inout GraphicsContext, metrics: DrawingMetrics) {
        let visibleCutouts = piece.cutouts.filter { $0.centerX >= 0 && $0.centerY >= 0 && !isEffectiveNotch($0, piece: piece, pieceSize: metrics.pieceSize) }
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            let y = noteStart.y + CGFloat(index) * 12
            context.draw(text, at: CGPoint(x: noteStart.x, y: y), anchor: .center)
        }
    }

    private func cutoutNoteLines(from cutouts: [Cutout]) -> [String] {
        var lines: [String] = []
        let leftCurveOffset = curveEdgeOffset(edge: .left)
        let topCurveOffset = curveEdgeOffset(edge: .top)

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
            let fromLeftValue = max(displayCutout.centerX + leftCurveOffset, 0)
            let fromTopValue = max(displayCutout.centerY + topCurveOffset, 0)
            let fromLeft = MeasurementParser.formatInches(fromLeftValue)
            let fromTop = MeasurementParser.formatInches(fromTopValue)
            lines.append("\(label): \(sizeText) - \(fromLeft)\" From Left to Center, \(fromTop)\" From Top to Center")
        }

        return wrapLines(lines, maxLength: 48)
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
        let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        let metricsInfo = notchInteriorEdgeMetrics(cutout: cutout, metrics: metrics, polygon: polygon)
        let widthValue = metricsInfo?.width ?? CGFloat(cutout.width)
        let lengthValue = metricsInfo?.length ?? CGFloat(cutout.height)
        let widthText = MeasurementParser.formatInches(Double(widthValue))
        let heightText = MeasurementParser.formatInches(Double(lengthValue))
        let widthLabel = Text("\(widthText) in")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
        let lengthLabel = Text("\(heightText) in")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)

        let center = CGPoint(x: displayCutout.centerX, y: displayCutout.centerY)
        let halfWidth = displayCutout.width / 2
        let halfHeight = displayCutout.height / 2
        let widthPadding = 12 / max(metrics.scale, 0.01)
        let heightPadding = 6 / max(metrics.scale, 0.01)
        let minX = center.x - halfWidth
        let maxX = center.x + halfWidth
        let minY = center.y - halfHeight
        let maxY = center.y + halfHeight
        let pieceWidth = metrics.pieceSize.width
        let pieceHeight = metrics.pieceSize.height
        let edgeEpsilon: CGFloat = 0.01

        let interiorX: CGFloat
        if minX <= edgeEpsilon {
            interiorX = maxX + widthPadding
        } else if maxX >= pieceWidth - edgeEpsilon {
            interiorX = minX - widthPadding
        } else {
            interiorX = maxX + widthPadding
        }

        let interiorY: CGFloat
        if minY <= edgeEpsilon {
            interiorY = maxY + heightPadding
        } else if maxY >= pieceHeight - edgeEpsilon {
            interiorY = minY - heightPadding
        } else {
            interiorY = maxY + heightPadding
        }

        let widthPoint = CGPoint(x: interiorX, y: metricsInfo?.widthCenterY ?? center.y)
        let lengthPoint = CGPoint(x: metricsInfo?.lengthCenterX ?? center.x, y: interiorY)

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
        }
        var horizontalLen: CGFloat = 0
        var horizontalCenterX: CGFloat = displayCutout.centerX
        if let interiorY {
            horizontalLen = segmentLengthOnLine(points: polygon, isVertical: false, value: interiorY, rangeMin: minX, rangeMax: maxX)
            if horizontalLen > 0 {
                horizontalCenterX = segmentCenterOnLine(points: polygon, isVertical: false, value: interiorY, rangeMin: minX, rangeMax: maxX)
            }
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
                if edge == .top || edge == .bottom {
                    lengthValue = abs(segment.end.x - segment.start.x)
                } else {
                    lengthValue = abs(segment.end.y - segment.start.y)
                }
                let text = MeasurementParser.formatInches(Double(lengthValue))
                let label = Text("\(text) in")
                    .font(.system(size: 9, weight: .semibold))
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
            if let geometry = edgeGeometryFromPolygon(edge: edge, polygon: polygon, shape: shape, baseBounds: baseBounds) {
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
            if let geometry = edgeGeometryFromPolygon(edge: edge, polygon: polygon, shape: shape, baseBounds: baseBounds) {
                let mid = CGPoint(x: (geometry.start.x + geometry.end.x) / 2, y: (geometry.start.y + geometry.end.y) / 2)
                let offsetDistance = 10 / max(metrics.scale, 0.01)
                let adjusted = offsetOutsidePolygon(
                    point: mid,
                    segmentStart: geometry.start,
                    segmentEnd: geometry.end,
                    polygon: polygon,
                    distance: offsetDistance
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
            let baseBounds = piece.shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : nil
            let geometry: (start: CGPoint, end: CGPoint, normal: CGPoint)?
            if piece.shape == .rectangle {
                let size = ShapePathBuilder.displaySize(for: piece)
                switch segment.edge {
                case .top:
                    geometry = (CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: -1))
                case .right:
                    geometry = (CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 1, y: 0))
                case .bottom:
                    geometry = (CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 1))
                case .left:
                    geometry = (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
                default:
                    geometry = edgeGeometryFromPolygon(edge: segment.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds)
                }
            } else {
                geometry = edgeGeometryFromPolygon(edge: segment.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds)
            }
            if let geometry {
                let denom: CGFloat
                let t: CGFloat
                switch segment.edge {
                case .top, .bottom, .legA:
                    denom = geometry.end.x - geometry.start.x
                    t = denom == 0 ? 0.5 : (mid.x - geometry.start.x) / denom
                case .left, .right, .legB:
                    denom = geometry.end.y - geometry.start.y
                    t = denom == 0 ? 0.5 : (mid.y - geometry.start.y) / denom
                case .hypotenuse:
                    let total = distance(geometry.start, geometry.end)
                    t = total == 0 ? 0.5 : distance(geometry.start, mid) / total
                }
                let clampedT = min(max(t, 0), 1)
                let control = controlPointDisplay(for: geometry, curve: curve)
                let curvePoint = quadBezierPoint(t: clampedT, start: geometry.start, control: control, end: geometry.end)
                let curveBaseOffset = CGFloat(segment.edge == .hypotenuse ? 12 : 8) / max(metrics.scale, 0.01)
                var curveOffsetDistance = curveBaseOffset
                if segment.edge == .bottom {
                    curveOffsetDistance += 4 / max(metrics.scale, 0.01)
                }
                if segment.edge == .left || segment.edge == .right {
                    curveOffsetDistance += (20 / max(metrics.scale, 0.01))
                }
                let outward = normalized(geometry.normal)
                var adjusted = offsetRelativeToPolygon(
                    point: curvePoint,
                    segmentStart: geometry.start,
                    segmentEnd: geometry.end,
                    polygon: polygon,
                    distance: curveOffsetDistance,
                    preferInside: false,
                    preferredDirection: outward
                )
                if pointIsInsidePolygon(adjusted, polygon: polygon) {
                    adjusted = CGPoint(
                        x: curvePoint.x - outward.x * curveOffsetDistance,
                        y: curvePoint.y - outward.y * curveOffsetDistance
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
        default:
            direction = CGPoint(x: 0, y: -1)
        }
                let offsetDistance = (segment.edge == .left || segment.edge == .right)
                    ? (baseOffset + sideBoost + extraPadding + (10 / max(metrics.scale, 0.01)))
                    : baseOffset
        let adjusted = CGPoint(x: mid.x + direction.x * offsetDistance, y: mid.y + direction.y * offsetDistance)
        return metrics.toCanvas(adjusted)
    }

    private func segmentEdgeLabelPosition(segment: BoundarySegment, metrics: DrawingMetrics) -> CGPoint {
        let mid = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
        if let curve = piece.curve(for: segment.edge), curve.radius > 0 {
            let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
            let baseBounds = piece.shape == .rightTriangle ? CGRect(origin: .zero, size: ShapePathBuilder.displaySize(for: piece)) : nil
            let geometry: (start: CGPoint, end: CGPoint, normal: CGPoint)?
            if piece.shape == .rectangle {
                let size = ShapePathBuilder.displaySize(for: piece)
                switch segment.edge {
                case .top:
                    geometry = (CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: -1))
                case .right:
                    geometry = (CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 1, y: 0))
                case .bottom:
                    geometry = (CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 1))
                case .left:
                    geometry = (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
                default:
                    geometry = edgeGeometryFromPolygon(edge: segment.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds)
                }
            } else {
                geometry = edgeGeometryFromPolygon(edge: segment.edge, polygon: polygon, shape: piece.shape, baseBounds: baseBounds)
            }
            if let geometry {
                let denom: CGFloat
                let t: CGFloat
                switch segment.edge {
                case .top, .bottom, .legA:
                    denom = geometry.end.x - geometry.start.x
                    t = denom == 0 ? 0.5 : (mid.x - geometry.start.x) / denom
                case .left, .right, .legB:
                    denom = geometry.end.y - geometry.start.y
                    t = denom == 0 ? 0.5 : (mid.y - geometry.start.y) / denom
                case .hypotenuse:
                    let total = distance(geometry.start, geometry.end)
                    t = total == 0 ? 0.5 : distance(geometry.start, mid) / total
                }
                let clampedT = min(max(t, 0), 1)
                let control = controlPointDisplay(for: geometry, curve: curve)
                let curvePoint = quadBezierPoint(t: clampedT, start: geometry.start, control: control, end: geometry.end)
                let offsetDistance = 6 / max(metrics.scale, 0.01)
                let centroid = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                let center = CGPoint(x: centroid.x / CGFloat(polygon.count), y: centroid.y / CGFloat(polygon.count))
                let outward = normalized(CGPoint(x: curvePoint.x - center.x, y: curvePoint.y - center.y))
                let adjusted = offsetRelativeToPolygon(
                    point: curvePoint,
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
        let baseOffset = 6 / max(metrics.scale, 0.01)
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
        default:
            direction = CGPoint(x: 0, y: -1)
        }
        let adjusted = CGPoint(x: mid.x + direction.x * baseOffset, y: mid.y + direction.y * baseOffset)
        return metrics.toCanvas(adjusted)
    }

    private func cutoutEdgeLabelPosition(cutout: Cutout, edge: EdgePosition, metrics: DrawingMetrics) -> CGPoint {
        let displayCutout = rotatedCutout(cutout)
        let halfWidth = displayCutout.width / 2
        let halfHeight = displayCutout.height / 2
        let center = CGPoint(x: displayCutout.centerX, y: displayCutout.centerY)
        let point: CGPoint

        if cutout.kind == .circle {
            point = center
            return metrics.toCanvas(point)
        }

        let polygon = ShapePathBuilder.displayPolygonPoints(for: piece, includeAngles: true)
        if let metricsInfo = notchInteriorEdgeMetrics(cutout: cutout, metrics: metrics, polygon: polygon) {
            switch edge {
            case .left:
                point = CGPoint(x: center.x - halfWidth, y: metricsInfo.widthCenterY)
            case .right:
                point = CGPoint(x: center.x + halfWidth, y: metricsInfo.widthCenterY)
            case .top:
                point = CGPoint(x: metricsInfo.lengthCenterX, y: center.y - halfHeight)
            case .bottom:
                point = CGPoint(x: metricsInfo.lengthCenterX, y: center.y + halfHeight)
            default:
                point = center
            }
            let offsetDistance = 6 / max(metrics.scale, 0.01)
            let adjusted = offsetOutsidePolygon(
                point: point,
                segmentStart: segmentStartPoint(for: edge, cutout: displayCutout),
                segmentEnd: segmentEndPoint(for: edge, cutout: displayCutout),
                polygon: polygon,
                distance: offsetDistance
            )
            return metrics.toCanvas(adjusted)
        }

        let minX = center.x - halfWidth
        let maxX = center.x + halfWidth
        let minY = center.y - halfHeight
        let maxY = center.y + halfHeight
        let cutoutPolygon = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY)
        ]

        switch edge {
        case .top:
            point = CGPoint(x: center.x, y: minY)
        case .bottom:
            point = CGPoint(x: center.x, y: maxY)
        case .left:
            point = CGPoint(x: minX, y: center.y)
        case .right:
            point = CGPoint(x: maxX, y: center.y)
        default:
            point = CGPoint(x: center.x, y: minY)
        }

        let offsetDistance = 6 / max(metrics.scale, 0.01)
        let adjusted = offsetRelativeToPolygon(
            point: point,
            segmentStart: segmentStartPoint(for: edge, cutout: displayCutout),
            segmentEnd: segmentEndPoint(for: edge, cutout: displayCutout),
            polygon: cutoutPolygon,
            distance: offsetDistance,
            preferInside: true,
            preferredDirection: nil
        )
        return metrics.toCanvas(adjusted)
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
        let tolerance: CGFloat = 1.0
        return pointLineDistance(point: start, a: a, b: b) <= tolerance &&
            pointLineDistance(point: end, a: a, b: b) <= tolerance
    }

    private func pointLineDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let denom = max(sqrt(dx * dx + dy * dy), 0.0001)
        return abs(dy * point.x - dx * point.y + b.x * a.y - b.y * a.x) / denom
    }

    private func segmentStartPoint(for edge: EdgePosition, cutout: Cutout) -> CGPoint {
        let halfWidth = cutout.width / 2
        let halfHeight = cutout.height / 2
        let center = CGPoint(x: cutout.centerX, y: cutout.centerY)
        switch edge {
        case .left:
            return CGPoint(x: center.x - halfWidth, y: center.y - halfHeight)
        case .right:
            return CGPoint(x: center.x + halfWidth, y: center.y - halfHeight)
        case .top:
            return CGPoint(x: center.x - halfWidth, y: center.y - halfHeight)
        case .bottom:
            return CGPoint(x: center.x - halfWidth, y: center.y + halfHeight)
        default:
            return center
        }
    }

    private func segmentEndPoint(for edge: EdgePosition, cutout: Cutout) -> CGPoint {
        let halfWidth = cutout.width / 2
        let halfHeight = cutout.height / 2
        let center = CGPoint(x: cutout.centerX, y: cutout.centerY)
        switch edge {
        case .left:
            return CGPoint(x: center.x - halfWidth, y: center.y + halfHeight)
        case .right:
            return CGPoint(x: center.x + halfWidth, y: center.y + halfHeight)
        case .top:
            return CGPoint(x: center.x + halfWidth, y: center.y - halfHeight)
        case .bottom:
            return CGPoint(x: center.x + halfWidth, y: center.y + halfHeight)
        default:
            return center
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
    let shape: ShapeKind
    let curves: [CurvedEdge]
    let cutouts: [Cutout]
    let angleSegments: [AngleSegment]
    let boundarySegments: [BoundarySegment]
    let edgeTapped: (EdgeTapTarget) -> Void
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
            if cutout.isNotch || (cutout.kind != .circle && ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, size: metrics.pieceSize, shape: shape)) {
                continue
            }
            let displayCutout = rotatedCutout(cutout)
            let center = metrics.toCanvas(CGPoint(x: displayCutout.centerX, y: displayCutout.centerY))
            let width = max(displayCutout.width * metrics.scale, 1)
            let height = max(displayCutout.height * metrics.scale, 1)
            let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)

            if cutout.kind == .circle {
                let radius = width / 2
                let distanceToCenter = hypot(point.x - center.x, point.y - center.y)
                let distanceFromEdge: CGFloat = abs(distanceToCenter - radius)
                if distanceToCenter <= radius + threshold {
                    let distance = distanceFromEdge
                    if best == nil || distance < best!.2 {
                        best = (cutout.id, .top, distance)
                    }
                }
                continue
            }

            let candidates: [(EdgePosition, CGFloat, Bool)] = [
                (.top, abs(point.y - rect.minY), point.x >= rect.minX && point.x <= rect.maxX),
                (.bottom, abs(point.y - rect.maxY), point.x >= rect.minX && point.x <= rect.maxX),
                (.left, abs(point.x - rect.minX), point.y >= rect.minY && point.y <= rect.maxY),
                (.right, abs(point.x - rect.maxX), point.y >= rect.minY && point.y <= rect.maxY)
            ]

            for (edge, distance, inRange) in candidates where inRange && distance <= threshold {
                if !isInteriorNotchEdge(cutout: cutout, edge: edge, pieceSize: metrics.pieceSize) {
                    continue
                }
                if best == nil || distance < best!.2 {
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
            if distance <= threshold, best == nil || distance < best!.1 {
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
            if let edge = bestEdge(from: distances, curveMap: curveMap, point: point, rect: rect, threshold: threshold) {
                return EdgeTapTarget(edge: edge, segmentIndex: nil)
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

        for cutout in cutouts where (cutout.isNotch || ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, size: metrics.pieceSize, shape: shape)) && cutout.centerX >= 0 && cutout.centerY >= 0 {
            let displayCutout = rotatedCutout(cutout)
            let halfWidth = displayCutout.width / 2
            let halfHeight = displayCutout.height / 2
            let minX = displayCutout.centerX - halfWidth
            let maxX = displayCutout.centerX + halfWidth
            let minY = displayCutout.centerY - halfHeight
            let maxY = displayCutout.centerY + halfHeight

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
    return Cutout(kind: cutout.kind, width: cutout.height, height: cutout.width, centerX: cutout.centerY, centerY: cutout.centerX, isNotch: cutout.isNotch)
}

private func rotatedPointToRaw(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.y, y: point.x)
}

private func isEffectiveNotch(_ cutout: Cutout, piece: Piece, pieceSize: CGSize) -> Bool {
    if cutout.isNotch { return true }
    guard cutout.kind != .circle else { return false }
    return ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, size: pieceSize, shape: piece.shape)
}

private func isInteriorNotchEdge(cutout: Cutout, edge: EdgePosition, pieceSize: CGSize) -> Bool {
    let displayCutout = rotatedCutout(cutout)
    let halfWidth = displayCutout.width / 2
    let halfHeight = displayCutout.height / 2
    let minX = displayCutout.centerX - halfWidth
    let maxX = displayCutout.centerX + halfWidth
    let minY = displayCutout.centerY - halfHeight
    let maxY = displayCutout.centerY + halfHeight
    let edgeEpsilon: CGFloat = 0.01

    switch edge {
    case .left:
        return minX > edgeEpsilon
    case .right:
        return maxX < pieceSize.width - edgeEpsilon
    case .top:
        return minY > edgeEpsilon
    case .bottom:
        return maxY < pieceSize.height - edgeEpsilon
    default:
        return true
    }
}
