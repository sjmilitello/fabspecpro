import SwiftUI

struct AngleSegment {
    let id: UUID
    let start: CGPoint
    let end: CGPoint
}

struct BoundarySegment {
    let edge: EdgePosition
    let index: Int
    let startIndex: Int
    let endIndex: Int
    let start: CGPoint
    let end: CGPoint
}

private struct CurveSpanIndices {
    let start: Int
    let end: Int
}

private struct SpanInfo {
    let curve: CurvedEdge
    let edge: EdgePosition
    let spanStart: CGPoint
    let spanEnd: CGPoint
    let sMin: CGFloat
    let sMax: CGFloat
    let control: CGPoint
}

enum CutoutCornerPosition: Int {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

enum ShapePathBuilder {
    private static func spanIndices(for curve: CurvedEdge, boundarySegments: [BoundarySegment], pointCount: Int, bounds: CGRect, shape: ShapeKind) -> CurveSpanIndices? {
        if curve.usesEdgeProgress {
            let edgeSegments = boundarySegments.filter { $0.edge == curve.edge }
            guard !edgeSegments.isEmpty else { return nil }
            var endpoints: [(index: Int, progress: CGFloat)] = []
            endpoints.reserveCapacity(edgeSegments.count * 2)
            for segment in edgeSegments {
                endpoints.append((segment.startIndex, edgeProgress(for: segment.start, edge: curve.edge, shape: shape, bounds: bounds)))
                endpoints.append((segment.endIndex, edgeProgress(for: segment.end, edge: curve.edge, shape: shape, bounds: bounds)))
            }
            guard let startIndex = nearestEndpointIndex(progress: CGFloat(curve.startEdgeProgress), endpoints: endpoints),
                  let endIndex = nearestEndpointIndex(progress: CGFloat(curve.endEdgeProgress), endpoints: endpoints) else {
                return nil
            }
            return CurveSpanIndices(
                start: normalizedIndex(startIndex, count: pointCount),
                end: normalizedIndex(endIndex, count: pointCount)
            )
        }
        if curve.usesBoundaryEndpoints {
            guard let startSegment = boundarySegments.first(where: { $0.edge == curve.edge && $0.index == curve.startBoundarySegmentIndex }),
                  let endSegment = boundarySegments.first(where: { $0.edge == curve.edge && $0.index == curve.endBoundarySegmentIndex }) else {
                return nil
            }
            let startIndex = curve.startBoundaryIsEnd ? startSegment.endIndex : startSegment.startIndex
            let endIndex = curve.endBoundaryIsEnd ? endSegment.endIndex : endSegment.startIndex
            return CurveSpanIndices(
                start: normalizedIndex(startIndex, count: pointCount),
                end: normalizedIndex(endIndex, count: pointCount)
            )
        }
        if curve.startCornerIndex >= 0 && curve.endCornerIndex >= 0 {
            return CurveSpanIndices(
                start: normalizedIndex(curve.startCornerIndex, count: pointCount),
                end: normalizedIndex(curve.endCornerIndex, count: pointCount)
            )
        }
        return nil
    }

    private static func nearestEndpointIndex(progress: CGFloat, endpoints: [(index: Int, progress: CGFloat)]) -> Int? {
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

    static func edgeProgress(for point: CGPoint, edge: EdgePosition, shape: ShapeKind, bounds: CGRect) -> CGFloat {
        let width = max(bounds.width, 0.0001)
        let height = max(bounds.height, 0.0001)
        switch shape {
        case .rightTriangle:
            switch edge {
            case .legA:
                return clamp01((point.x - bounds.minX) / width)
            case .legB:
                return clamp01((point.y - bounds.minY) / height)
            case .hypotenuse:
                let a = CGPoint(x: bounds.maxX, y: bounds.minY)
                let b = CGPoint(x: bounds.minX, y: bounds.maxY)
                let dx = b.x - a.x
                let dy = b.y - a.y
                let denom = max(dx * dx + dy * dy, 0.0001)
                let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / denom
                return clamp01(t)
            default:
                return 0
            }
        default:
            switch edge {
            case .top, .bottom:
                return clamp01((point.x - bounds.minX) / width)
            case .left, .right:
                return clamp01((point.y - bounds.minY) / height)
            default:
                return 0
            }
        }
    }

    private static func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
    static func pieceSize(for piece: Piece) -> CGSize {
        let width = MeasurementParser.parseInches(piece.widthText) ?? 24
        let height = MeasurementParser.parseInches(piece.heightText) ?? 18

        switch piece.shape {
        case .circle:
            return CGSize(width: max(width, 1), height: max(height, 1))
        case .quarterCircle:
            return CGSize(width: max(width, 1), height: max(width, 1))
        case .rectangle, .rightTriangle:
            return CGSize(width: max(width, 1), height: max(height, 1))
        }
    }

    static func displaySize(for piece: Piece) -> CGSize {
        let rawSize = pieceSize(for: piece)
        return CGSize(width: rawSize.height, height: rawSize.width)
    }

    static func rawPoint(fromDisplay point: CGPoint) -> CGPoint {
        CGPoint(x: point.y, y: point.x)
    }

    static func displayPoint(fromRaw point: CGPoint) -> CGPoint {
        CGPoint(x: point.y, y: point.x)
    }

    /// Returns the corner indices adjacent to a given edge.
    /// For rectangles: corners are A=0 (top-left), B=1 (top-right), C=2 (bottom-right), D=3 (bottom-left)
    /// For triangles: corners are A=0 (top-left), B=1 (top-right), C=2 (bottom-left)
    static func cornersAdjacentToEdge(_ edge: EdgePosition, shape: ShapeKind) -> [Int] {
        switch shape {
        case .rectangle:
            switch edge {
            case .top: return [0, 1]      // A-B
            case .right: return [1, 2]    // B-C
            case .bottom: return [2, 3]   // C-D
            case .left: return [3, 0]     // D-A
            default: return []
            }
        case .rightTriangle:
            switch edge {
            case .legA: return [0, 1]        // A-B (top edge)
            case .hypotenuse: return [1, 2]  // B-C (diagonal)
            case .legB: return [2, 0]        // C-A (left edge)
            default: return []
            }
        default:
            return []
        }
    }

    /// Returns corner indices that are occupied by curved edges
    static func cornerIndicesOccupiedByCurves(curves: [CurvedEdge], shape: ShapeKind) -> Set<Int> {
        var occupied = Set<Int>()
        for curve in curves where curve.radius > 0 {
            let corners = cornersAdjacentToEdge(curve.edge, shape: shape)
            for corner in corners {
                occupied.insert(corner)
            }
        }
        return occupied
    }

    /// Returns corner indices (based on the current base-corner list) that lie on curved outer edges.
    static func cornerIndicesOnCurvedEdges(
        points: [CGPoint],
        shape: ShapeKind,
        curves: [CurvedEdge],
        baseBounds: CGRect? = nil,
        requireConvex: Bool = false
    ) -> Set<Int> {
        guard !points.isEmpty else { return [] }
        let curvedEdges = Set(curves.filter { $0.radius > 0 }.map { $0.edge })
        guard !curvedEdges.isEmpty else { return [] }

        // Use boundary segments to determine which edge each vertex belongs to.
        // This catches notch vertices that are indented from the edge line —
        // pointIsOnEdge misses them because they don't sit at the edge coordinate,
        // but they still belong to the curved edge and must be blocked.
        let bounds = baseBounds ?? polygonBounds(points)
        let hypotenuseBounds = baseBounds ?? bounds
        let segments = boundarySegments(for: points, shape: shape, bounds: bounds)

        // Build a set of vertex indices that touch any curved edge.
        // Each boundary segment connects two vertices and has an edge assignment.
        var occupied = Set<Int>()
        for segment in segments {
            if curvedEdges.contains(segment.edge) {
                occupied.insert(segment.startIndex)
                occupied.insert(segment.endIndex)
            }
        }

        // Also classify points that lie on the actual curved boundary. This catches
        // curve-only notches where vertices are off the straight-edge line and
        // boundarySegments can't assign an edge.
        let curveDistanceTolerance: CGFloat = 1.0
        for curve in curves where curve.radius > 0 {
            guard let geometry = fullEdgeGeometry(edge: curve.edge, bounds: bounds, hypotenuseBounds: hypotenuseBounds, shape: shape) else {
                continue
            }
            let mid = CGPoint(x: (geometry.start.x + geometry.end.x) / 2, y: (geometry.start.y + geometry.end.y) / 2)
            let direction: CGFloat = curve.isConcave ? -1.0 : 1.0
            let control = CGPoint(
                x: mid.x + geometry.normal.x * CGFloat(curve.radius) * 2 * direction,
                y: mid.y + geometry.normal.y * CGFloat(curve.radius) * 2 * direction
            )
            let spanRange: (min: CGFloat, max: CGFloat)?
            if curve.hasSpan && curve.usesEdgeProgress {
                let p0 = CGFloat(min(curve.startEdgeProgress, curve.endEdgeProgress))
                let p1 = CGFloat(max(curve.startEdgeProgress, curve.endEdgeProgress))
                spanRange = (min: p0, max: p1)
            } else if curve.hasSpan && curve.usesBoundaryEndpoints {
                if let startSegment = segments.first(where: { $0.edge == curve.edge && $0.index == curve.startBoundarySegmentIndex }),
                   let endSegment = segments.first(where: { $0.edge == curve.edge && $0.index == curve.endBoundarySegmentIndex }) {
                    let startPoint = curve.startBoundaryIsEnd ? startSegment.end : startSegment.start
                    let endPoint = curve.endBoundaryIsEnd ? endSegment.end : endSegment.start
                    let p0 = edgeProgress(for: startPoint, edge: curve.edge, shape: shape, bounds: hypotenuseBounds)
                    let p1 = edgeProgress(for: endPoint, edge: curve.edge, shape: shape, bounds: hypotenuseBounds)
                    spanRange = (min: min(p0, p1), max: max(p0, p1))
                } else {
                    spanRange = nil
                }
            } else if curve.hasSpan && curve.usesCornerIndices {
                if curve.startCornerIndex >= 0, curve.startCornerIndex < points.count,
                   curve.endCornerIndex >= 0, curve.endCornerIndex < points.count {
                    let p0 = edgeProgress(for: points[curve.startCornerIndex], edge: curve.edge, shape: shape, bounds: hypotenuseBounds)
                    let p1 = edgeProgress(for: points[curve.endCornerIndex], edge: curve.edge, shape: shape, bounds: hypotenuseBounds)
                    spanRange = (min: min(p0, p1), max: max(p0, p1))
                } else {
                    spanRange = nil
                }
            } else {
                spanRange = nil
            }
            for index in 0..<points.count {
                let point = points[index]
                // Use edgeProgress for the span range check (which uses min/max so
                // direction doesn't matter) but tForEdge for the Bézier evaluation
                // so the parametric direction matches fullEdgeGeometry's start→end.
                // edgeProgress always goes left→right / top→bottom, but the Bézier
                // direction is reversed for bottom (right→left) and left (bottom→top).
                let progressT = edgeProgress(for: point, edge: curve.edge, shape: shape, bounds: hypotenuseBounds)
                if let spanRange, (progressT < spanRange.min - 0.02 || progressT > spanRange.max + 0.02) {
                    continue
                }
                let bezierT = tForEdge(point: point, geometry: geometry, edge: curve.edge)
                let curvePoint = quadPoint(start: geometry.start, control: control, end: geometry.end, t: bezierT)
                if distance(point, curvePoint) <= curveDistanceTolerance {
                    occupied.insert(index)
                }
            }
        }

        // If requireConvex, exclude concave corners (notch indentation vertices).
        if requireConvex, points.count > 2 {
            let clockwise = polygonIsClockwise(points)
            occupied = occupied.filter { index in
                let prev = points[(index - 1 + points.count) % points.count]
                let curr = points[index]
                let next = points[(index + 1) % points.count]
                return !isConcaveCorner(prev: prev, curr: curr, next: next, clockwise: clockwise)
            }
        }

        return occupied
    }

    /// Returns corner indices that fall within the span of any curve on the same edge.
    /// Uses labeling boundary segments so the blocked indices match the UI labels.
    static func cornerIndicesBlockedByCurveSpans(
        points: [CGPoint],
        shape: ShapeKind,
        curves: [CurvedEdge],
        segments: [BoundarySegment],
        baseBounds: CGRect,
        requireConvex: Bool = false
    ) -> Set<Int> {
        guard !points.isEmpty else { return [] }
        let activeCurves = curves.filter { $0.radius > 0 }
        guard !activeCurves.isEmpty else { return [] }

        var blocked = Set<Int>()

        // Identify the indices that correspond to the curve span endpoints,
        // then block the contiguous edge-list range between them. This matches
        // how the curve spans are defined for drawing and avoids curve-distance
        // heuristics that miss span endpoints outside straight edges.
        let concave = requireConvex ? concaveCornerIndices(points: points) : []

        func orderedEdgeIndices(for edge: EdgePosition) -> [Int] {
            let edgeSegments = segments.filter { $0.edge == edge }.sorted { $0.index < $1.index }
            guard !edgeSegments.isEmpty else { return [] }
            var ordered: [Int] = []
            for seg in edgeSegments {
                if ordered.last != seg.startIndex { ordered.append(seg.startIndex) }
                if ordered.last != seg.endIndex { ordered.append(seg.endIndex) }
            }
            if requireConvex {
                ordered = ordered.filter { !concave.contains($0) }
            }
            return ordered
        }

        func indicesBetween(_ list: [Int], start: Int, end: Int) -> [Int] {
            guard let startPos = list.firstIndex(of: start),
                  let endPos = list.firstIndex(of: end) else { return [] }
            if startPos <= endPos {
                return Array(list[startPos...endPos])
            }
            return Array(list[endPos...startPos])
        }

        for curve in activeCurves {
            if curve.hasSpan {
                var startIndex: Int?
                var endIndex: Int?

                if curve.usesEdgeProgress {
                    // Use edge-progress to derive concrete endpoint indices on the labeling polygon.
                    let edgeSegments = segments.filter { $0.edge == curve.edge }
                    var endpoints: [(index: Int, progress: CGFloat)] = []
                    endpoints.reserveCapacity(edgeSegments.count * 2)
                    for segment in edgeSegments {
                        endpoints.append((segment.startIndex, edgeProgress(for: segment.start, edge: curve.edge, shape: shape, bounds: baseBounds)))
                        endpoints.append((segment.endIndex, edgeProgress(for: segment.end, edge: curve.edge, shape: shape, bounds: baseBounds)))
                    }
                    startIndex = nearestEndpointIndex(progress: CGFloat(curve.startEdgeProgress), endpoints: endpoints)
                    endIndex = nearestEndpointIndex(progress: CGFloat(curve.endEdgeProgress), endpoints: endpoints)
                } else if curve.usesBoundaryEndpoints {
                    if let startSegment = segments.first(where: { $0.edge == curve.edge && $0.index == curve.startBoundarySegmentIndex }),
                       let endSegment = segments.first(where: { $0.edge == curve.edge && $0.index == curve.endBoundarySegmentIndex }) {
                        startIndex = curve.startBoundaryIsEnd ? startSegment.endIndex : startSegment.startIndex
                        endIndex = curve.endBoundaryIsEnd ? endSegment.endIndex : endSegment.startIndex
                    }
                } else if curve.usesCornerIndices {
                    startIndex = curve.startCornerIndex
                    endIndex = curve.endCornerIndex
                }

                if let startIndex, let endIndex {
                    let edgeList = orderedEdgeIndices(for: curve.edge)
                    blocked.formUnion(indicesBetween(edgeList, start: startIndex, end: endIndex))
                    if requireConvex {
                        if !concave.contains(startIndex) { blocked.insert(startIndex) }
                        if !concave.contains(endIndex) { blocked.insert(endIndex) }
                    } else {
                        blocked.insert(startIndex)
                        blocked.insert(endIndex)
                    }
                }
                continue
            }
            if curve.usesCornerIndices {
                let edgeList = orderedEdgeIndices(for: curve.edge)
                blocked.formUnion(indicesBetween(edgeList, start: curve.startCornerIndex, end: curve.endCornerIndex))
                continue
            }
            // Full-edge curves block the whole edge list.
            let edgeList = orderedEdgeIndices(for: curve.edge)
            blocked.formUnion(edgeList)
        }

        return blocked
    }

    /// Returns only curves that are valid for rendering: radius > 0, valid
    /// span selection (start ≠ end), and no overlapping spans on the same edge.
    static func validCurves(for piece: Piece) -> [CurvedEdge] {
        // Use includeAngles: false because the curve-first pipeline applies curves
        // to the clean rectangle BEFORE angle cuts. Angle cut vertices shift polygon
        // indices and cause curve corner index validation to produce wrong results.
        let points = displayPolygonPoints(for: piece, includeAngles: false)
        let pointCount = points.count
        let curves = piece.curvedEdges.filter { curve in
            guard curve.radius > 0 else { return false }
            // Filter out segment curves with invalid edge progress
            if curve.usesEdgeProgress &&
               abs(curve.startEdgeProgress - curve.endEdgeProgress) < 0.001 {
                return false
            }
            // When edge progress is available, it's the canonical data — skip corner
            // index validation. Corner indices may be stale (from a different polygon
            // configuration) until normalizeSpanSelection re-resolves them.
            if curve.usesEdgeProgress {
                return true
            }
            // No edge progress — validate using corner indices only.
            // Filter out curves where start and end corner are the same
            if curve.usesCornerIndices && curve.startCornerIndex == curve.endCornerIndex {
                return false
            }
            // Filter out curves with out-of-range corner indices
            if curve.usesCornerIndices && pointCount > 0 {
                if curve.startCornerIndex < 0 || curve.startCornerIndex >= pointCount ||
                   curve.endCornerIndex < 0 || curve.endCornerIndex >= pointCount {
                    return false
                }
            }
            // Filter out curves that have corner indices set but edge progress
            // was cleared (e.g., by overlap detection or invalid span)
            if curve.usesCornerIndices && curve.startCornerIndex != curve.endCornerIndex
                && !curve.usesEdgeProgress && curve.hasSpan == false {
                // This is a "full-edge" curve by corner indices — validate that
                // both corners are actually on the same edge
                guard curve.startCornerIndex >= 0, curve.startCornerIndex < pointCount,
                      curve.endCornerIndex >= 0, curve.endCornerIndex < pointCount else {
                    return false
                }
                let start = points[curve.startCornerIndex]
                let end = points[curve.endCornerIndex]
                let bounds = polygonBounds(points)
                let hypBounds = piece.shape == .rightTriangle
                    ? CGRect(origin: .zero, size: displaySize(for: piece)) : bounds
                if edgeForSpanPoints(start: start, end: end, points: points,
                                     bounds: bounds, hypotenuseBounds: hypBounds,
                                     shape: piece.shape) == nil {
                    return false
                }
            }
            return true
        }
        guard curves.count > 1 else { return curves }

        // Helper: resolve edge progress for a curve, computing it from corner
        // indices if not already stored. This prevents newly-added curves (which
        // haven't had normalizeSpanSelection run yet) from being treated as
        // full-edge curves that knock out all other curves on the same edge.
        let bounds = polygonBounds(points)
        func resolvedProgress(_ curve: CurvedEdge) -> (p0: CGFloat, p1: CGFloat)? {
            if curve.usesEdgeProgress {
                let p0 = CGFloat(min(curve.startEdgeProgress, curve.endEdgeProgress))
                let p1 = CGFloat(max(curve.startEdgeProgress, curve.endEdgeProgress))
                return (p0, p1)
            }
            // Compute edge progress from corner indices on the fly
            if curve.usesCornerIndices &&
               curve.startCornerIndex != curve.endCornerIndex &&
               curve.startCornerIndex >= 0 && curve.startCornerIndex < pointCount &&
               curve.endCornerIndex >= 0 && curve.endCornerIndex < pointCount {
                let startPt = points[curve.startCornerIndex]
                let endPt = points[curve.endCornerIndex]
                let hypBounds = piece.shape == .rightTriangle
                    ? CGRect(origin: .zero, size: displaySize(for: piece)) : bounds
                let sp = edgeProgress(for: startPt, edge: curve.edge, shape: piece.shape, bounds: hypBounds)
                let ep = edgeProgress(for: endPt, edge: curve.edge, shape: piece.shape, bounds: hypBounds)
                let p0 = min(sp, ep)
                let p1 = max(sp, ep)
                if p1 - p0 > 0.001 { return (p0, p1) }
            }
            return nil // Truly a full-edge curve or unable to resolve
        }

        // Group by edge and check for overlaps
        let byEdge = Dictionary(grouping: curves, by: { $0.edge })
        var valid: [CurvedEdge] = []
        for (_, edgeCurves) in byEdge {
            if edgeCurves.count == 1 {
                valid.append(contentsOf: edgeCurves)
                continue
            }
            // Multiple curves on same edge — only allow non-overlapping segment curves
            for curve in edgeCurves {
                guard let cRange = resolvedProgress(curve) else {
                    // Full-edge curve conflicts with any other curve on same edge
                    continue
                }
                var overlaps = false
                for other in edgeCurves where other.id != curve.id {
                    guard let oRange = resolvedProgress(other) else {
                        overlaps = true
                        break
                    }
                    if min(cRange.p1, oRange.p1) - max(cRange.p0, oRange.p0) > 0.01 {
                        overlaps = true
                        break
                    }
                }
                if !overlaps {
                    valid.append(curve)
                }
            }
        }
        return valid
    }

    static func boundarySegments(for piece: Piece, includeAngles: Bool = true) -> [BoundarySegment] {
        let points = displayPolygonPoints(for: piece, includeAngles: includeAngles)
        guard points.count >= 2 else { return [] }
        let pMinX = points.map(\.x).min() ?? 0
        let pMinY = points.map(\.y).min() ?? 0
        let pMaxX = points.map(\.x).max() ?? 0
        let pMaxY = points.map(\.y).max() ?? 0
        let bounds = CGRect(x: pMinX, y: pMinY, width: pMaxX - pMinX, height: pMaxY - pMinY)
        return boundarySegments(for: points, shape: piece.shape, bounds: bounds)
    }

    /// Curve-aware boundary segments using the labeling polygon.
    /// Use this for curve picker span selection so indices match corner labels.
    static func boundarySegmentsForLabeling(for piece: Piece, includeAngles: Bool = true) -> [BoundarySegment] {
        let points = displayPolygonPointsForLabeling(for: piece, includeAngles: includeAngles)
        guard points.count >= 2 else { return [] }
        let pMinX = points.map(\.x).min() ?? 0
        let pMinY = points.map(\.y).min() ?? 0
        let pMaxX = points.map(\.x).max() ?? 0
        let pMaxY = points.map(\.y).max() ?? 0
        let bounds = CGRect(x: pMinX, y: pMinY, width: pMaxX - pMinX, height: pMaxY - pMinY)
        return boundarySegments(for: points, shape: piece.shape, bounds: bounds)
    }

    private static func boundarySegments(for points: [CGPoint], shape: ShapeKind, bounds: CGRect, hypotenuseBounds: CGRect? = nil) -> [BoundarySegment] {
        guard points.count >= 2 else { return [] }
        let eps: CGFloat = 0.001
        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY
        // For right triangles with notches, use the base triangle bounds for hypotenuse detection
        let hypBounds = hypotenuseBounds ?? bounds

        var rawSegments: [(EdgePosition, Int, Int, CGPoint, CGPoint)] = []
        for i in 0..<points.count {
            let a = points[i]
            let nextIndex = (i + 1) % points.count
            let b = points[nextIndex]
            let dx = b.x - a.x
            let dy = b.y - a.y
            if shape == .rightTriangle {
                if abs(dy) < eps, abs(a.y - hypBounds.minY) < eps {
                    rawSegments.append((.legA, i, nextIndex, a, b))
                } else if abs(dx) < eps, abs(a.x - hypBounds.minX) < eps {
                    rawSegments.append((.legB, i, nextIndex, a, b))
                } else if segmentIsOnHypotenuse(start: a, end: b, bounds: hypBounds) {
                    rawSegments.append((.hypotenuse, i, nextIndex, a, b))
                }
            } else {
                if abs(dy) < eps {
                    if abs(a.y - minY) < eps {
                        rawSegments.append((.top, i, nextIndex, a, b))
                    } else if abs(a.y - maxY) < eps {
                        rawSegments.append((.bottom, i, nextIndex, a, b))
                    }
                } else if abs(dx) < eps {
                    if abs(a.x - minX) < eps {
                        rawSegments.append((.left, i, nextIndex, a, b))
                    } else if abs(a.x - maxX) < eps {
                        rawSegments.append((.right, i, nextIndex, a, b))
                    }
                }
            }
        }

        var segments: [BoundarySegment] = []
        let edges: [EdgePosition] = shape == .rightTriangle ? [.legA, .hypotenuse, .legB] : [.top, .right, .bottom, .left]
        for edge in edges {
            let edgeSegments = rawSegments.filter { $0.0 == edge }.sorted { lhs, rhs in
                switch edge {
                case .top, .bottom, .legA:
                    return min(lhs.3.x, lhs.4.x) < min(rhs.3.x, rhs.4.x)
                case .left, .right, .legB:
                    return min(lhs.3.y, lhs.4.y) < min(rhs.3.y, rhs.4.y)
                case .hypotenuse:
                    let midL = CGPoint(x: (lhs.3.x + lhs.4.x) / 2, y: (lhs.3.y + lhs.4.y) / 2)
                    let midR = CGPoint(x: (rhs.3.x + rhs.4.x) / 2, y: (rhs.3.y + rhs.4.y) / 2)
                    let tL = ((maxX - midL.x) / max(maxX - minX, 0.0001))
                    let tR = ((maxX - midR.x) / max(maxX - minX, 0.0001))
                    return tL < tR
                }
            }
            for (index, segment) in edgeSegments.enumerated() {
                segments.append(BoundarySegment(edge: segment.0, index: index, startIndex: segment.1, endIndex: segment.2, start: segment.3, end: segment.4))
            }
        }
        return segments
    }

    static func path(for piece: Piece) -> Path {
        let rawSize = pieceSize(for: piece)
        let allCornerRadii = pieceCornerRadii(for: piece)
        let activeCurves = validCurves(for: piece)
        // Use curve-aware notch candidates for rendering: cutouts interior to a curved
        // boundary are not treated as notches (they're drawn as interior cutouts instead).
        let notches = notchCandidatesCurveAware(for: piece, size: rawSize)
        let pieceAngleCuts = boundaryAngleCuts(for: piece)

        // Labeling polygon includes curve-aware notches (matches the UI's index space).
        // All index lookups in the curve-first pipeline use this polygon so indices
        // match what the UI picker assigned.
        let labelingCorners = displayPolygonPointsForLabeling(for: piece, includeAngles: false)
        let baseTriangleCorners: [CGPoint]
        if piece.shape == .rightTriangle {
            let base = rightTrianglePoints(size: rawSize)
            baseTriangleCorners = reorderCornersClockwise(base.map { displayPoint(fromRaw: $0) })
        } else {
            baseTriangleCorners = []
        }
        // Filter corner radii on curved edges using boundary segment detection.
        // This catches notch vertices on curved edges that pointIsOnEdge misses
        // (notch vertices are indented from the edge line but still belong to it).
        let curvedCornerIndices = cornerIndicesOnCurvedEdges(
            points: labelingCorners, shape: piece.shape, curves: activeCurves, requireConvex: false)
        let curvedCornerIndicesForAngles = cornerIndicesOnCurvedEdges(
            points: labelingCorners, shape: piece.shape, curves: activeCurves, requireConvex: true)
        let isClockwise = polygonIsClockwise(labelingCorners)
        let cornerRadii = allCornerRadii.filter { radius in
            guard radius.cornerIndex >= 0, radius.cornerIndex < labelingCorners.count else { return false }
            return !curvedCornerIndices.contains(radius.cornerIndex)
        }

        // Curve-aware notch candidates for the curve-first pipeline subtraction step.
        // Uses curve-aware detection so notches that extend past the straight edge
        // but still touch the curved boundary are included in subtraction.
        // This is safe because the curve-first pipeline builds curves on the clean
        // base shape first (steps 1-2), so the notch list doesn't affect curve computation.
        let stableNotches = notchCandidatesCurveAware(for: piece, size: rawSize)

        if piece.shape == .rectangle, (!notches.isEmpty || !stableNotches.isEmpty || !piece.angleCuts.isEmpty) {
            // When curves are active, use curve-first pipeline:
            // 1. Build base shape with angle cuts (no notches)
            // 2. Apply curves to the simple shape (full unfragmented edges)
            // 3. Subtract notches from the curved path
            // This ensures addEdge receives full edge endpoints so edge progress
            // interpolates correctly, and avoids cross-edge instability from
            // curvedBooleanDifference changing the polygon when curves are added.
            if !activeCurves.isEmpty {
                // Classify angle cuts: base-corner cuts (safe for Step 1) vs
                // notch-interior cuts (must be handled via chamfered clips in Step 4).
                // baseCorners uses notchCandidates (same polygon that boundaryAngleCuts validated against).
                let cleanRectDisplay = reorderCornersClockwise(rectanglePoints(size: rawSize).map { displayPoint(fromRaw: $0) })
                // Classify angle cuts using labelingCorners (curve-aware polygon).
                // anchorCornerIndex is set by the UI picker which uses labeling indices.
                // Using baseCorners (non-curve-aware) causes index space divergence when
                // full-side curves reclassify notches as interior, shrinking the labeling
                // polygon while baseCorners stays the same size.
                var baseCornerCuts: [AngleCut] = []
                var notchInteriorCuts: [AngleCut] = []
                for cut in pieceAngleCuts {
                    guard cut.anchorCornerIndex >= 0 else { continue }
                    // If index exceeds labeling polygon (notch reclassified by curves),
                    // treat as notch-interior cut.
                    guard cut.anchorCornerIndex < labelingCorners.count else {
                        notchInteriorCuts.append(cut)
                        continue
                    }
                    let vertex = labelingCorners[cut.anchorCornerIndex]
                    if cleanRectDisplay.contains(where: { distance($0, vertex) < 0.5 }) {
                        baseCornerCuts.append(cut)
                    } else {
                        notchInteriorCuts.append(cut)
                    }
                }

                // Classify corner radii: base-corner radii (Step 3) vs notch-interior radii (after Step 4).
                // Corner radii indices come from the labeling polygon (curve-aware notches).
                // Base-corner radii target the clean rectangle corners; notch-interior radii
                // target notch corners that only exist after Step 4 subtraction.
                var baseCornerRadii: [CornerRadius] = []
                var notchInteriorRadii: [CornerRadius] = []
                for radius in cornerRadii {
                    guard radius.cornerIndex >= 0, radius.cornerIndex < labelingCorners.count else { continue }
                    let vertex = labelingCorners[radius.cornerIndex]
                    if cleanRectDisplay.contains(where: { distance($0, vertex) < 0.5 }) {
                        baseCornerRadii.append(radius)
                    } else {
                        notchInteriorRadii.append(radius)
                    }
                }

                // Exclude angle cuts on curved corners — they distort the curve.
                // Uses curvedCornerIndices (boundary-segment-based) which correctly
                // catches notch vertices on curved edges that pointIsOnEdge misses.
                // This applies to BOTH base-corner cuts (Step 1) and notch-interior
                // cuts (Step 4) — chamfering a notch clip at a curved corner also
                // distorts the curve when the clip is subtracted.
                let notchInteriorAngleIndices = Set(notchInteriorCuts.map { $0.anchorCornerIndex })
                let curvedCornerIndicesForAngleCuts = curvedCornerIndicesForAngles.subtracting(notchInteriorAngleIndices)
                let safeBaseCornerCuts = baseCornerCuts.filter { cut in
                    guard cut.anchorCornerIndex >= 0, cut.anchorCornerIndex < labelingCorners.count else { return false }
                    return !curvedCornerIndicesForAngleCuts.contains(cut.anchorCornerIndex)
                }
                let safeNotchInteriorCuts = notchInteriorCuts.filter { cut in
                    let idx = cut.anchorCornerIndex
                    guard idx >= 0, idx < labelingCorners.count else { return false }
                    let prev = labelingCorners[(idx - 1 + labelingCorners.count) % labelingCorners.count]
                    let curr = labelingCorners[idx]
                    let next = labelingCorners[(idx + 1) % labelingCorners.count]
                    let isConcave = isConcaveCorner(prev: prev, curr: curr, next: next, clockwise: isClockwise)
                    if isConcave { return true }
                    return !curvedCornerIndicesForAngleCuts.contains(idx)
                }
                // Step 1-2: Always apply curves to the clean rectangle first using
                // curvedRectanglePath. This function handles both full-side and segment
                // curves correctly via addEdge with exact edge progress values.
                // Then subtract base-corner angle cuts as boolean clip triangles.
                // This avoids curvedPolygonPath which loses segment curve span precision
                // because the base polygon (no notches) lacks the span boundary vertices
                // that spanIndices needs — causing curves to flatten or distort.
                let dispSize = displaySize(for: piece)
                var curvedPath = curvedRectanglePath(width: dispSize.width, height: dispSize.height, curves: activeCurves)

                // Subtract base-corner angle cuts as triangular clips from the curved path.
                // Use cleanRectDisplay for clip geometry so edge lengths span the full
                // rectangle edge (not just to the nearest notch vertex in labelingCorners).
                if !safeBaseCornerCuts.isEmpty {
                    let rectCount = cleanRectDisplay.count
                    for cut in safeBaseCornerCuts {
                        guard cut.anchorCornerIndex >= 0, cut.anchorCornerIndex < labelingCorners.count else { continue }
                        let labelVertex = labelingCorners[cut.anchorCornerIndex]
                        // Map labeling polygon index to the nearest clean rectangle corner.
                        guard let rectIdx = cleanRectDisplay.enumerated().min(by: {
                            distance($0.element, labelVertex) < distance($1.element, labelVertex)
                        })?.offset, distance(cleanRectDisplay[rectIdx], labelVertex) < 0.5 else { continue }
                        // Build clip triangle using clean rectangle edges for full edge lengths.
                        let corner = cleanRectDisplay[rectIdx]
                        let prev = cleanRectDisplay[(rectIdx - 1 + rectCount) % rectCount]
                        let next = cleanRectDisplay[(rectIdx + 1) % rectCount]
                        let alongEdge1 = abs(cut.anchorOffset)
                        let alongEdge2 = abs(cut.secondaryOffset)
                        let toNext = unitVector(from: corner, to: next)
                        let toPrev = unitVector(from: corner, to: prev)
                        let lenNext = distance(corner, next)
                        let lenPrev = distance(corner, prev)
                        guard alongEdge1 <= lenNext, alongEdge2 <= lenPrev else { continue }
                        let p1 = CGPoint(x: corner.x + toNext.x * alongEdge1, y: corner.y + toNext.y * alongEdge1)
                        let p2 = CGPoint(x: corner.x + toPrev.x * alongEdge2, y: corner.y + toPrev.y * alongEdge2)
                        let clipPath = polygonPath([corner, p1, p2])
                        curvedPath = curvedPath.subtracting(clipPath)
                    }
                }

                // Step 3: (Base-corner radii are currently only possible on non-curved corners.
                // Since all 4 base rectangle corners have curves in typical usage, this is a no-op.
                // If needed in the future, base-corner radii can be handled here.)

                // Step 4: Subtract notches (with chamfered angle cuts and rounded corner radii).
                // Notch clip polygons are built with rounded corners using roundedPolygonPath —
                // the same proven function used for interior cutout corner radii.
                // Chamfered corners for notch-interior angle cuts are also applied to the clips.
                if !stableNotches.isEmpty {
                    var clipPolygons = notchClipPolygons(notches: stableNotches, size: rawSize, shape: .rectangle)

                    // Chamfer clip polygon corners for notch-interior angle cuts
                    if !safeNotchInteriorCuts.isEmpty {
                        let needsCurvedChamfer = !activeCurves.isEmpty && stableNotches.contains { cutout in
                            cutoutOverlapsPiece(cutout: cutout, size: rawSize, shape: piece.shape, curves: activeCurves)
                                && !cutoutOverlapsPiece(cutout: cutout, size: rawSize, shape: piece.shape, curves: [])
                        }
                        let notchedForChamfer = angledRectanglePoints(
                            size: rawSize,
                            notches: stableNotches,
                            angleCuts: [],
                            curves: needsCurvedChamfer ? activeCurves : [],
                            forLabeling: needsCurvedChamfer
                        )
                        let notchedChamferDisplay = reorderCornersClockwise(notchedForChamfer.points.map { displayPoint(fromRaw: $0) })

                        for cut in safeNotchInteriorCuts {
                            // Resolve anchor position from labelingCorners (curve-aware polygon)
                            // since anchorCornerIndex was assigned from the labeling polygon.
                            // Using baseCorners (non-curve-aware) causes index mismatch when
                            // full-side curves reclassify notches, changing vertex count/order.
                            guard cut.anchorCornerIndex >= 0, cut.anchorCornerIndex < labelingCorners.count else { continue }
                            let anchorPosition = labelingCorners[cut.anchorCornerIndex]

                            guard let chamferIdx = notchedChamferDisplay.enumerated().min(by: {
                                distance($0.element, anchorPosition) < distance($1.element, anchorPosition)
                            })?.offset, distance(notchedChamferDisplay[chamferIdx], anchorPosition) < 1.0 else { continue }

                            let anchor = notchedChamferDisplay[chamferIdx]
                            let chamferCount = notchedChamferDisplay.count
                            let outlinePrev = notchedChamferDisplay[(chamferIdx - 1 + chamferCount) % chamferCount]
                            let outlineNext = notchedChamferDisplay[(chamferIdx + 1) % chamferCount]

                            let alongEdge1 = abs(cut.anchorOffset)
                            let alongEdge2 = abs(cut.secondaryOffset)
                            let toOutlineNext = unitVector(from: anchor, to: outlineNext)
                            let toOutlinePrev = unitVector(from: anchor, to: outlinePrev)
                            let lenNext = distance(anchor, outlineNext)
                            let lenPrev = distance(anchor, outlinePrev)
                            guard alongEdge1 <= lenNext, alongEdge2 <= lenPrev else { continue }

                            let p1 = CGPoint(x: anchor.x + toOutlineNext.x * alongEdge1, y: anchor.y + toOutlineNext.y * alongEdge1)
                            let p2 = CGPoint(x: anchor.x + toOutlinePrev.x * alongEdge2, y: anchor.y + toOutlinePrev.y * alongEdge2)

                            var bestClipIndex: Int?
                            var bestCornerIndex: Int?
                            var bestDistance = CGFloat.greatestFiniteMagnitude

                            for clipIdx in clipPolygons.indices {
                                let clipDisplay = clipPolygons[clipIdx].map { displayPoint(fromRaw: $0) }
                                guard let cornerIdx = clipDisplay.enumerated().min(by: {
                                    distance($0.element, anchor) < distance($1.element, anchor)
                                })?.offset else { continue }
                                let cornerDistance = distance(clipDisplay[cornerIdx], anchor)
                                if cornerDistance < bestDistance {
                                    bestDistance = cornerDistance
                                    bestClipIndex = clipIdx
                                    bestCornerIndex = cornerIdx
                                }
                            }

                            if let clipIdx = bestClipIndex,
                               let cornerIdx = bestCornerIndex,
                               bestDistance < 1.0 {
                                let clipDisplay = clipPolygons[clipIdx].map { displayPoint(fromRaw: $0) }
                                let clipCount = clipDisplay.count
                                let prevClip = clipDisplay[(cornerIdx - 1 + clipCount) % clipCount]
                                let nextClip = clipDisplay[(cornerIdx + 1) % clipCount]

                                let p1OnPrevEdge = abs(distance(prevClip, p1) + distance(p1, anchor) - distance(prevClip, anchor))
                                let p1OnNextEdge = abs(distance(anchor, p1) + distance(p1, nextClip) - distance(anchor, nextClip))

                                var newClip: [CGPoint] = []
                                for (i, pt) in clipDisplay.enumerated() {
                                    if i == cornerIdx {
                                        if p1OnPrevEdge < p1OnNextEdge {
                                            newClip.append(p1)
                                            newClip.append(p2)
                                        } else {
                                            newClip.append(p2)
                                            newClip.append(p1)
                                        }
                                    } else {
                                        newClip.append(pt)
                                    }
                                }
                                clipPolygons[clipIdx] = newClip.map { rawPoint(fromDisplay: $0) }
                            }
                        }
                    }

                    // Build clip paths — use roundedPolygonPath for clips with corner radii
                    // (same approach as interior cutout rendering in cutoutPath)
                    if !clipPolygons.isEmpty {
                        var clipPath = Path()
                        for clip in clipPolygons {
                            let displayClip = reorderCornersClockwise(clip.map { displayPoint(fromRaw: $0) })
                            guard displayClip.count >= 3 else { continue }

                            // Map notch-interior corner radii to this clip's corners
                            var localRadii: [CornerRadius] = []
                            if !notchInteriorRadii.isEmpty {
                                for radius in notchInteriorRadii {
                                    guard radius.cornerIndex >= 0, radius.cornerIndex < labelingCorners.count else { continue }
                                    let radiusVertex = labelingCorners[radius.cornerIndex]
                                    // Find matching corner in this clip polygon
                                    if let matchIdx = displayClip.enumerated().min(by: {
                                        distance($0.element, radiusVertex) < distance($1.element, radiusVertex)
                                    })?.offset, distance(displayClip[matchIdx], radiusVertex) < 1.0 {
                                        localRadii.append(CornerRadius(cornerIndex: matchIdx, radius: radius.radius, isInside: radius.isInside))
                                    }
                                }
                            }

                            if !localRadii.isEmpty {
                                // Build rounded clip using roundedPolygonPath (proven approach)
                                let roundedClip = roundedPolygonPath(points: displayClip, cornerRadii: localRadii)
                                clipPath.addPath(roundedClip)
                            } else {
                                // Standard straight-edged clip
                                clipPath.move(to: displayClip[0])
                                for pt in displayClip.dropFirst() { clipPath.addLine(to: pt) }
                                clipPath.closeSubpath()
                            }
                        }
                        let subtracted = curvedPath.subtracting(clipPath)
                        let subBounds = subtracted.boundingRect
                        if subBounds.width >= 0.01 || subBounds.height >= 0.01 {
                            return subtracted
                        }
                        // Fallback to old pipeline
                        let fallbackResult = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: pieceAngleCuts, curves: activeCurves)
                        let fallbackPoints = fallbackResult.points.map { displayPoint(fromRaw: $0) }
                        let fallbackMapped = mapCurvesToDisplayPointsUsingBaseCorners(
                            curves: activeCurves,
                            displayPoints: fallbackPoints,
                            baseCorners: baseTriangleCorners
                        )
                        return curvedPolygonPath(points: fallbackPoints, shape: .rectangle, curves: fallbackMapped, baseBounds: nil)
                    }
                }

                // Subtract interior cutouts using the curve-first path to avoid curve distortion.
                let interiorCutouts = interiorCutoutsCurveAware(for: piece)
                if !interiorCutouts.isEmpty {
                    let cutoutRanges = cutoutCornerRanges(for: piece)
                    let displaySize = CGSize(width: rawSize.height, height: rawSize.width)
                    func displayCutoutForPath(_ cutout: Cutout) -> Cutout {
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
                    func localAngleCuts(for cutout: Cutout) -> [AngleCut] {
                        guard let range = cutoutRanges.first(where: { $0.cutout.id == cutout.id })?.range else { return [] }
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
                    func localCornerRadii(for cutout: Cutout) -> [CornerRadius] {
                        guard let range = cutoutRanges.first(where: { $0.cutout.id == cutout.id })?.range else { return [] }
                        return piece.cornerRadii.compactMap { radius in
                            guard range.contains(radius.cornerIndex) else { return nil }
                            let local = CornerRadius(
                                cornerIndex: radius.cornerIndex - range.lowerBound,
                                radius: radius.radius,
                                isInside: radius.isInside
                            )
                            local.id = radius.id
                            return local
                        }
                    }

                    var cutoutClipPath = Path()
                    for cutout in interiorCutouts {
                        let displayCutout = displayCutoutForPath(cutout)
                        let angleCuts = localAngleCuts(for: cutout)
                        let cornerRadii = localCornerRadii(for: cutout)
                        let cutoutPath = cutoutPath(
                            displayCutout,
                            angleCuts: angleCuts,
                            cornerRadii: cornerRadii,
                            size: displaySize,
                            shape: piece.shape
                        )
                        cutoutClipPath.addPath(cutoutPath)
                    }
                    let subtracted = curvedPath.subtracting(cutoutClipPath)
                    let subBounds = subtracted.boundingRect
                    if subBounds.width >= 0.01 || subBounds.height >= 0.01 {
                        curvedPath = subtracted
                    }
                }
                return curvedPath
            }

            // No curves: use existing polygon-based pipeline
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: pieceAngleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            if !cornerRadii.isEmpty {
                let ordered = reorderCornersClockwise(displayPoints)
                let baseCorners = displayPolygonPointsForLabeling(for: piece, includeAngles: false)
                return roundedPolygonPath(points: ordered, cornerRadii: cornerRadii, baseCorners: baseCorners)
            }
            return polygonPath(displayPoints)
        }
        if piece.shape == .rightTriangle, (!notches.isEmpty || !stableNotches.isEmpty || !piece.angleCuts.isEmpty) {
            let dispSize = displaySize(for: piece)
            let baseBounds = CGRect(origin: .zero, size: dispSize)

            // Curve-first pipeline for right triangles (same approach as rectangle)
            if !activeCurves.isEmpty {
                // Classify angle cuts for right triangle (base has 3 corners).
                // Use labelingCorners for vertex lookup (same rationale as rectangle pipeline).
                let cleanTriDisplay = reorderCornersClockwise(rightTrianglePoints(size: rawSize).map { displayPoint(fromRaw: $0) })
                var triBaseCornerCuts: [AngleCut] = []
                var triNotchInteriorCuts: [AngleCut] = []
                for cut in pieceAngleCuts {
                    guard cut.anchorCornerIndex >= 0 else { continue }
                    guard cut.anchorCornerIndex < labelingCorners.count else {
                        triNotchInteriorCuts.append(cut)
                        continue
                    }
                    let vertex = labelingCorners[cut.anchorCornerIndex]
                    if cleanTriDisplay.contains(where: { distance($0, vertex) < 0.5 }) {
                        triBaseCornerCuts.append(cut)
                    } else {
                        triNotchInteriorCuts.append(cut)
                    }
                }

                // Classify corner radii for right triangle (same approach as rectangle)
                var triBaseCornerRadii: [CornerRadius] = []
                var triNotchInteriorRadii: [CornerRadius] = []
                for radius in cornerRadii {
                    guard radius.cornerIndex >= 0, radius.cornerIndex < labelingCorners.count else { continue }
                    let vertex = labelingCorners[radius.cornerIndex]
                    if cleanTriDisplay.contains(where: { distance($0, vertex) < 0.5 }) {
                        triBaseCornerRadii.append(radius)
                    } else {
                        triNotchInteriorRadii.append(radius)
                    }
                }

                // Step 1: Base shape with base-corner angle cuts only (no notches).
                // Exclude angle cuts on curved corners — they distort the curve.
                // Uses curvedCornerIndices (boundary-segment-based) which correctly
                // catches notch vertices on curved edges that pointIsOnEdge misses.
                let safeTriBaseCornerCuts = triBaseCornerCuts.filter { cut in
                    guard cut.anchorCornerIndex >= 0, cut.anchorCornerIndex < labelingCorners.count else { return false }
                    return !curvedCornerIndices.contains(cut.anchorCornerIndex)
                }
                let safeTriNotchInteriorCuts = triNotchInteriorCuts.filter { cut in
                    let idx = cut.anchorCornerIndex
                    guard idx >= 0, idx < labelingCorners.count else { return false }
                    let prev = labelingCorners[(idx - 1 + labelingCorners.count) % labelingCorners.count]
                    let curr = labelingCorners[idx]
                    let next = labelingCorners[(idx + 1) % labelingCorners.count]
                    let isConcave = isConcaveCorner(prev: prev, curr: curr, next: next, clockwise: isClockwise)
                    if isConcave { return true }
                    return !curvedCornerIndices.contains(idx)
                }
                // Step 1-2: Apply curves to the clean triangle first, then subtract
                // base-corner angle cuts as boolean clip triangles.
                // Same approach as rectangle pipeline — avoids curvedPolygonPath which
                // loses segment curve span precision on the simplified polygon.
                let triDisplayPoints = reorderCornersClockwise(rightTrianglePoints(size: rawSize).map { displayPoint(fromRaw: $0) })
                let mappedCurves = mapCurvesToRawDisplayPoints(curves: activeCurves, displayPoints: triDisplayPoints)
                var curvedPath = curvedPolygonPath(points: triDisplayPoints, shape: .rightTriangle, curves: mappedCurves, baseBounds: baseBounds)

                // Subtract base-corner angle cuts as triangular clips from the curved path.
                if !safeTriBaseCornerCuts.isEmpty {
                    let cleanTriDisplay = reorderCornersClockwise(rightTrianglePoints(size: rawSize).map { displayPoint(fromRaw: $0) })
                    let triCount = cleanTriDisplay.count
                    for cut in safeTriBaseCornerCuts {
                        guard cut.anchorCornerIndex >= 0, cut.anchorCornerIndex < labelingCorners.count else { continue }
                        let labelVertex = labelingCorners[cut.anchorCornerIndex]
                        guard let triIdx = cleanTriDisplay.enumerated().min(by: {
                            distance($0.element, labelVertex) < distance($1.element, labelVertex)
                        })?.offset, distance(cleanTriDisplay[triIdx], labelVertex) < 0.5 else { continue }
                        let corner = cleanTriDisplay[triIdx]
                        let prev = cleanTriDisplay[(triIdx - 1 + triCount) % triCount]
                        let next = cleanTriDisplay[(triIdx + 1) % triCount]
                        let alongEdge1 = abs(cut.anchorOffset)
                        let alongEdge2 = abs(cut.secondaryOffset)
                        let toNext = unitVector(from: corner, to: next)
                        let toPrev = unitVector(from: corner, to: prev)
                        let lenNext = distance(corner, next)
                        let lenPrev = distance(corner, prev)
                        guard alongEdge1 <= lenNext, alongEdge2 <= lenPrev else { continue }
                        let p1 = CGPoint(x: corner.x + toNext.x * alongEdge1, y: corner.y + toNext.y * alongEdge1)
                        let p2 = CGPoint(x: corner.x + toPrev.x * alongEdge2, y: corner.y + toPrev.y * alongEdge2)
                        let clipPath = polygonPath([corner, p1, p2])
                        curvedPath = curvedPath.subtracting(clipPath)
                    }
                }

                // Step 3: (Base-corner radii skipped — same note as rectangle pipeline)

                // Step 4: Subtract notches (with chamfered angle cuts and rounded corner radii)
                if !stableNotches.isEmpty {
                    var clipPolygons = notchClipPolygons(notches: stableNotches, size: rawSize, shape: .rightTriangle)

                    if !safeTriNotchInteriorCuts.isEmpty {
                        let notchedForChamfer = angledRightTrianglePoints(size: rawSize, notches: stableNotches, angleCuts: [])
                        let notchedChamferDisplay = reorderCornersClockwise(notchedForChamfer.points.map { displayPoint(fromRaw: $0) })

                        for cut in safeTriNotchInteriorCuts {
                            // Resolve anchor position from labelingCorners (curve-aware polygon)
                            // since anchorCornerIndex was assigned from the labeling polygon.
                            // Using baseCorners (non-curve-aware) causes index mismatch when
                            // full-side curves reclassify notches, changing vertex count/order.
                            guard cut.anchorCornerIndex >= 0, cut.anchorCornerIndex < labelingCorners.count else { continue }
                            let anchorPosition = labelingCorners[cut.anchorCornerIndex]

                            guard let chamferIdx = notchedChamferDisplay.enumerated().min(by: {
                                distance($0.element, anchorPosition) < distance($1.element, anchorPosition)
                            })?.offset, distance(notchedChamferDisplay[chamferIdx], anchorPosition) < 1.0 else { continue }

                            let anchor = notchedChamferDisplay[chamferIdx]
                            let chamferCount = notchedChamferDisplay.count
                            let outlinePrev = notchedChamferDisplay[(chamferIdx - 1 + chamferCount) % chamferCount]
                            let outlineNext = notchedChamferDisplay[(chamferIdx + 1) % chamferCount]

                            let alongEdge1 = abs(cut.anchorOffset)
                            let alongEdge2 = abs(cut.secondaryOffset)
                            let toOutlineNext = unitVector(from: anchor, to: outlineNext)
                            let toOutlinePrev = unitVector(from: anchor, to: outlinePrev)
                            let lenNext = distance(anchor, outlineNext)
                            let lenPrev = distance(anchor, outlinePrev)
                            guard alongEdge1 <= lenNext, alongEdge2 <= lenPrev else { continue }

                            let p1 = CGPoint(x: anchor.x + toOutlineNext.x * alongEdge1, y: anchor.y + toOutlineNext.y * alongEdge1)
                            let p2 = CGPoint(x: anchor.x + toOutlinePrev.x * alongEdge2, y: anchor.y + toOutlinePrev.y * alongEdge2)

                            for clipIdx in clipPolygons.indices {
                                let clipDisplay = clipPolygons[clipIdx].map { displayPoint(fromRaw: $0) }
                                guard let cornerIdx = clipDisplay.enumerated().min(by: {
                                    distance($0.element, anchor) < distance($1.element, anchor)
                                })?.offset, distance(clipDisplay[cornerIdx], anchor) < 1.0 else { continue }

                                let clipCount = clipDisplay.count
                                let prevClip = clipDisplay[(cornerIdx - 1 + clipCount) % clipCount]
                                let nextClip = clipDisplay[(cornerIdx + 1) % clipCount]

                                let p1OnPrevEdge = abs(distance(prevClip, p1) + distance(p1, anchor) - distance(prevClip, anchor))
                                let p1OnNextEdge = abs(distance(anchor, p1) + distance(p1, nextClip) - distance(anchor, nextClip))

                                var newClip: [CGPoint] = []
                                for (i, pt) in clipDisplay.enumerated() {
                                    if i == cornerIdx {
                                        if p1OnPrevEdge < p1OnNextEdge {
                                            newClip.append(p1)
                                            newClip.append(p2)
                                        } else {
                                            newClip.append(p2)
                                            newClip.append(p1)
                                        }
                                    } else {
                                        newClip.append(pt)
                                    }
                                }
                                clipPolygons[clipIdx] = newClip.map { rawPoint(fromDisplay: $0) }
                                break
                            }
                        }
                    }

                    // Build clip paths — use roundedPolygonPath for clips with corner radii
                    if !clipPolygons.isEmpty {
                        var clipPath = Path()
                        for clip in clipPolygons {
                            let displayClip = reorderCornersClockwise(clip.map { displayPoint(fromRaw: $0) })
                            guard displayClip.count >= 3 else { continue }

                            var localRadii: [CornerRadius] = []
                            if !triNotchInteriorRadii.isEmpty {
                                for radius in triNotchInteriorRadii {
                                    guard radius.cornerIndex >= 0, radius.cornerIndex < labelingCorners.count else { continue }
                                    let radiusVertex = labelingCorners[radius.cornerIndex]
                                    if let matchIdx = displayClip.enumerated().min(by: {
                                        distance($0.element, radiusVertex) < distance($1.element, radiusVertex)
                                    })?.offset, distance(displayClip[matchIdx], radiusVertex) < 1.0 {
                                        localRadii.append(CornerRadius(cornerIndex: matchIdx, radius: radius.radius, isInside: radius.isInside))
                                    }
                                }
                            }

                            if !localRadii.isEmpty {
                                let roundedClip = roundedPolygonPath(points: displayClip, cornerRadii: localRadii)
                                clipPath.addPath(roundedClip)
                            } else {
                                clipPath.move(to: displayClip[0])
                                for pt in displayClip.dropFirst() { clipPath.addLine(to: pt) }
                                clipPath.closeSubpath()
                            }
                        }
                        let subtracted = curvedPath.subtracting(clipPath)
                        let subBounds = subtracted.boundingRect
                        if subBounds.width >= 0.01 || subBounds.height >= 0.01 {
                            return subtracted
                        }
                        // Fallback to old pipeline
                        let fallbackResult = angledRightTrianglePoints(size: rawSize, notches: notches, angleCuts: pieceAngleCuts, curves: activeCurves)
                        let fallbackPoints = fallbackResult.points.map { displayPoint(fromRaw: $0) }
                        let fallbackMapped = mapCurvesToRawDisplayPoints(curves: activeCurves, displayPoints: fallbackPoints)
                        return curvedPolygonPath(points: fallbackPoints, shape: .rightTriangle, curves: fallbackMapped, baseBounds: baseBounds)
                    }
                }
                return curvedPath
            }

            // No curves: use existing polygon-based pipeline
            let result = angledRightTrianglePoints(size: rawSize, notches: notches, angleCuts: pieceAngleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            if !cornerRadii.isEmpty {
                let ordered = reorderCornersClockwise(displayPoints)
                let baseCorners = displayPolygonPointsForLabeling(for: piece, includeAngles: false)
                return roundedPolygonPath(points: ordered, cornerRadii: cornerRadii, baseCorners: baseCorners)
            }
            return polygonPath(displayPoints)
        }

        // Simple shapes without notches or angle cuts
        if !cornerRadii.isEmpty || !activeCurves.isEmpty {
            switch piece.shape {
            case .rectangle:
                let base = rectanglePoints(size: rawSize)
                let displayPoints = base.map { displayPoint(fromRaw: $0) }

                if !activeCurves.isEmpty {
                    // Always use the proven edge-based curvedRectanglePath
                    let size = displaySize(for: piece)
                    let curvedPath = curvedRectanglePath(width: size.width, height: size.height, curves: activeCurves)
                    if !cornerRadii.isEmpty {
                        return applyCornerRadiiToPath(curvedPath, cornerRadii: cornerRadii, piece: piece, displayPoints: displayPoints)
                    }
                    return curvedPath
                }
                if !cornerRadii.isEmpty {
                    let ordered = reorderCornersClockwise(displayPoints)
                    let baseCorners = displayPolygonPointsForLabeling(for: piece, includeAngles: false)
                    return roundedPolygonPath(points: ordered, cornerRadii: cornerRadii, baseCorners: baseCorners)
                }
            case .rightTriangle:
                let localNotches = notchCandidates(for: piece, size: rawSize)
                let base = localNotches.isEmpty ? rightTrianglePoints(size: rawSize) : notchRightTrianglePoints(size: rawSize, notches: localNotches)
                let displayPoints = base.map { displayPoint(fromRaw: $0) }

                if !activeCurves.isEmpty {
                    // If there are notches, use curvedPolygonPath to incorporate them with curves
                    // Otherwise use the simpler curvedRightTriangle
                    if !localNotches.isEmpty {
                        let displaySize = CGSize(width: rawSize.height, height: rawSize.width)
                        let baseBounds = CGRect(origin: .zero, size: displaySize)
                        let mappedCurves = mapCurvesToDisplayPointsUsingBaseCorners(
                            curves: activeCurves,
                            displayPoints: displayPoints,
                            baseCorners: baseTriangleCorners
                        )
                        let curvedPath = curvedPolygonPath(points: displayPoints, shape: .rightTriangle, curves: mappedCurves, baseBounds: baseBounds)
                        if !cornerRadii.isEmpty {
                            return applyCornerRadiiToPath(curvedPath, cornerRadii: cornerRadii, piece: piece, displayPoints: displayPoints)
                        }
                        return curvedPath
                    }
                    // No notches - use simple curvedRightTriangle
                    let size = displaySize(for: piece)
                    let curvedPath = curvedRightTriangle(width: size.width, height: size.height, curves: activeCurves)
                    if !cornerRadii.isEmpty {
                        return applyCornerRadiiToPath(curvedPath, cornerRadii: cornerRadii, piece: piece, displayPoints: displayPoints)
                    }
                    return curvedPath
                }
                if !cornerRadii.isEmpty {
                    let ordered = reorderCornersClockwise(displayPoints)
                    let baseCorners = displayPolygonPointsForLabeling(for: piece, includeAngles: false)
                    return roundedPolygonPath(points: ordered, cornerRadii: cornerRadii, baseCorners: baseCorners)
                }
            default:
                break
            }
        }
        let size = displaySize(for: piece)
        return path(for: piece.shape, size: size, curves: validCurves(for: piece))
    }
    
    /// Applies corner radii to corners of a path that aren't affected by curves.
    /// This allows curves and corner radii to coexist on different parts of the same piece.
    private static func applyCornerRadiiToPath(_ basePath: Path, cornerRadii: [CornerRadius], piece: Piece, displayPoints: [CGPoint]) -> Path {
        // Get the base corners for reference
        let baseCorners = displayPolygonPointsForLabeling(for: piece, includeAngles: false)
        let ordered = reorderCornersClockwise(displayPoints)

        func indexMap(from source: [CGPoint], to target: [CGPoint]) -> [Int: Int] {
            var map: [Int: Int] = [:]
            for (sourceIndex, sourcePoint) in source.enumerated() {
                var bestIndex = 0
                var bestDistance = CGFloat.greatestFiniteMagnitude
                for (targetIndex, targetPoint) in target.enumerated() {
                    let dx = sourcePoint.x - targetPoint.x
                    let dy = sourcePoint.y - targetPoint.y
                    let distance = dx * dx + dy * dy
                    if distance < bestDistance {
                        bestDistance = distance
                        bestIndex = targetIndex
                    }
                }
                map[sourceIndex] = bestIndex
            }
            return map
        }
        
        func exactIndexMap(from source: [CGPoint], to target: [CGPoint], tolerance: CGFloat = 0.5) -> [Int: Int] {
            var map: [Int: Int] = [:]
            for (sourceIndex, sourcePoint) in source.enumerated() {
                if let match = target.enumerated().first(where: { candidate in
                    abs(candidate.element.x - sourcePoint.x) <= tolerance &&
                    abs(candidate.element.y - sourcePoint.y) <= tolerance
                }) {
                    map[sourceIndex] = match.offset
                }
            }
            return map
        }

        let curveIndexMap = indexMap(from: displayPoints, to: ordered)
        let displayBounds = polygonBounds(displayPoints)
        let boundarySegments = boundarySegments(for: displayPoints, shape: piece.shape, bounds: displayBounds)
        let rawCurves = mapCurvesToRawDisplayPoints(curves: validCurves(for: piece), displayPoints: displayPoints)
        let mappedCurves: [CurvedEdge] = rawCurves.map { curve in
            guard curve.hasSpan else { return curve }
            guard let span = spanIndices(for: curve, boundarySegments: boundarySegments, pointCount: displayPoints.count, bounds: displayBounds, shape: piece.shape),
                  let mappedStart = curveIndexMap[span.start],
                  let mappedEnd = curveIndexMap[span.end] else {
                return curve
            }
            return CurvedEdge(
                startCornerIndex: mappedStart,
                endCornerIndex: mappedEnd,
                radius: curve.radius,
                isConcave: curve.isConcave,
                edge: curve.edge
            )
        }
        
        let cornerToDisplayMap = exactIndexMap(from: baseCorners, to: displayPoints)
        let mappedCornerRadii: [CornerRadius] = cornerRadii.compactMap { radius in
            guard let displayIndex = cornerToDisplayMap[radius.cornerIndex],
                  let orderedIndex = curveIndexMap[displayIndex] else { return nil }
            return CornerRadius(cornerIndex: orderedIndex, radius: radius.radius, isInside: radius.isInside)
        }
        
        // Build a new path that combines curved edges with rounded corners
        return roundedCurvedPolygonPath(
            points: ordered,
            cornerRadii: mappedCornerRadii,
            baseCorners: baseCorners,
            radiusBaseCorners: nil,
            curves: mappedCurves,
            shape: piece.shape,
            piece: piece
        )
    }

    /// Applies corner radii to an existing curved path using boolean clipping.
    /// Unlike applyCornerRadiiToPath (which rebuilds from scratch via roundedCurvedPolygonPath),
    /// this function preserves the existing curved path and only modifies the specific corners
    /// that need rounding — preventing curve flattening/distortion.
    ///
    /// For each corner with a radius: subtracts a triangular "sharp corner" clip from the path,
    /// then unions an arc fill to create the rounded corner.
    private static func applyCornerRadiiByClipping(_ basePath: Path, cornerRadii: [CornerRadius], piece: Piece, displayPoints: [CGPoint]) -> Path {
        guard !cornerRadii.isEmpty else { return basePath }

        let count = displayPoints.count
        guard count >= 3 else { return basePath }

        var result = basePath

        for radius in cornerRadii {
            guard radius.radius > 0, radius.cornerIndex >= 0, radius.cornerIndex < count else { continue }

            // Use displayPoints directly — the caller passes the polygon whose
            // index space matches the corner radius indices.
            let idx = radius.cornerIndex
            let curr = displayPoints[idx]
            let prev = displayPoints[(idx - 1 + count) % count]
            let next = displayPoints[(idx + 1) % count]

            // Compute tangent points (same math as roundedPolygonPath)
            let v1 = unitVector(from: curr, to: prev)
            let v2 = unitVector(from: curr, to: next)
            let dot = max(min(v1.x * v2.x + v1.y * v2.y, 1), -1)
            let angleSmall = acos(dot)
            guard angleSmall > 0.0001 else { continue }

            let lenPrev = distance(curr, prev)
            let lenNext = distance(curr, next)
            let tanHalf = tan(angleSmall / 2)
            let tanHalfAbs = abs(tanHalf)
            guard tanHalfAbs > 0.0001 else { continue }

            let maxRadius = min(lenPrev, lenNext) * tanHalfAbs
            let r = min(CGFloat(radius.radius), maxRadius)
            guard r > 0.0001 else { continue }

            let t = r / tanHalfAbs
            let p1 = CGPoint(x: curr.x + v1.x * t, y: curr.y + v1.y * t)  // tangent on prev edge
            let p2 = CGPoint(x: curr.x + v2.x * t, y: curr.y + v2.y * t)  // tangent on next edge

            // Arc center
            let bisector = unitVector(from: .zero, to: CGPoint(x: v1.x + v2.x, y: v1.y + v2.y))
            let sinHalf = sin(angleSmall / 2)
            guard sinHalf > 0.0001 else { continue }
            let centerOffset = r / sinHalf
            let center = CGPoint(x: curr.x + bisector.x * centerOffset,
                                 y: curr.y + bisector.y * centerOffset)

            let startRadians = atan2(p1.y - center.y, p1.x - center.x)
            let endRadians = atan2(p2.y - center.y, p2.x - center.x)
            var delta = endRadians - startRadians
            while delta <= -CGFloat.pi { delta += 2 * CGFloat.pi }
            while delta > CGFloat.pi { delta -= 2 * CGFloat.pi }
            let arcClockwise = delta < 0

            // Build the corner cap clip: the area between the sharp corner and the arc.
            // Shape: p1 → curr → p2, then arc back from p2 to p1 (closing the rounded edge).
            // Subtracting this from the path replaces the sharp corner with the arc.
            var cornerCap = Path()
            cornerCap.move(to: p1)
            cornerCap.addLine(to: curr)
            cornerCap.addLine(to: p2)
            // Arc from p2 back to p1 (same arc direction, swapped endpoints = reverse traversal)
            cornerCap.addArc(center: center, radius: r,
                            startAngle: .radians(endRadians),
                            endAngle: .radians(startRadians),
                            clockwise: arcClockwise)
            cornerCap.closeSubpath()

            result = result.subtracting(cornerCap)
        }

        return result
    }

    private static func mapCurvesToRawDisplayPoints(curves: [CurvedEdge], displayPoints: [CGPoint]) -> [CurvedEdge] {
        guard !curves.isEmpty else { return curves }
        let ordered = reorderCornersClockwise(displayPoints)

        func indexMap(from source: [CGPoint], to target: [CGPoint]) -> [Int: Int] {
            var map: [Int: Int] = [:]
            for (sourceIndex, sourcePoint) in source.enumerated() {
                var bestIndex = 0
                var bestDistance = CGFloat.greatestFiniteMagnitude
                for (targetIndex, targetPoint) in target.enumerated() {
                    let dx = sourcePoint.x - targetPoint.x
                    let dy = sourcePoint.y - targetPoint.y
                    let distance = dx * dx + dy * dy
                    if distance < bestDistance {
                        bestDistance = distance
                        bestIndex = targetIndex
                    }
                }
                map[sourceIndex] = bestIndex
            }
            return map
        }

        let labelToRaw = indexMap(from: ordered, to: displayPoints)
        return curves.map { curve in
            guard curve.usesCornerIndices else { return curve }
            let rawStart = labelToRaw[curve.startCornerIndex] ?? curve.startCornerIndex
            let rawEnd = labelToRaw[curve.endCornerIndex] ?? curve.endCornerIndex
            let mapped = CurvedEdge(startCornerIndex: rawStart, endCornerIndex: rawEnd, radius: curve.radius, isConcave: curve.isConcave, edge: curve.edge)
            mapped.startBoundarySegmentIndex = curve.startBoundarySegmentIndex
            mapped.startBoundaryIsEnd = curve.startBoundaryIsEnd
            mapped.endBoundarySegmentIndex = curve.endBoundarySegmentIndex
            mapped.endBoundaryIsEnd = curve.endBoundaryIsEnd
            mapped.startEdgeProgress = curve.startEdgeProgress
            mapped.endEdgeProgress = curve.endEdgeProgress
            return mapped
        }
    }

    private static func mapCurvesToDisplayPointsUsingBaseCorners(
        curves: [CurvedEdge],
        displayPoints: [CGPoint],
        baseCorners: [CGPoint]
    ) -> [CurvedEdge] {
        guard !curves.isEmpty else { return curves }
        guard !displayPoints.isEmpty, !baseCorners.isEmpty else { return curves }

        func indexMap(from source: [CGPoint], to target: [CGPoint]) -> [Int: Int] {
            var map: [Int: Int] = [:]
            for (sourceIndex, sourcePoint) in source.enumerated() {
                var bestIndex = 0
                var bestDistance = CGFloat.greatestFiniteMagnitude
                for (targetIndex, targetPoint) in target.enumerated() {
                    let dx = sourcePoint.x - targetPoint.x
                    let dy = sourcePoint.y - targetPoint.y
                    let distance = dx * dx + dy * dy
                    if distance < bestDistance {
                        bestDistance = distance
                        bestIndex = targetIndex
                    }
                }
                map[sourceIndex] = bestIndex
            }
            return map
        }

        func exactIndexMap(from source: [CGPoint], to target: [CGPoint], tolerance: CGFloat = 0.5) -> [Int: Int] {
            var map: [Int: Int] = [:]
            for (sourceIndex, sourcePoint) in source.enumerated() {
                if let match = target.enumerated().first(where: { candidate in
                    abs(candidate.element.x - sourcePoint.x) <= tolerance &&
                    abs(candidate.element.y - sourcePoint.y) <= tolerance
                }) {
                    map[sourceIndex] = match.offset
                } else {
                    map[sourceIndex] = indexMap(from: [sourcePoint], to: target)[0]
                }
            }
            return map
        }

        let baseToDisplay = exactIndexMap(from: baseCorners, to: displayPoints)
        return curves.map { curve in
            guard curve.usesCornerIndices else { return curve }
            guard curve.startCornerIndex >= 0, curve.endCornerIndex >= 0 else { return curve }
            if curve.startCornerIndex >= baseCorners.count || curve.endCornerIndex >= baseCorners.count {
                return curve
            }
            let mappedStart = baseToDisplay[curve.startCornerIndex] ?? curve.startCornerIndex
            let mappedEnd = baseToDisplay[curve.endCornerIndex] ?? curve.endCornerIndex
            let mapped = CurvedEdge(startCornerIndex: mappedStart, endCornerIndex: mappedEnd, radius: curve.radius, isConcave: curve.isConcave, edge: curve.edge)
            mapped.startBoundarySegmentIndex = curve.startBoundarySegmentIndex
            mapped.startBoundaryIsEnd = curve.startBoundaryIsEnd
            mapped.endBoundarySegmentIndex = curve.endBoundarySegmentIndex
            mapped.endBoundaryIsEnd = curve.endBoundaryIsEnd
            mapped.startEdgeProgress = curve.startEdgeProgress
            mapped.endEdgeProgress = curve.endEdgeProgress
            return mapped
        }
    }

    static func path(for shape: ShapeKind, size: CGSize, curves: [CurvedEdge]) -> Path {
        let width = size.width
        let height = size.height

        switch shape {
        case .rectangle:
            return curvedRectanglePath(width: width, height: height, curves: curves)
        case .circle:
            return Path(ellipseIn: CGRect(x: 0, y: 0, width: width, height: height))
        case .quarterCircle:
            return quarterCirclePath(radius: width)
        case .rightTriangle:
            return curvedRightTriangle(width: width, height: height, curves: curves)
        }
    }

    private static func notchCandidates(for piece: Piece, size: CGSize) -> [Cutout] {
        piece.cutouts.filter { cutout in
            guard cutout.kind != .circle else { return false }
            guard cutout.isPlaced else { return false }
            // Must actually overlap the piece — a cutout fully beyond the edge is not a notch
            guard cutoutOverlapsPiece(cutout: cutout, size: size, shape: piece.shape, curves: []) else { return false }
            // Use dynamic geometric evaluation - don't rely on stale isNotch flag
            return cutoutTouchesBoundary(cutout: cutout, size: size, shape: piece.shape)
        }
    }

    /// Curve-aware notch candidates: only includes cutouts that touch the CURVED boundary,
    /// not just the straight-edge boundary. Used for labeling so that cutouts interior to
    /// the curve are not counted as notches in the polygon point count.
    /// Curve-aware notch candidates for labeling polygon.
    /// When curves are active, the curve IS the boundary on that edge — the original
    /// straight edge has no effect. A cutout is a notch candidate only if it touches
    /// the curved boundary OR a straight edge that has no curve on it.
    /// The isNotch flag alone does NOT qualify — geometry determines notch status.
    private static func notchCandidatesCurveAware(for piece: Piece, size: CGSize) -> [Cutout] {
        let activeCurves = validCurves(for: piece)
        guard !activeCurves.isEmpty else {
            return notchCandidates(for: piece, size: size)
        }
        return piece.cutouts.filter { cutout in
            guard cutout.kind != .circle else { return false }
            guard cutout.isPlaced else { return false }
            // Must overlap the piece — fully outside means not a notch
            guard cutoutOverlapsPiece(cutout: cutout, size: size, shape: piece.shape, curves: activeCurves) else {
                return false
            }
            // cutoutFullyInsideBoundary is the sole authority:
            // If the cutout extends beyond the curved boundary → notch.
            // If fully inside → interior cutout (not a notch).
            return !cutoutFullyInsideBoundary(cutout: cutout, size: size, shape: piece.shape, curves: activeCurves)
        }
    }

    /// Returns true if the cutout touches at least one straight edge that does NOT
    /// have an active curve on it. When a curve is on an edge, the curve replaces
    /// the straight edge as the boundary — touching only the straight line under
    /// a curve does not make a cutout a perimeter notch.
    ///
    /// Edge mapping (raw → display): raw top(y=0)→display .left,
    /// raw bottom(y=h)→display .right, raw left(x=0)→display .top,
    /// raw right(x=w)→display .bottom.
    /// Returns the set of display edges that are fully covered by a curve
    /// (either a full-edge curve or segment curves spanning the entire edge).
    /// Edges with only partial segment curves are NOT included.
    static func fullyCurvedEdges(_ curves: [CurvedEdge]) -> Set<EdgePosition> {
        var result: Set<EdgePosition> = []
        let byEdge = Dictionary(grouping: curves.filter { $0.radius > 0 }, by: { $0.edge })
        for (edge, edgeCurves) in byEdge {
            // Full-edge curve (no span) → fully curved
            if edgeCurves.contains(where: { !$0.hasSpan }) {
                result.insert(edge)
                continue
            }
            // Check if segment curves collectively cover the full edge (0 to 1)
            let spans = edgeCurves.compactMap { curve -> (CGFloat, CGFloat)? in
                guard curve.usesEdgeProgress else { return nil }
                let p0 = CGFloat(min(curve.startEdgeProgress, curve.endEdgeProgress))
                let p1 = CGFloat(max(curve.startEdgeProgress, curve.endEdgeProgress))
                return (p0, p1)
            }.sorted { $0.0 < $1.0 }
            guard !spans.isEmpty else { continue }
            // Check if spans cover from ~0 to ~1
            var coverage: CGFloat = 0
            for (p0, p1) in spans {
                if p0 > coverage + 0.02 { break } // gap found
                coverage = max(coverage, p1)
            }
            if coverage >= 0.98 {
                result.insert(edge)
            }
        }
        return result
    }

    static func cutoutTouchesUncurvedEdge(
        cutout: Cutout,
        size: CGSize,
        shape: ShapeKind,
        curvedDisplayEdges: Set<EdgePosition>
    ) -> Bool {
        let corners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape)
        let bounds = GeometryHelpers.bounds(for: corners)
        let tolerance: CGFloat = 0.001

        switch shape {
        case .rectangle:
            // Raw top (y=0) → display .left
            if bounds.minY <= tolerance && !curvedDisplayEdges.contains(.left) { return true }
            // Raw bottom (y=height) → display .right
            if bounds.maxY >= size.height - tolerance && !curvedDisplayEdges.contains(.right) { return true }
            // Raw left (x=0) → display .top
            if bounds.minX <= tolerance && !curvedDisplayEdges.contains(.top) { return true }
            // Raw right (x=width) → display .bottom
            if bounds.maxX >= size.width - tolerance && !curvedDisplayEdges.contains(.bottom) { return true }
            return false
        case .rightTriangle:
            // Raw top (y=0) → display .left
            if bounds.minY <= tolerance && !curvedDisplayEdges.contains(.left) { return true }
            // Raw left (x=0) → display .top
            if bounds.minX <= tolerance && !curvedDisplayEdges.contains(.top) { return true }
            // Hypotenuse
            if cutoutTouchesHypotenuse(corners: corners, size: size, eps: tolerance)
                && !curvedDisplayEdges.contains(.hypotenuse) { return true }
            return false
        default:
            return false
        }
    }

    /// Returns true if the cutout touches the straight-line version of an edge that HAS a curve.
    /// This is the complement of cutoutTouchesUncurvedEdge — it detects cutouts in the
    /// "transition zone" where the straight edge has been replaced by a curve.
    static func cutoutTouchesCurvedEdge(
        cutout: Cutout,
        size: CGSize,
        shape: ShapeKind,
        curvedDisplayEdges: Set<EdgePosition>
    ) -> Bool {
        guard !curvedDisplayEdges.isEmpty else { return false }
        let corners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape)
        let bounds = GeometryHelpers.bounds(for: corners)
        let tolerance: CGFloat = 0.001

        switch shape {
        case .rectangle:
            // Raw top (y=0) → display .left
            if bounds.minY <= tolerance && curvedDisplayEdges.contains(.left) { return true }
            // Raw bottom (y=height) → display .right
            if bounds.maxY >= size.height - tolerance && curvedDisplayEdges.contains(.right) { return true }
            // Raw left (x=0) → display .top
            if bounds.minX <= tolerance && curvedDisplayEdges.contains(.top) { return true }
            // Raw right (x=width) → display .bottom
            if bounds.maxX >= size.width - tolerance && curvedDisplayEdges.contains(.bottom) { return true }
            return false
        case .rightTriangle:
            // Raw top (y=0) → display .left
            if bounds.minY <= tolerance && curvedDisplayEdges.contains(.left) { return true }
            // Raw left (x=0) → display .top
            if bounds.minX <= tolerance && curvedDisplayEdges.contains(.top) { return true }
            // Hypotenuse
            if cutoutTouchesHypotenuse(corners: corners, size: size, eps: tolerance)
                && curvedDisplayEdges.contains(.hypotenuse) { return true }
            return false
        default:
            return false
        }
    }

    static func cutoutTouchesBoundary(cutout: Cutout, size: CGSize, shape: ShapeKind) -> Bool {
        // For custom angle cutouts, use UNROTATED corners to determine if it touches the boundary.
        // This prevents interior cutouts from being incorrectly classified as notches just because
        // their rotated corners happen to extend to/beyond the triangle edges.
        let corners: [CGPoint]
        if shape == .rightTriangle && cutout.orientation == .custom {
            // Create an unrotated version of the cutout (as if customAngleDegrees = 0)
            let unrotatedCutout = Cutout(
                kind: cutout.kind,
                width: cutout.width,
                height: cutout.height,
                centerX: cutout.centerX,
                centerY: cutout.centerY,
                isNotch: cutout.isNotch,
                orientation: .legs,  // Use legs orientation to get unrotated corners
                customAngleDegrees: 0
            )
            corners = GeometryHelpers.cutoutCornerPoints(cutout: unrotatedCutout, size: size, shape: shape)
        } else {
            corners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape)
        }
        
        let bounds = GeometryHelpers.bounds(for: corners)
        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY
        // Use a small tolerance for "on the edge" detection
        let tolerance: CGFloat = 0.001

        // Reject cutouts that don't actually overlap the piece interior.
        // A cutout entirely past an edge (e.g., all corners beyond the right side)
        // would pass the "touches boundary" checks below but has no real intersection
        // with the piece, producing degenerate geometry (protrusions, negative depths).
        let clampedMinX = max(0, minX)
        let clampedMaxX = min(size.width, maxX)
        let clampedMinY = max(0, minY)
        let clampedMaxY = min(size.height, maxY)
        if clampedMaxX < clampedMinX || clampedMaxY < clampedMinY {
            return false
        }

        switch shape {
        case .rightTriangle:
            // A cutout touches the boundary if any corner is on or beyond any edge:
            // - Top edge (y = 0): any corner with y <= tolerance
            // - Left edge (x = 0): any corner with x <= tolerance
            // - Hypotenuse: any corner on or beyond the line x/w + y/h = 1
            let touchesTop = minY <= tolerance
            let touchesLeft = minX <= tolerance
            let touchesHypotenuse = cutoutTouchesHypotenuse(corners: corners, size: size, eps: tolerance)
            return touchesTop || touchesLeft || touchesHypotenuse
        default:
            return minX <= tolerance || minY <= tolerance || maxX >= size.width - tolerance || maxY >= size.height - tolerance
        }
    }

    static func cutoutTouchesBoundary(cutout: Cutout, size: CGSize, shape: ShapeKind, curves: [CurvedEdge]) -> Bool {
        guard !curves.isEmpty else {
            return cutoutTouchesBoundary(cutout: cutout, size: size, shape: shape)
        }

        // cutoutCornerPoints returns RAW coordinates, but curvedRectanglePath/curvedRightTriangle
        // work in DISPLAY coordinates (x↔y swapped). Convert corners to display space and use
        // display-size for the boundary path so the curve is applied to the correct edge.
        let rawCorners: [CGPoint]
        if shape == .rightTriangle && cutout.orientation == .custom {
            let unrotatedCutout = Cutout(
                kind: cutout.kind,
                width: cutout.width,
                height: cutout.height,
                centerX: cutout.centerX,
                centerY: cutout.centerY,
                isNotch: cutout.isNotch,
                orientation: .legs,
                customAngleDegrees: 0
            )
            rawCorners = GeometryHelpers.cutoutCornerPoints(cutout: unrotatedCutout, size: size, shape: shape)
        } else {
            rawCorners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape)
        }

        // Convert raw corners to display space
        let corners = rawCorners.map { displayPoint(fromRaw: $0) }

        // Build the curved boundary path in display coordinates
        let displaySize = CGSize(width: size.height, height: size.width)
        let boundaryPath = path(for: shape, size: displaySize, curves: curves)
        let cgPath = boundaryPath.cgPath
        let stroke = cgPath.copy(strokingWithWidth: 1.0, lineCap: .butt, lineJoin: .miter, miterLimit: 1)

        // Classify corners as inside/outside the curved boundary
        var anyInside = false
        var anyOutside = false
        for corner in corners {
            if cgPath.contains(corner, using: .winding, transform: .identity) {
                if stroke.contains(corner, using: .winding, transform: .identity) {
                    // Corner is on the boundary stroke — treat as outside (touching)
                    anyOutside = true
                }
                anyInside = true
            } else {
                anyOutside = true
            }
        }

        // Case 1: Some corners inside, some outside → cutout straddles the boundary.
        // This is a valid notch that crosses the curved edge.
        if anyInside && anyOutside {
            return true
        }

        // Case 2: All corners outside the boundary. The cutout might be entirely
        // outside the piece (should return false) or might wrap around / intersect
        // the boundary in a way that still creates a notch. Check for actual overlap.
        if anyOutside && !anyInside {
            guard corners.count >= 3 else { return false }
            var cutoutPath = Path()
            cutoutPath.move(to: corners[0])
            for i in 1..<corners.count {
                cutoutPath.addLine(to: corners[i])
            }
            cutoutPath.closeSubpath()
            let intersection = boundaryPath.intersection(cutoutPath)
            let intBounds = intersection.boundingRect
            // Only a boundary-touching notch if there's meaningful overlap with the piece
            return intBounds.width > 0.01 && intBounds.height > 0.01
        }

        // Case 3: All corners inside the curved boundary. The cutout may still
        // touch/cross the boundary if its edges intersect the curve.
        if corners.count >= 3 {
            var cutoutPath = Path()
            cutoutPath.move(to: corners[0])
            for i in 1..<corners.count {
                cutoutPath.addLine(to: corners[i])
            }
            cutoutPath.closeSubpath()

            let intersection = boundaryPath.intersection(cutoutPath)
            let intBounds = intersection.boundingRect
            if intBounds.width > 0.01 && intBounds.height > 0.01 {
                let cutoutBounds = cutoutPath.boundingRect
                let cutoutArea = cutoutBounds.width * cutoutBounds.height
                let intArea = intBounds.width * intBounds.height
                // If the cutout extends outside the boundary at all, it's a boundary notch
                if intArea < cutoutArea * 0.99 {
                    return true
                }
            }
        }

        return false
    }

    /// Returns true if the cutout has any meaningful overlap with the piece interior,
    /// considering curved edges. Returns false if the cutout is entirely outside the piece.
    static func cutoutOverlapsPiece(cutout: Cutout, size: CGSize, shape: ShapeKind, curves: [CurvedEdge]) -> Bool {
        let activeCurves = curves.filter { $0.radius > 0 }

        // Without curves, check against straight-edge bounding box
        if activeCurves.isEmpty {
            let corners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape)
            let bounds = GeometryHelpers.bounds(for: corners)
            let clampedMinX = max(0, bounds.minX)
            let clampedMaxX = min(size.width, bounds.maxX)
            let clampedMinY = max(0, bounds.minY)
            let clampedMaxY = min(size.height, bounds.maxY)
            return clampedMaxX > clampedMinX && clampedMaxY > clampedMinY
        }

        // With curves, build the curved boundary path and check intersection
        let rawCorners: [CGPoint]
        if shape == .rightTriangle && cutout.orientation == .custom {
            let unrotatedCutout = Cutout(
                kind: cutout.kind, width: cutout.width, height: cutout.height,
                centerX: cutout.centerX, centerY: cutout.centerY,
                isNotch: cutout.isNotch, orientation: .legs, customAngleDegrees: 0
            )
            rawCorners = GeometryHelpers.cutoutCornerPoints(cutout: unrotatedCutout, size: size, shape: shape)
        } else {
            rawCorners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape)
        }
        let corners = rawCorners.map { displayPoint(fromRaw: $0) }
        let displaySize = CGSize(width: size.height, height: size.width)
        let boundaryPath = path(for: shape, size: displaySize, curves: activeCurves)
        let cgPath = boundaryPath.cgPath

        // Quick check: if any corner is inside the boundary, there's overlap
        for corner in corners {
            if cgPath.contains(corner, using: .winding, transform: .identity) {
                return true
            }
        }

        // Check if the cutout's center is inside the boundary
        let rawCenter = CGPoint(x: cutout.centerX, y: cutout.centerY)
        let displayCenter = displayPoint(fromRaw: rawCenter)
        if cgPath.contains(displayCenter, using: .winding, transform: .identity) {
            return true
        }

        // All corners outside. Check if the cutout path intersects the boundary.
        // This catches cases where the cutout straddles the curve (thin crescent overlap).
        guard corners.count >= 3 else { return false }
        var cutoutPath = Path()
        cutoutPath.move(to: corners[0])
        for i in 1..<corners.count {
            cutoutPath.addLine(to: corners[i])
        }
        cutoutPath.closeSubpath()
        let cutoutCGPath = cutoutPath.cgPath
        
        // Check if any point along the cutout edges is inside the boundary
        // Sample multiple points along each edge for better coverage
        for i in 0..<corners.count {
            let start = corners[i]
            let end = corners[(i + 1) % corners.count]
            for j in 1...3 {
                let t = CGFloat(j) / 4.0
                let sample = CGPoint(x: start.x + t * (end.x - start.x), y: start.y + t * (end.y - start.y))
                if cgPath.contains(sample, using: .winding, transform: .identity) {
                    return true
                }
            }
        }
        
        // Check if any point along curve edges is inside the cutout
        // Sample points along the boundary path and check if any are inside the cutout
        let sampleCount = 40
        for curve in activeCurves {
            // Get edge endpoints and normal in display coordinates
            guard let edgeInfo = edgeInfoForOverlapCheck(for: curve.edge, shape: shape, size: displaySize) else { continue }
            let start = edgeInfo.start
            let end = edgeInfo.end
            let normal = edgeInfo.normal
            
            // Calculate control point for the curve (matching addEdge logic: radius * 2)
            // For concave curves, the direction is reversed
            let direction: CGFloat = curve.isConcave ? -1.0 : 1.0
            let midX = (start.x + end.x) / 2
            let midY = (start.y + end.y) / 2
            let control = CGPoint(
                x: midX + normal.x * CGFloat(curve.radius) * 2 * direction,
                y: midY + normal.y * CGFloat(curve.radius) * 2 * direction
            )
            
            // Sample points along the quadratic Bezier curve
            for i in 1..<sampleCount {
                let t = CGFloat(i) / CGFloat(sampleCount)
                let point = GeometryHelpers.quadBezierPoint(t: t, start: start, control: control, end: end)
                if cutoutCGPath.contains(point, using: .winding, transform: .identity) {
                    return true
                }
            }
        }
        
        let intersection = boundaryPath.intersection(cutoutPath)
        // Check if intersection has meaningful area
        // Path.isEmpty can return false even for degenerate paths, so check bounding rect
        if intersection.isEmpty {
            return false
        }
        let bounds = intersection.boundingRect
        // Require at least 0.1 x 0.1 area to be considered overlapping
        // This filters out numerical artifacts from path operations
        return bounds.width > 0.1 && bounds.height > 0.1
    }
    
    /// Returns the start, end, and outward normal of an edge in display coordinates
    /// These match the values used in curvedRectanglePath and curvedRightTriangle
    private static func edgeInfoForOverlapCheck(for edge: EdgePosition, shape: ShapeKind, size: CGSize) -> (start: CGPoint, end: CGPoint, normal: CGPoint)? {
        switch shape {
        case .rectangle:
            switch edge {
            case .top: return (CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: -1))
            case .right: return (CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 1, y: 0))
            case .bottom: return (CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 1))
            case .left: return (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
            default: return nil
            }
        case .rightTriangle:
            switch edge {
            case .legA: return (CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: -1))
            case .hypotenuse: return (CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: 0.7, y: 0.7))
            case .legB: return (CGPoint(x: 0, y: size.height), CGPoint(x: 0, y: 0), CGPoint(x: -1, y: 0))
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Returns true if the cutout is entirely inside the piece boundary with a gap
    /// (not touching the boundary). Returns false if the cutout extends beyond or is
    /// flush with (touching) the boundary — meaning it's a perimeter notch.
    ///
    /// Works with both straight and curved boundaries using cgPath.contains only.
    /// Path.subtracting is deliberately avoided because it produces numerical artifacts.
    ///
    /// Algorithm:
    /// 1. cgPath.contains for each corner → must all be inside the boundary
    /// 2. Expand each corner slightly outward (away from cutout center) and re-check
    ///    cgPath.contains → if expanded corner is STILL inside, there's a gap between
    ///    the cutout and the boundary (interior). If ANY expanded corner falls outside,
    ///    the cutout was flush with/touching the boundary (perimeter notch).
    static func cutoutFullyInsideBoundary(cutout: Cutout, size: CGSize, shape: ShapeKind, curves: [CurvedEdge]) -> Bool {
        let rawCorners: [CGPoint]
        if shape == .rightTriangle && cutout.orientation == .custom {
            let unrotatedCutout = Cutout(
                kind: cutout.kind, width: cutout.width, height: cutout.height,
                centerX: cutout.centerX, centerY: cutout.centerY,
                isNotch: cutout.isNotch, orientation: .legs, customAngleDegrees: 0
            )
            rawCorners = GeometryHelpers.cutoutCornerPoints(cutout: unrotatedCutout, size: size, shape: shape)
        } else {
            rawCorners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape)
        }
        let corners = rawCorners.map { displayPoint(fromRaw: $0) }
        let displaySize = CGSize(width: size.height, height: size.width)
        let boundaryPath = path(for: shape, size: displaySize, curves: curves)
        let cgPath = boundaryPath.cgPath

        // Check 1: if ANY corner is outside the boundary, it's not fully inside.
        for corner in corners {
            if !cgPath.contains(corner, using: .winding, transform: .identity) {
                return false
            }
        }

        // Check 2: Expand each corner outward (away from cutout centroid) and test
        // if the expanded point is still inside the boundary. This detects whether
        // the cutout is touching the boundary or has a gap.
        //
        // For a straight edge: a flush cutout's corner is at the edge; expanding
        // pushes it outside → correctly detected as boundary notch.
        //
        // For a convex curve: the boundary has moved outward from the straight edge.
        // A cutout at the straight edge position has a gap to the curve. Expanding
        // the corner slightly still lands inside the curved boundary → correctly
        // detected as interior.
        let expandAmount: CGFloat = 0.25
        let centroid = CGPoint(
            x: corners.reduce(0.0) { $0 + $1.x } / CGFloat(corners.count),
            y: corners.reduce(0.0) { $0 + $1.y } / CGFloat(corners.count)
        )

        for corner in corners {
            let dx = corner.x - centroid.x
            let dy = corner.y - centroid.y
            let len = sqrt(dx * dx + dy * dy)
            guard len > 0.001 else { continue }
            // Move corner outward (away from centroid) by expandAmount
            let expanded = CGPoint(
                x: corner.x + dx / len * expandAmount,
                y: corner.y + dy / len * expandAmount
            )
            if !cgPath.contains(expanded, using: .winding, transform: .identity) {
                return false  // Corner is on or very close to boundary → perimeter notch
            }
        }

        // All corners are inside AND have clearance from the boundary → interior cutout.
        return true
    }

    /// Dynamically evaluates whether a cutout is currently a notch based on the piece's
    /// current geometry (including curves). This should be used instead of checking
    /// `cutout.isNotch` directly, as the persisted flag may be stale when curves change.
    ///
    /// A cutout is considered a notch if:
    /// 1. It overlaps the piece boundary
    /// 2. It is NOT fully contained within the curved boundary
    ///
    /// When curve configuration changes (e.g., two segment curves become one full curve),
    /// a cutout that was previously a notch may become an interior cutout, or vice versa.
    static func isCurrentlyNotch(cutout: Cutout, piece: Piece) -> Bool {
        guard cutout.kind != .circle else { return false }
        guard cutout.isPlaced else { return false }
        
        let size = pieceSize(for: piece)
        let activeCurves = validCurves(for: piece)
        
        // Must overlap the piece — fully outside means not a notch
        guard cutoutOverlapsPiece(cutout: cutout, size: size, shape: piece.shape, curves: activeCurves) else {
            return false
        }
        
        // If fully inside the curved boundary, it's an interior cutout, not a notch
        if cutoutFullyInsideBoundary(cutout: cutout, size: size, shape: piece.shape, curves: activeCurves) {
            return false
        }
        
        // Cutout extends beyond the curved boundary → notch
        return true
    }

    private static func cutoutTouchesHypotenuse(corners: [CGPoint], size: CGSize, eps: CGFloat) -> Bool {
        let width = max(size.width, 0.0001)
        let height = max(size.height, 0.0001)
        
        // Hypotenuse line equation: x/width + y/height = 1
        // value < 0 means inside triangle, value = 0 means on hypotenuse, value > 0 means outside
        // A cutout touches the hypotenuse if any corner is on or beyond the hypotenuse line
        let tolerance: CGFloat = 0.001
        for corner in corners {
            let value = (corner.x / width) + (corner.y / height) - 1
            // If any corner is on or outside the hypotenuse, the cutout touches the boundary
            if value >= -tolerance {
                return true
            }
        }
        return false
    }
    
    private static func cutoutIsInsideTriangle(cutout: Cutout, size: CGSize) -> Bool {
        let width = max(size.width, 0.0001)
        let height = max(size.height, 0.0001)
        let corners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: .rightTriangle)
        // Use the same epsilon as cutoutTouchesBoundary (0.5) to avoid a gap where cutouts 
        // are neither "inside" nor "touching boundary". A cutout is considered "inside or touching"
        // if all corners are within this tolerance of the triangle boundary.
        let eps: CGFloat = 0.5
        // Convert distance epsilon to the hypotenuse equation tolerance
        // For point (x,y), distance to hypotenuse line x/w + y/h = 1 is:
        // |x/w + y/h - 1| * w * h / sqrt(w^2 + h^2)
        // So equation tolerance = distance * sqrt(w^2 + h^2) / (w * h)
        let hypotenuseLength = sqrt(width * width + height * height)
        let eqTolerance = eps * hypotenuseLength / (width * height)
        for corner in corners {
            if corner.x < -eps || corner.y < -eps {
                return false
            }
            if (corner.x / width) + (corner.y / height) > 1.0 + eqTolerance {
                return false
            }
        }
        return true
    }

    private static func cutoutHypotenuseSpan(minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat, size: CGSize) -> (start: CGFloat, end: CGFloat, depth: CGFloat, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)? {
        let width = max(size.width, 0.0001)
        let height = max(size.height, 0.0001)
        var tValues: [CGFloat] = []

        let xCandidates = [minX, maxX]
        for x in xCandidates {
            let t = (width - x) / width
            if t >= 0 && t <= 1 {
                let y = height * t
                if y >= minY - 0.01 && y <= maxY + 0.01 {
                    tValues.append(t)
                }
            }
        }

        let yCandidates = [minY, maxY]
        for y in yCandidates {
            let t = y / height
            if t >= 0 && t <= 1 {
                let x = width * (1 - t)
                if x >= minX - 0.01 && x <= maxX + 0.01 {
                    tValues.append(t)
                }
            }
        }

        guard tValues.count >= 2 else { return nil }
        tValues.sort()
        let start = tValues.first ?? 0
        let end = tValues.last ?? 0
        let depth = maxHypotenuseDepth(minX: minX, maxX: maxX, minY: minY, maxY: maxY, size: size)
        if depth <= 0 { return nil }
        // Return the rectangle bounds along with the span for axis-aligned rendering
        return (start: start, end: end, depth: depth, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    private static func maxHypotenuseDepth(minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat, size: CGSize) -> CGFloat {
        let width = max(size.width, 0.0001)
        let height = max(size.height, 0.0001)
        let denom = max(sqrt((1 / width) * (1 / width) + (1 / height) * (1 / height)), 0.0001)
        let corners = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY)
        ]
        var maxDepth: CGFloat = 0
        for corner in corners {
            let signed = ((corner.x / width) + (corner.y / height) - 1) / denom
            if signed <= 0 {
                maxDepth = max(maxDepth, -signed)
            }
        }
        return maxDepth
    }

    private static func hypotenuseInwardNormal(size: CGSize) -> CGPoint {
        let width = max(size.width, 0.0001)
        let height = max(size.height, 0.0001)
        var normal = CGPoint(x: -(1 / width), y: -(1 / height))
        let length = max(sqrt(normal.x * normal.x + normal.y * normal.y), 0.0001)
        normal = CGPoint(x: normal.x / length, y: normal.y / length)
        return normal
    }

    private static func pointOnHypotenuse(start: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }

    private static func boundaryAngleCuts(for piece: Piece) -> [AngleCut] {
        // Use the labeling polygon count (curve-aware) so indices align with the UI picker.
        let polygonCount = displayPolygonPointsForLabeling(for: piece, includeAngles: false).count
        return piece.angleCuts.filter { $0.anchorCornerIndex >= 0 && $0.anchorCornerIndex < polygonCount }
    }

    private static func pieceCornerRadii(for piece: Piece) -> [CornerRadius] {
        // Use the labeling polygon count (curve-aware notches) to validate indices,
        // since the UI assigns corner indices from the same labeling polygon.
        let cornerCount = cornerLabelCount(for: piece)
        return piece.cornerRadii.filter { $0.radius > 0 && $0.cornerIndex >= 0 && $0.cornerIndex < cornerCount }
    }

    private static func quarterCirclePath(radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.addArc(center: CGPoint(x: 0, y: 0), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.closeSubpath()
        return path
    }

    static func cutoutPath(_ cutout: Cutout) -> Path {
        switch cutout.kind {
        case .circle:
            return Path(ellipseIn: CGRect(x: cutout.centerX - cutout.width / 2, y: cutout.centerY - cutout.height / 2, width: cutout.width, height: cutout.height))
        case .square:
            return Path(CGRect(x: cutout.centerX - cutout.width / 2, y: cutout.centerY - cutout.width / 2, width: cutout.width, height: cutout.width))
        case .rectangle:
            return Path(CGRect(x: cutout.centerX - cutout.width / 2, y: cutout.centerY - cutout.height / 2, width: cutout.width, height: cutout.height))
        }
    }

    static func cutoutPath(_ cutout: Cutout, angleCuts: [AngleCut], cornerRadii: [CornerRadius], size: CGSize, shape: ShapeKind) -> Path {
        switch cutout.kind {
        case .circle:
            return cutoutPath(cutout)
        case .square, .rectangle:
            var points = reorderCornersClockwise(GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape))
            if !angleCuts.isEmpty {
                points = applyAngleCutsDisplay(to: points, angleCuts: angleCuts)
            }
            let localRadii = cornerRadii.filter { $0.cornerIndex >= 0 }
            if !localRadii.isEmpty {
                let baseCorners = reorderCornersClockwise(GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape))
                return roundedPolygonPath(points: points, cornerRadii: localRadii, baseCorners: baseCorners)
            }
            return polygonPath(points)
        }
    }

    static func cutoutPath(_ cutout: Cutout, angleCuts: [AngleCut], cornerRadii: [CornerRadius]) -> Path {
        cutoutPath(
            cutout,
            angleCuts: angleCuts,
            cornerRadii: cornerRadii,
            size: CGSize(width: cutout.width, height: cutout.height),
            shape: .rectangle
        )
    }

    static func cornerLabelCount(for piece: Piece) -> Int {
        let outlineCount = displayPolygonPointsForLabeling(for: piece, includeAngles: false).count
        return outlineCount + interiorCutoutsCurveAware(for: piece).count * 4
    }

    static func pieceCornerCount(for piece: Piece) -> Int {
        baseCornerPoints(for: piece).count
    }

    static func interiorCutouts(for piece: Piece) -> [Cutout] {
        let rawSize = pieceSize(for: piece)
        return piece.cutouts.filter { cutout in
            guard cutout.isPlaced else { return false }
            guard cutout.kind != .circle else { return false }
            // Use dynamic evaluation - a cutout is interior if it's NOT currently a notch
            guard !isCurrentlyNotch(cutout: cutout, piece: piece) else { return false }
            // Skip cutouts entirely outside the piece boundary
            if !cutoutOverlapsPiece(cutout: cutout, size: rawSize, shape: piece.shape, curves: []) {
                return false
            }
            if piece.shape == .rightTriangle {
                return cutoutIsInsideTriangle(cutout: cutout, size: rawSize) &&
                    !cutoutTouchesBoundary(cutout: cutout, size: rawSize, shape: piece.shape)
            }
            return !cutoutTouchesBoundary(cutout: cutout, size: rawSize, shape: piece.shape)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Curve-aware interior cutouts: cutouts that need their own 4 corner labels.
    /// When curves are active, the curve IS the boundary on that edge. Cutouts
    /// that extend beyond the curved boundary are treated as notches and get
    /// perimeter labels; only fully interior cutouts get their own 4 labels.
    static func interiorCutoutsCurveAware(for piece: Piece) -> [Cutout] {
        let activeCurves = validCurves(for: piece)
        guard !activeCurves.isEmpty else {
            return interiorCutouts(for: piece)
        }
        let rawSize = pieceSize(for: piece)
        return piece.cutouts.filter { cutout in
            guard cutout.isPlaced else { return false }
            guard cutout.kind != .circle else { return false }
            // Exclude cutouts entirely outside the piece (past the curve boundary)
            if !cutoutOverlapsPiece(cutout: cutout, size: rawSize, shape: piece.shape, curves: activeCurves) {
                return false
            }
            // Case 1: Fully inside the curved boundary → interior.
            if cutoutFullyInsideBoundary(cutout: cutout, size: rawSize, shape: piece.shape, curves: activeCurves) {
                if piece.shape == .rightTriangle {
                    return cutoutIsInsideTriangle(cutout: cutout, size: rawSize)
                }
                return true
            }
            return false
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func cutoutCornerRanges(for piece: Piece) -> [(cutout: Cutout, range: Range<Int>)] {
        let outlineCount = displayPolygonPointsForLabeling(for: piece, includeAngles: false).count
        var nextIndex = outlineCount
        var ranges: [(Cutout, Range<Int>)] = []
        for cutout in interiorCutoutsCurveAware(for: piece) {
            let range = nextIndex..<(nextIndex + 4)
            ranges.append((cutout, range))
            nextIndex += 4
        }
        return ranges
    }

    static func interiorCornerIndices(for piece: Piece) -> Set<Int> {
        let ranges = cutoutCornerRanges(for: piece)
        guard !ranges.isEmpty else { return [] }
        var indices = Set<Int>()
        for entry in ranges {
            for index in entry.range {
                indices.insert(index)
            }
        }
        return indices
    }

    /// Notch interior corners: for each notch cutout, pick the two cutout corners
    /// closest to the piece center and map them to labeling indices.
    static func notchInteriorCornerIndices(for piece: Piece) -> Set<Int> {
        let labelingPoints = displayPolygonPointsForLabeling(for: piece, includeAngles: false)
        guard !labelingPoints.isEmpty else { return [] }
        let rawSize = pieceSize(for: piece)
        let curves = validCurves(for: piece)
        let rawCenter = CGPoint(x: rawSize.width / 2, y: rawSize.height / 2)

        func nearestLabelIndex(to point: CGPoint) -> Int? {
            var bestIndex: Int?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for (index, candidate) in labelingPoints.enumerated() {
                let d = distance(candidate, point)
                if d < bestDistance {
                    bestDistance = d
                    bestIndex = index
                }
            }
            return bestIndex
        }

        var indices = Set<Int>()
        for cutout in piece.cutouts {
            guard cutout.isPlaced else { continue }
            guard cutout.kind != .circle else { continue }
            if !cutoutTouchesBoundary(cutout: cutout, size: rawSize, shape: piece.shape, curves: curves) {
                continue
            }
            if cutoutFullyInsideBoundary(cutout: cutout, size: rawSize, shape: piece.shape, curves: curves) {
                continue
            }
            let rawCorners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: rawSize, shape: piece.shape)
            let displayCorners = rawCorners.map { displayPoint(fromRaw: $0) }
            let sortedByCenter = displayCorners
                .map { (point: $0, dist: distance(rawCenter, $0)) }
                .sorted { $0.dist < $1.dist }
            for entry in sortedByCenter.prefix(2) {
                if let labelIndex = nearestLabelIndex(to: entry.point) {
                    indices.insert(labelIndex)
                }
            }
        }

        return indices
    }

    static func cutoutCornerInfo(for piece: Piece, index: Int) -> (cutout: Cutout, corner: CutoutCornerPosition, localIndex: Int)? {
        for entry in cutoutCornerRanges(for: piece) {
            if entry.range.contains(index) {
                let localIndex = index - entry.range.lowerBound
                let corner = CutoutCornerPosition(rawValue: localIndex) ?? .topLeft
                return (entry.cutout, corner, localIndex)
            }
        }
        return nil
    }

    static func angleSegments(for piece: Piece) -> [AngleSegment] {
        let rawSize = pieceSize(for: piece)
        let referencePolygon = displayPolygonPointsForLabeling(for: piece, includeAngles: false)
        if piece.shape == .rectangle {
            let notches = notchCandidatesCurveAware(for: piece, size: rawSize)
            let result = angledRectanglePoints(
                size: rawSize,
                notches: notches,
                angleCuts: boundaryAngleCuts(for: piece),
                referencePolygon: referencePolygon
            )
            return result.segments.map { segment in
                AngleSegment(id: segment.id, start: displayPoint(fromRaw: segment.start), end: displayPoint(fromRaw: segment.end))
            }
        }
        if piece.shape == .rightTriangle {
            let notches = notchCandidatesCurveAware(for: piece, size: rawSize)
            let result = angledRightTrianglePoints(
                size: rawSize,
                notches: notches,
                angleCuts: boundaryAngleCuts(for: piece),
                referencePolygon: referencePolygon
            )
            return result.segments.map { segment in
                AngleSegment(id: segment.id, start: displayPoint(fromRaw: segment.start), end: displayPoint(fromRaw: segment.end))
            }
        }
        return []
    }

    private static func baseCornerPoints(for piece: Piece) -> [CGPoint] {
        let rawSize = pieceSize(for: piece)
        switch piece.shape {
        case .rectangle:
            let notches = notchCandidates(for: piece, size: rawSize)
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: [])
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        case .rightTriangle:
            let notches = notchCandidates(for: piece, size: rawSize)
            let result = angledRightTrianglePoints(size: rawSize, notches: notches, angleCuts: [])
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        default:
            return []
        }
    }

    static func cornerPoints(for piece: Piece, includeAngles: Bool = true, angleCutLimit: Int? = nil) -> [CGPoint] {
        let rawSize = pieceSize(for: piece)
        switch piece.shape {
        case .rectangle:
            let notches = notchCandidates(for: piece, size: rawSize)
            let angleCuts: [AngleCut]
            if includeAngles {
                if let limit = angleCutLimit {
                    angleCuts = Array(boundaryAngleCuts(for: piece).prefix(max(0, limit)))
                } else {
                    angleCuts = boundaryAngleCuts(for: piece)
                }
            } else {
                angleCuts = []
            }
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        case .rightTriangle:
            let notches = notchCandidates(for: piece, size: rawSize)
            let angleCuts: [AngleCut]
            if includeAngles {
                if let limit = angleCutLimit {
                    angleCuts = Array(boundaryAngleCuts(for: piece).prefix(max(0, limit)))
                } else {
                    angleCuts = boundaryAngleCuts(for: piece)
                }
            } else {
                angleCuts = []
            }
            let result = angledRightTrianglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        default:
            return []
        }
    }

    static func displayPolygonPoints(for piece: Piece, includeAngles: Bool = true, angleCutLimit: Int? = nil, includeNotches: Bool = true) -> [CGPoint] {
        let rawSize = pieceSize(for: piece)
        switch piece.shape {
        case .rectangle:
            let notches = includeNotches ? notchCandidates(for: piece, size: rawSize) : []
            let angleCuts: [AngleCut]
            if includeAngles {
                if let limit = angleCutLimit {
                    angleCuts = Array(boundaryAngleCuts(for: piece).prefix(max(0, limit)))
                } else {
                    angleCuts = boundaryAngleCuts(for: piece)
                }
            } else {
                angleCuts = []
            }
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        case .rightTriangle:
            let notches = includeNotches ? notchCandidates(for: piece, size: rawSize) : []
            let angleCuts: [AngleCut]
            if includeAngles {
                if let limit = angleCutLimit {
                    angleCuts = Array(boundaryAngleCuts(for: piece).prefix(max(0, limit)))
                } else {
                    angleCuts = boundaryAngleCuts(for: piece)
                }
            } else {
                angleCuts = []
            }
            let result = angledRightTrianglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        default:
            return []
        }
    }

    /// Curve-aware polygon points for labeling and corner counting.
    /// Labeling polygon: uses curve-aware notch candidates for correct classification,
    /// and defaults to the straight-edge boolean pipeline to avoid Path.subtracting
    /// artifacts that can produce near-duplicate vertices and extra labels.
    ///
    /// When a notch overlaps only the curved boundary (outside the straight-edge
    /// bounds), the straight-edge boolean cannot generate the perimeter indentation,
    /// so we switch to a curved labeling boolean for those cases.
    ///
    /// Cutouts fully inside the curved boundary (detected by cutoutFullyInsideBoundary)
    /// are excluded from the notch list and get their own 4 corner labels via
    /// interiorCutoutsCurveAware / cutoutCornerRanges. Cutouts that cross the curved
    /// boundary but remain inside the straight-edge boundary also get 4 interior
    /// labels (they don't produce notch vertices in the straight-edge polygon).
    static func displayPolygonPointsForLabeling(for piece: Piece, includeAngles: Bool = true) -> [CGPoint] {
        let rawSize = pieceSize(for: piece)
        let activeCurves = validCurves(for: piece)
        switch piece.shape {
        case .rectangle:
            let notches = notchCandidatesCurveAware(for: piece, size: rawSize)
            let angleCuts: [AngleCut]
            if includeAngles {
                angleCuts = boundaryAngleCuts(for: piece)
            } else {
                angleCuts = []
            }
            // Default to straight-edge boolean for labeling to avoid Path.subtracting artifacts.
            // If a notch only intersects the curved boundary, use the curved labeling boolean
            // so perimeter corners and label order stay correct.
            let needsCurvedLabeling = !activeCurves.isEmpty && notches.contains { cutout in
                cutoutOverlapsPiece(cutout: cutout, size: rawSize, shape: piece.shape, curves: activeCurves)
                    && !cutoutOverlapsPiece(cutout: cutout, size: rawSize, shape: piece.shape, curves: [])
            }
            let result = angledRectanglePoints(
                size: rawSize,
                notches: notches,
                angleCuts: angleCuts,
                curves: needsCurvedLabeling ? activeCurves : [],
                forLabeling: needsCurvedLabeling
            )
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        case .rightTriangle:
            let notches = notchCandidatesCurveAware(for: piece, size: rawSize)
            let angleCuts: [AngleCut]
            if includeAngles {
                angleCuts = boundaryAngleCuts(for: piece)
            } else {
                angleCuts = []
            }
            let needsCurvedLabeling = !activeCurves.isEmpty && notches.contains { cutout in
                cutoutOverlapsPiece(cutout: cutout, size: rawSize, shape: piece.shape, curves: activeCurves)
                    && !cutoutOverlapsPiece(cutout: cutout, size: rawSize, shape: piece.shape, curves: [])
            }
            let result = angledRightTrianglePoints(
                size: rawSize,
                notches: notches,
                angleCuts: angleCuts,
                curves: needsCurvedLabeling ? activeCurves : [],
                forLabeling: needsCurvedLabeling
            )
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        default:
            return []
        }
    }

    private static func notchRectanglePath(size: CGSize, notches: [Cutout]) -> Path {
        let points = notchRectanglePoints(size: size, notches: notches)
        return polygonPath(points)
    }

    private static func angledRectanglePath(size: CGSize, notches: [Cutout], angleCuts: [AngleCut]) -> Path {
        let result = angledRectanglePoints(size: size, notches: notches, angleCuts: angleCuts)
        return polygonPath(result.points)
    }

    private static func angledRightTrianglePath(size: CGSize, notches: [Cutout], angleCuts: [AngleCut]) -> Path {
        let result = angledRightTrianglePoints(size: size, notches: notches, angleCuts: angleCuts)
        return polygonPath(result.points)
    }

    private static func angledRectanglePoints(size: CGSize, notches: [Cutout], angleCuts: [AngleCut], curves: [CurvedEdge] = [], forLabeling: Bool = false, referencePolygon: [CGPoint]? = nil) -> (points: [CGPoint], segments: [AngleSegment]) {
        let base = rectanglePoints(size: size)
        let baseAfterNotches = basePolygonAfterNotches(base: base, size: size, shape: .rectangle, notches: notches, curves: curves, forLabeling: forLabeling)
        let points = applyAngleCutsToPolygon(polygon: baseAfterNotches, angleCuts: angleCuts, referencePolygon: referencePolygon)
        let segments = angleCutSegments(polygon: baseAfterNotches, angleCuts: angleCuts, referencePolygon: referencePolygon)
        return (points: points, segments: segments)
    }

    private static func angledRightTrianglePoints(size: CGSize, notches: [Cutout], angleCuts: [AngleCut], curves: [CurvedEdge] = [], forLabeling: Bool = false, referencePolygon: [CGPoint]? = nil) -> (points: [CGPoint], segments: [AngleSegment]) {
        let base = rightTrianglePoints(size: size)
        let baseAfterNotches = basePolygonAfterNotches(base: base, size: size, shape: .rightTriangle, notches: notches, curves: curves, forLabeling: forLabeling)
        let points = applyAngleCutsToPolygon(polygon: baseAfterNotches, angleCuts: angleCuts, referencePolygon: referencePolygon)
        let segments = angleCutSegments(polygon: baseAfterNotches, angleCuts: angleCuts, referencePolygon: referencePolygon)
        return (points: points, segments: segments)
    }

    private static func rectanglePoints(size: CGSize) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
    }

    private static func rightTrianglePoints(size: CGSize) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height)]
    }

    private static func basePolygonAfterNotches(
        base: [CGPoint],
        size: CGSize,
        shape: ShapeKind,
        notches: [Cutout],
        curves: [CurvedEdge] = [],
        forLabeling: Bool = false
    ) -> [CGPoint] {
        let clipPolygons = notchClipPolygons(notches: notches, size: size, shape: shape)
        guard !clipPolygons.isEmpty else { return base }

        let activeCurves = curves.filter { $0.radius > 0 }

        if forLabeling {
            // For labeling, we need the correct number of clean corner points
            // without curve-sampled intermediate points.
            //
            // When curves are active, use the curved boundary path for the boolean
            // so that cutouts in the curve bulge are correctly handled. The
            // extractCornersFromPath deduplication removes the near-duplicate points
            // that Path.subtracting produces at curve/line intersections.
            //
            // Without curves, use straight-edge boolean (faster, no Path artifacts).
            if !activeCurves.isEmpty {
                let displaySize = CGSize(width: size.height, height: size.width)
                let curvedSubjectPath = path(for: shape, size: displaySize, curves: activeCurves)
                let result = curvedBooleanDifferenceForLabeling(
                    subjectPath: curvedSubjectPath,
                    clips: clipPolygons
                )
                if !result.isEmpty {
                    return result
                }
                // Fallback to straight-edge if curved labeling boolean fails
            }
            return booleanDifference(subject: base, clips: clipPolygons)
        }

        // For rendering, use curve-aware boolean difference when curves are active.
        // This ensures cutouts positioned in the curved bulge are properly subtracted.
        if !activeCurves.isEmpty {
            let displaySize = CGSize(width: size.height, height: size.width)
            let curvedSubjectPath = path(for: shape, size: displaySize, curves: activeCurves)
            let result = curvedBooleanDifference(subjectPath: curvedSubjectPath, clips: clipPolygons)
            if !result.isEmpty {
                return result
            }
            // Fallback to straight-edge if curved boolean fails
        }

        return booleanDifference(subject: base, clips: clipPolygons)
    }

    private static func applyAngleCutsToPolygon(polygon: [CGPoint], angleCuts: [AngleCut], referencePolygon: [CGPoint]? = nil) -> [CGPoint] {
        guard !angleCuts.isEmpty, polygon.count >= 3 else { return polygon }
        let displayPolygon = polygon.map { displayPoint(fromRaw: $0) }
        let orderedDisplay = reorderCornersClockwise(displayPolygon)
        let cutDisplay = applyAngleCutsDisplay(to: orderedDisplay, angleCuts: angleCuts, referencePolygon: referencePolygon)
        let rawPoints = cutDisplay.map { rawPoint(fromDisplay: $0) }
        return dedupePoints(rawPoints)
    }

    private static func booleanBasePolygon(
        base: [CGPoint],
        size: CGSize,
        shape: ShapeKind,
        notches: [Cutout],
        angleCuts: [AngleCut]
    ) -> [CGPoint] {
        let baseAfterNotches = basePolygonAfterNotches(base: base, size: size, shape: shape, notches: notches)
        return applyAngleCutsToPolygon(polygon: baseAfterNotches, angleCuts: angleCuts)
    }

    private static func angleCutSegments(polygon: [CGPoint], angleCuts: [AngleCut], referencePolygon: [CGPoint]? = nil) -> [AngleSegment] {
        guard !angleCuts.isEmpty, polygon.count >= 3 else { return [] }
        let displayPolygon = reorderCornersClockwise(polygon.map { displayPoint(fromRaw: $0) })
        var segments: [AngleSegment] = []
        segments.reserveCapacity(angleCuts.count)
        for cut in angleCuts {
            if let segment = angleCutSegmentRaw(cut, polygonDisplay: displayPolygon, referencePolygon: referencePolygon) {
                segments.append(segment)
            }
        }
        return segments
    }

    private static func notchClipPolygons(notches: [Cutout], size: CGSize, shape: ShapeKind) -> [[CGPoint]] {
        guard !notches.isEmpty else { return [] }
        var clips: [[CGPoint]] = []
        clips.reserveCapacity(notches.count)
        for cutout in notches {
            guard cutout.kind != .circle else { continue }
            
            if shape == .rightTriangle && cutout.orientation == .custom {
                // For custom angle notches, calculate corners directly in raw coordinates.
                // This is similar to how .legs works, but with rotation applied.
                //
                // The cutout is stored in raw coordinates (centerX, centerY, width, height).
                // We just need to apply the custom angle rotation around the center.
                let corners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape)
                if corners.count >= 3 {
                    clips.append(corners)
                }
            } else {
                let corners = GeometryHelpers.cutoutCornerPoints(cutout: cutout, size: size, shape: shape)
                if corners.count >= 3 {
                    clips.append(corners)
                }
            }
        }
        return clips
    }

    private static func angleCutPolygonsRaw(
        polygon: [CGPoint],
        angleCuts: [AngleCut],
        polygonDisplay: [CGPoint]? = nil,
        referencePolygon: [CGPoint]? = nil
    ) -> [[CGPoint]] {
        guard !angleCuts.isEmpty, polygon.count >= 3 else { return [] }
        let displayPolygon = polygonDisplay ?? polygon.map { displayPoint(fromRaw: $0) }
        var clips: [[CGPoint]] = []
        clips.reserveCapacity(angleCuts.count)
        for cut in angleCuts {
            if let polygon = angleCutPolygonRaw(cut, polygonDisplay: displayPolygon, referencePolygon: referencePolygon) {
                clips.append(polygon)
            }
        }
        return clips
    }

    private static func angleCutPolygonRaw(_ cut: AngleCut, polygonDisplay: [CGPoint], referencePolygon: [CGPoint]? = nil) -> [CGPoint]? {
        let count = polygonDisplay.count
        guard count >= 3 else { return nil }
        let anchorIndex = resolvedAngleAnchorIndex(cut, polygonDisplay: polygonDisplay, referencePolygon: referencePolygon)
        let prevIndex = normalizedIndex(anchorIndex - 1, count: count)
        let nextIndex = normalizedIndex(anchorIndex + 1, count: count)
        let corner = polygonDisplay[anchorIndex]
        let prev = polygonDisplay[prevIndex]
        let next = polygonDisplay[nextIndex]
        let alongEdge1 = abs(cut.anchorOffset)
        let alongEdge2 = abs(cut.secondaryOffset)
        let toNext = unitVector(from: corner, to: next)
        let toPrev = unitVector(from: corner, to: prev)
        let lenNext = distance(corner, next)
        let lenPrev = distance(corner, prev)
        guard alongEdge1 <= lenNext, alongEdge2 <= lenPrev else { return nil }

        let p1 = CGPoint(x: corner.x + toNext.x * alongEdge1, y: corner.y + toNext.y * alongEdge1)
        let p2 = CGPoint(x: corner.x + toPrev.x * alongEdge2, y: corner.y + toPrev.y * alongEdge2)
        let apex = corner
        return [
            rawPoint(fromDisplay: apex),
            rawPoint(fromDisplay: p1),
            rawPoint(fromDisplay: p2)
        ]
    }

    private static func angleCutSegmentRaw(_ cut: AngleCut, polygonDisplay: [CGPoint], referencePolygon: [CGPoint]? = nil) -> AngleSegment? {
        let count = polygonDisplay.count
        guard count >= 3 else { return nil }
        let anchorIndex = resolvedAngleAnchorIndex(cut, polygonDisplay: polygonDisplay, referencePolygon: referencePolygon)
        let prevIndex = normalizedIndex(anchorIndex - 1, count: count)
        let nextIndex = normalizedIndex(anchorIndex + 1, count: count)
        let corner = polygonDisplay[anchorIndex]
        let prev = polygonDisplay[prevIndex]
        let next = polygonDisplay[nextIndex]
        let alongEdge1 = abs(cut.anchorOffset)
        let alongEdge2 = abs(cut.secondaryOffset)
        let toNext = unitVector(from: corner, to: next)
        let toPrev = unitVector(from: corner, to: prev)
        let lenNext = distance(corner, next)
        let lenPrev = distance(corner, prev)
        guard alongEdge1 <= lenNext, alongEdge2 <= lenPrev else { return nil }

        let p1 = CGPoint(x: corner.x + toNext.x * alongEdge1, y: corner.y + toNext.y * alongEdge1)
        let p2 = CGPoint(x: corner.x + toPrev.x * alongEdge2, y: corner.y + toPrev.y * alongEdge2)
        return AngleSegment(id: cut.id, start: rawPoint(fromDisplay: p2), end: rawPoint(fromDisplay: p1))
    }

    private static func resolvedAngleAnchorIndex(_ cut: AngleCut, polygonDisplay: [CGPoint], referencePolygon: [CGPoint]? = nil) -> Int {
        if let ref = referencePolygon, !ref.isEmpty {
            let refIdx = normalizedIndex(cut.anchorCornerIndex, count: ref.count)
            let refVertex = ref[refIdx]
            return nearestVertexIndex(to: refVertex, in: polygonDisplay)
        }
        return normalizedIndex(cut.anchorCornerIndex, count: polygonDisplay.count)
    }



    private static func booleanDifference(subject: [CGPoint], clips: [[CGPoint]]) -> [CGPoint] {
        guard subject.count >= 3 else { return subject }
        // Build subject path
        var subjectPath = Path()
        subjectPath.move(to: subject[0])
        for pt in subject.dropFirst() { subjectPath.addLine(to: pt) }
        subjectPath.closeSubpath()
        // Build combined clip path
        var clipPath = Path()
        for clip in clips where clip.count >= 3 {
            clipPath.move(to: clip[0])
            for pt in clip.dropFirst() { clipPath.addLine(to: pt) }
            clipPath.closeSubpath()
        }
        // Use SwiftUI Path.subtracting
        let result = subjectPath.subtracting(clipPath)
        // Extract the largest contour from the result
        var contours: [[CGPoint]] = []
        var current: [CGPoint] = []
        result.forEach { element in
            switch element {
            case .move(to: let pt):
                if current.count >= 3 { contours.append(current) }
                current = [pt]
            case .line(to: let pt):
                current.append(pt)
            case .closeSubpath:
                if current.count >= 3 { contours.append(current) }
                current = []
            default:
                break
            }
        }
        if current.count >= 3 { contours.append(current) }
        guard !contours.isEmpty else { return subject }
        let best = contours.max { abs(polygonArea($0)) < abs(polygonArea($1)) }
        return best ?? subject
    }

    /// Boolean difference using a curved path as the subject.
    /// This properly handles cutouts that are positioned within a convex curve's bulge
    /// (past the straight edge but still overlapping the curved boundary).
    private static func curvedBooleanDifference(
        subjectPath: Path,
        clips: [[CGPoint]]
    ) -> [CGPoint] {
        // Build combined clip path (in display coordinates)
        var clipPath = Path()
        for clip in clips where clip.count >= 3 {
            let displayClip = clip.map { displayPoint(fromRaw: $0) }
            clipPath.move(to: displayClip[0])
            for pt in displayClip.dropFirst() { clipPath.addLine(to: pt) }
            clipPath.closeSubpath()
        }
        
        // Use SwiftUI Path.subtracting
        let result = subjectPath.subtracting(clipPath)
        
        // Prefer non-sampled corner extraction to avoid curve sampling artifacts.
        let cornerContours = extractCornersFromPath(result)
        if !cornerContours.isEmpty {
            let best = cornerContours.max { abs(polygonArea($0)) < abs(polygonArea($1)) }
            return (best ?? []).map { rawPoint(fromDisplay: $0) }
        }
        // Fallback to sampled extraction when corner-only extraction fails.
        let displayContours = extractContoursFromPath(result)
        guard !displayContours.isEmpty else { return [] }
        let best = displayContours.max { abs(polygonArea($0)) < abs(polygonArea($1)) }
        return (best ?? []).map { rawPoint(fromDisplay: $0) }
    }
    
    /// Curved boolean difference that extracts only corner points (for labeling).
    /// Unlike curvedBooleanDifference, this does NOT sample curves - it only keeps
    /// line endpoints and curve endpoints, giving clean corner points for labels.
    private static func curvedBooleanDifferenceForLabeling(
        subjectPath: Path,
        clips: [[CGPoint]]
    ) -> [CGPoint] {
        // Build combined clip path (in display coordinates)
        var clipPath = Path()
        for clip in clips where clip.count >= 3 {
            let displayClip = clip.map { displayPoint(fromRaw: $0) }
            clipPath.move(to: displayClip[0])
            for pt in displayClip.dropFirst() { clipPath.addLine(to: pt) }
            clipPath.closeSubpath()
        }

        // Use SwiftUI Path.subtracting
        let result = subjectPath.subtracting(clipPath)

        // Extract only corner points (no curve sampling)
        let displayContours = extractCornersFromPath(result)
        guard !displayContours.isEmpty else { return [] }
        var corners = displayContours.max { abs(polygonArea($0)) < abs(polygonArea($1)) } ?? []
        guard !corners.isEmpty else { return [] }

        // Remove curve-junction artifacts.
        // Path.subtracting can emit a near-duplicate vertex close to a curve
        // start/end point (rectangle corner).  The artifact has a gentle bend
        // angle (~5-20°) while the real corner bends sharply (~90°).
        // For each curve endpoint, if multiple extracted corners are nearby,
        // keep the one with the largest bend angle (the real corner) and
        // discard the rest.  This is robust even when Path.subtracting
        // shifts the real corner position away from the mathematical endpoint.
        let curveSegments = extractQuadCurves(from: subjectPath)
        if !curveSegments.isEmpty {
            var uniqueEndpoints: [CGPoint] = []
            for seg in curveSegments {
                for ep in [seg.start, seg.end] {
                    if !uniqueEndpoints.contains(where: { hypot($0.x - ep.x, $0.y - ep.y) < 0.5 }) {
                        uniqueEndpoints.append(ep)
                    }
                }
            }
            let nearRadius: CGFloat = 5.0
            var indicesToRemove = Set<Int>()
            let m = corners.count
            for ep in uniqueEndpoints {
                var nearby: [(index: Int, bendSin: CGFloat)] = []
                for (i, corner) in corners.enumerated() {
                    let d = hypot(corner.x - ep.x, corner.y - ep.y)
                    if d < nearRadius {
                        let prev = corners[(i - 1 + m) % m]
                        let next = corners[(i + 1) % m]
                        let v1x = corner.x - prev.x, v1y = corner.y - prev.y
                        let v2x = next.x - corner.x, v2y = next.y - corner.y
                        let cross = abs(v1x * v2y - v1y * v2x)
                        let len1 = sqrt(v1x * v1x + v1y * v1y)
                        let len2 = sqrt(v2x * v2x + v2y * v2y)
                        let denom = len1 * len2
                        let sinA = denom > 0.0001 ? cross / denom : 0.0
                        nearby.append((i, sinA))
                    }
                }
                if nearby.count > 1 {
                        // Only remove clear outliers: vertices whose bend angle
                    // is less than half the second-smallest bend in the group.
                    // This targets the single artifact without touching real corners.
                    nearby.sort { $0.bendSin < $1.bendSin }
                    let secondSmallest = nearby.count >= 2 ? nearby[1].bendSin : nearby[0].bendSin
                    let outlierThreshold = secondSmallest * 0.5
                    for entry in nearby where entry.bendSin < outlierThreshold {
                        indicesToRemove.insert(entry.index)
                    }
                }
            }
            if !indicesToRemove.isEmpty {
                corners = corners.enumerated().compactMap {
                    indicesToRemove.contains($0.offset) ? nil : $0.element
                }
            }
        }

        // Convert back to raw coordinates
        return corners.map { rawPoint(fromDisplay: $0) }
    }

    /// Extract quadratic Bézier segments (start, control, end) from a Path.
    private static func extractQuadCurves(from path: Path) -> [(start: CGPoint, control: CGPoint, end: CGPoint)] {
        var curves: [(start: CGPoint, control: CGPoint, end: CGPoint)] = []
        var currentPoint: CGPoint = .zero
        path.forEach { element in
            switch element {
            case .move(to: let pt):
                currentPoint = pt
            case .line(to: let pt):
                currentPoint = pt
            case .quadCurve(to: let end, control: let control):
                curves.append((start: currentPoint, control: control, end: end))
                currentPoint = end
            case .curve(to: let end, control1: _, control2: _):
                currentPoint = end
            case .closeSubpath:
                break
            }
        }
        return curves
    }

    
    /// Extracts polygon contours from a Path, sampling curves into line segments
    private static func extractContoursFromPath(_ path: Path) -> [[CGPoint]] {
        var contours: [[CGPoint]] = []
        var current: [CGPoint] = []
        var lastPoint: CGPoint?
        
        path.forEach { element in
            processPathElement(element, contours: &contours, current: &current, lastPoint: &lastPoint)
        }
        if current.count >= 3 { contours.append(current) }
        return contours
    }
    
    /// Extracts only corner points from a Path (line endpoints), skipping curve samples.
    /// This is used for labeling where we only want significant corners, not curve approximations.
    /// Deduplicates adjacent near-duplicate points that Path.subtracting can produce
    /// at curve/line intersections.
    private static func extractCornersFromPath(_ path: Path) -> [[CGPoint]] {
        var contours: [[CGPoint]] = []
        var current: [CGPoint] = []

        path.forEach { element in
            switch element {
            case .move(to: let pt):
                if current.count >= 3 { contours.append(current) }
                current = [pt]
            case .line(to: let pt):
                current.append(pt)
            case .quadCurve(to: let end, control: _):
                current.append(end)
            case .curve(to: let end, control1: _, control2: _):
                current.append(end)
            case .closeSubpath:
                if current.count >= 3 { contours.append(current) }
                current = []
            }
        }
        if current.count >= 3 { contours.append(current) }

        // Deduplicate adjacent near-duplicate points.
        // Path.subtracting produces near-duplicate points at curve/line
        // intersections (e.g., quadCurve end ≈ next line start). Without
        // deduplication these cause extra corner labels (C and D at same spot).
        let dupTolerance: CGFloat = 1.0
        return contours.map { contour in
            guard contour.count > 1 else { return contour }
            var deduped: [CGPoint] = [contour[0]]
            for i in 1..<contour.count {
                let prev = deduped.last!
                let pt = contour[i]
                if abs(pt.x - prev.x) > dupTolerance || abs(pt.y - prev.y) > dupTolerance {
                    deduped.append(pt)
                }
            }
            // Also check wrap-around: last point vs first point
            if deduped.count > 1,
               let first = deduped.first, let last = deduped.last,
               abs(first.x - last.x) <= dupTolerance && abs(first.y - last.y) <= dupTolerance {
                deduped.removeLast()
            }

            // Remove collinear points — transition points between curve segments
            // and straight segments on the same edge that are not real corners.
            // When multiple curves exist per edge, addEdge produces
            // straight→curve→straight→curve→straight, and each transition endpoint
            // lands on the original edge line. These are collinear with their
            // neighbors and should not be labeled as corners.
            guard deduped.count > 3 else { return deduped }
            var filtered: [CGPoint] = []
            let n = deduped.count
            for i in 0..<n {
                let prev = deduped[(i - 1 + n) % n]
                let curr = deduped[i]
                let next = deduped[(i + 1) % n]

                // Cross product of (curr-prev) × (next-curr) measures how much
                // the path bends at curr.  If ≈ 0 the three points are collinear
                // and curr is not a real corner.
                let v1x = curr.x - prev.x
                let v1y = curr.y - prev.y
                let v2x = next.x - curr.x
                let v2y = next.y - curr.y
                let cross = abs(v1x * v2y - v1y * v2x)

                // Normalise by the product of the two segment lengths so the
                // threshold is scale-independent (it approximates sin(angle)).
                let len1 = sqrt(v1x * v1x + v1y * v1y)
                let len2 = sqrt(v2x * v2x + v2y * v2y)
                let denom = len1 * len2
                let sinAngle = denom > 0.0001 ? cross / denom : 1.0

                // sin(5°) ≈ 0.087 — anything below this is effectively collinear
                if sinAngle > 0.087 {
                    filtered.append(curr)
                }
            }
            return filtered.count >= 3 ? filtered : deduped
        }
    }
    
    /// Process a single path element for contour extraction
    private static func processPathElement(
        _ element: Path.Element,
        contours: inout [[CGPoint]],
        current: inout [CGPoint],
        lastPoint: inout CGPoint?
    ) {
        switch element {
        case .move(to: let pt):
            if current.count >= 3 { contours.append(current) }
            current = [pt]
            lastPoint = pt
        case .line(to: let pt):
            current.append(pt)
            lastPoint = pt
        case .quadCurve(to: let end, control: let control):
            sampleQuadCurve(start: lastPoint, control: control, end: end, into: &current)
            lastPoint = end
        case .curve(to: let end, control1: let c1, control2: let c2):
            sampleCubicCurve(start: lastPoint, c1: c1, c2: c2, end: end, into: &current)
            lastPoint = end
        case .closeSubpath:
            if current.count >= 3 { contours.append(current) }
            current = []
            lastPoint = nil
        }
    }
    
    /// Sample a quadratic Bezier curve into line segments
    private static func sampleQuadCurve(start: CGPoint?, control: CGPoint, end: CGPoint, into points: inout [CGPoint]) {
        guard let start = start else {
            points.append(end)
            return
        }
        let sampleCount = 8
        for i in 1...sampleCount {
            let t = CGFloat(i) / CGFloat(sampleCount)
            let pt = GeometryHelpers.quadBezierPoint(t: t, start: start, control: control, end: end)
            points.append(pt)
        }
    }
    
    /// Sample a cubic Bezier curve into line segments
    private static func sampleCubicCurve(start: CGPoint?, c1: CGPoint, c2: CGPoint, end: CGPoint, into points: inout [CGPoint]) {
        guard let start = start else {
            points.append(end)
            return
        }
        let sampleCount = 8
        for i in 1...sampleCount {
            let t = CGFloat(i) / CGFloat(sampleCount)
            let pt = cubicBezierPoint(t: t, p0: start, p1: c1, p2: c2, p3: end)
            points.append(pt)
        }
    }
    
    /// Calculate point on cubic Bezier curve
    private static func cubicBezierPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let oneMinusT = 1 - t
        let t2 = t * t
        let t3 = t2 * t
        let oneMinusT2 = oneMinusT * oneMinusT
        let oneMinusT3 = oneMinusT2 * oneMinusT
        
        let x = oneMinusT3 * p0.x + 3 * oneMinusT2 * t * p1.x + 3 * oneMinusT * t2 * p2.x + t3 * p3.x
        let y = oneMinusT3 * p0.y + 3 * oneMinusT2 * t * p1.y + 3 * oneMinusT * t2 * p2.y + t3 * p3.y
        return CGPoint(x: x, y: y)
    }

    private static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var area: CGFloat = 0
        for index in 0..<points.count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            area += (a.x * b.y) - (b.x * a.y)
        }
        return area / 2
    }

    private static func notchRightTrianglePoints(size: CGSize, notches: [Cutout]) -> [CGPoint] {
        let width = size.width
        let height = size.height
        let edgeEpsilon: CGFloat = 0.5

        var topLeftMaxX: CGFloat = 0
        var topLeftMaxY: CGFloat = 0
        var topSpans: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        var leftSpans: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        // Store hypotenuse notches with their t-values and axis-aligned rect bounds
        var hypotenuseSpans: [(tStart: CGFloat, tEnd: CGFloat, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)] = []
        
        // Track notches that touch top edge + hypotenuse (corner cut towards top-right)
        // These modify where the top edge ends and where the hypotenuse starts
        var topHypotenuseCornerMinX: CGFloat = width  // leftmost X of top+hypotenuse notch (limits top edge)
        var topHypotenuseCornerIntersectY: CGFloat = 0 // Y where notch meets hypotenuse
        var topHypotenuseCornerIntersectX: CGFloat = width // X where notch meets hypotenuse
        var hasTopHypotenuseCorner = false
        var topHypotenuseCornerIsClip = false
        
        // Track notches that touch left edge + hypotenuse (corner cut towards bottom-left)
        // These modify where the left edge starts (from bottom) and where the hypotenuse ends
        var leftHypotenuseCornerEdgeY: CGFloat = height  // Y where notch meets left edge (limits left edge)
        var leftHypotenuseCornerIntersectX: CGFloat = 0  // X where notch meets hypotenuse
        var leftHypotenuseCornerIntersectY: CGFloat = height // Y where notch meets hypotenuse
        var hasLeftHypotenuseCorner = false
        var leftHypotenuseCornerIsClip = false

        for notch in notches {
            let corners = GeometryHelpers.cutoutCornerPoints(cutout: notch, size: size, shape: .rightTriangle)
            let bounds = GeometryHelpers.bounds(for: corners)
            var minX = bounds.minX
            var maxX = bounds.maxX
            var minY = bounds.minY
            var maxY = bounds.maxY

            if minX <= edgeEpsilon { minX = 0 }
            if minY <= edgeEpsilon { minY = 0 }
            if maxX >= width - edgeEpsilon { maxX = width }
            if maxY >= height - edgeEpsilon { maxY = height }

            let touchesTop = minY <= edgeEpsilon
            let touchesLeft = minX <= edgeEpsilon
            let touchesHypotenuse = cutoutTouchesHypotenuse(
                corners: corners,
                size: size,
                eps: edgeEpsilon
            )

            var minValue = CGFloat.greatestFiniteMagnitude
            var maxValue = -CGFloat.greatestFiniteMagnitude
            var anyCornerInside = false
            for corner in corners {
                let value = (corner.x / max(width, 0.0001)) + (corner.y / max(height, 0.0001)) - 1
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
                if value < -0.0001, corner.x >= -0.001, corner.y >= -0.001 {
                    anyCornerInside = true
                }
            }
            let spansHypotenuse = minValue < -0.0001 && maxValue > 0.0001
            let touchesTopWithinBounds = touchesTop && minX < width - edgeEpsilon
            let touchesLeftWithinBounds = touchesLeft && minY < height - edgeEpsilon
            if !(anyCornerInside || spansHypotenuse || touchesTopWithinBounds || touchesLeftWithinBounds) {
                continue
            }

            if touchesTop && touchesLeft {
                topLeftMaxX = max(topLeftMaxX, maxX)
                topLeftMaxY = max(topLeftMaxY, maxY)
            }
            
            // Handle top + hypotenuse corner: notch touches top edge and hypotenuse (but not left edge)
            // This creates a corner cut between the top edge and hypotenuse
            // Only process .hypotenuse orientation notches - .legs and .custom should keep rectangular shape
            if touchesTop && touchesHypotenuse && !touchesLeft && notch.orientation == .hypotenuse {
                topHypotenuseCornerMinX = min(topHypotenuseCornerMinX, minX)
                let yAtMinX = height * (1 - minX / max(width, 0.0001))
                if yAtMinX < maxY - edgeEpsilon {
                    // Hypotenuse intersects above the notch bottom; treat as a clipped corner.
                    topHypotenuseCornerIsClip = true
                    topHypotenuseCornerIntersectX = min(topHypotenuseCornerIntersectX, minX)
                    topHypotenuseCornerIntersectY = max(topHypotenuseCornerIntersectY, yAtMinX)
                } else {
                    let intersectY = maxY
                    let intersectX = width * (1 - intersectY / max(height, 0.0001))
                    topHypotenuseCornerIntersectX = min(topHypotenuseCornerIntersectX, intersectX)
                    topHypotenuseCornerIntersectY = max(topHypotenuseCornerIntersectY, intersectY)
                }
                hasTopHypotenuseCorner = true
                continue
            }
            
            // Handle left + hypotenuse corner: notch touches left edge and hypotenuse (but not top edge)
            // This creates a corner cut between the left edge and hypotenuse
            // Only process .hypotenuse orientation notches - .legs and .custom should keep rectangular shape
            if touchesLeft && touchesHypotenuse && !touchesTop && notch.orientation == .hypotenuse {
                leftHypotenuseCornerEdgeY = min(leftHypotenuseCornerEdgeY, minY)
                let xAtMinY = width * (1 - minY / max(height, 0.0001))
                if xAtMinY < maxX - edgeEpsilon {
                    // Hypotenuse intersects left of the notch right edge; treat as a clipped corner.
                    leftHypotenuseCornerIsClip = true
                    leftHypotenuseCornerIntersectX = max(leftHypotenuseCornerIntersectX, xAtMinY)
                    leftHypotenuseCornerIntersectY = min(leftHypotenuseCornerIntersectY, minY)
                } else {
                    let intersectX = maxX
                    let intersectY = height * (1 - intersectX / max(width, 0.0001))
                    leftHypotenuseCornerIntersectX = max(leftHypotenuseCornerIntersectX, intersectX)
                    leftHypotenuseCornerIntersectY = min(leftHypotenuseCornerIntersectY, intersectY)
                }
                hasLeftHypotenuseCorner = true
                continue
            }
            
            let touchesCount = [touchesTop, touchesLeft, touchesHypotenuse].filter { $0 }.count
            
            if touchesCount == 1 {
                if touchesTop {
                    let depth = maxY
                    if depth > 0 && minX < maxX { topSpans.append((start: minX, end: maxX, depth: depth)) }
                } else if touchesLeft {
                    let depth = maxX
                    if depth > 0 && minY < maxY { leftSpans.append((start: minY, end: maxY, depth: depth)) }
                } else if touchesHypotenuse {
                    // Only process notches with .hypotenuse orientation through the hypotenuse
                    // axis-aligned path. Notches with .legs or .custom orientation should keep
                    // their rectangular shape and be handled by the boolean difference approach
                    // in notchClipPolygons, not stretched toward the hypotenuse angle.
                    if notch.orientation != .hypotenuse {
                        continue
                    }
                    if let span = cutoutHypotenuseSpan(minX: minX, maxX: maxX, minY: minY, maxY: maxY, size: size) {
                        hypotenuseSpans.append((tStart: span.start, tEnd: span.end, minX: span.minX, maxX: span.maxX, minY: span.minY, maxY: span.maxY))
                    }
                }
            }
        }

        let hasTopLeft = topLeftMaxX > 0 && topLeftMaxY > 0
        let mergedTop = mergeEdgeSpans(topSpans)
        let mergedLeft = mergeEdgeSpans(leftSpans)
        // Sort hypotenuse spans by t-value (0 = top-right corner, 1 = bottom-left corner)
        let orderedHypotenuseSpans = hypotenuseSpans.sorted { $0.tStart < $1.tStart }

        let hypotenuseStart = CGPoint(x: width, y: 0)
        let hypotenuseEnd = CGPoint(x: 0, y: height)
        
        // Calculate where the hypotenuse actually starts and ends (accounting for corner cuts)
        // The t-value represents position along hypotenuse: 0 = top-right corner (width, 0), 1 = bottom-left corner (0, height)
        var hypotenuseStartT: CGFloat = 0
        if hasTopHypotenuseCorner {
            // For top+hypotenuse corner, calculate t where the notch depth meets the hypotenuse
            // The hypotenuse Y at a given X is: y = height * (1 - x/width)
            // We want the t-value where y = topHypotenuseCornerIntersectY
            hypotenuseStartT = topHypotenuseCornerIntersectY / height
        }
        
        var hypotenuseEndT: CGFloat = 1
        if hasLeftHypotenuseCorner {
            // For left+hypotenuse corner, calculate t where the notch depth meets the hypotenuse
            hypotenuseEndT = leftHypotenuseCornerIntersectY / height
        }

        var points: [CGPoint] = []
        let startX = hasTopLeft ? topLeftMaxX : 0
        points.append(CGPoint(x: startX, y: 0))

        // The effective end of the top edge (before top+hypotenuse corner)
        var topEdgeEndX: CGFloat = width
        if hasTopHypotenuseCorner {
            topEdgeEndX = topHypotenuseCornerMinX
        }

        for span in mergedTop {
            let clampedStart = max(span.start, startX)
            let clampedEnd = min(span.end, topEdgeEndX)
            if clampedEnd <= clampedStart { continue }
            if points.last?.x ?? 0 < clampedStart {
                points.append(CGPoint(x: clampedStart, y: 0))
            }
            points.append(CGPoint(x: clampedStart, y: span.depth))
            points.append(CGPoint(x: clampedEnd, y: span.depth))
            points.append(CGPoint(x: clampedEnd, y: 0))
        }
        
        // End the top edge and transition to hypotenuse
        if hasTopHypotenuseCorner {
            // Go to where the top edge ends, then down, then right to the hypotenuse
            // Path: (topHypotenuseCornerMinX, 0) -> (topHypotenuseCornerMinX, intersectY) -> (point on hypotenuse)
            if points.last?.x ?? 0 < topHypotenuseCornerMinX {
                points.append(CGPoint(x: topHypotenuseCornerMinX, y: 0))
            }
            if !topHypotenuseCornerIsClip {
                // Go down to the notch depth for a stepped notch.
                points.append(CGPoint(x: topHypotenuseCornerMinX, y: topHypotenuseCornerIntersectY))
            }
            // Go to where the hypotenuse intersects the notch rectangle (clip or notch)
            points.append(CGPoint(x: topHypotenuseCornerIntersectX, y: topHypotenuseCornerIntersectY))
        } else {
            points.append(CGPoint(x: width, y: 0))
        }

        // Walk along the hypotenuse, inserting notch paths at the right positions
        // Start from hypotenuseStartT (which accounts for top-right corner cut)
        var currentT: CGFloat = hypotenuseStartT
        for span in orderedHypotenuseSpans {
            // Skip spans that are entirely before the hypotenuse start or after the end (covered by corner cuts)
            if span.tEnd <= hypotenuseStartT { continue }
            if span.tStart >= hypotenuseEndT { continue }
            
            // Clamp span to the effective hypotenuse range
            let effectiveSpanStart = max(span.tStart, hypotenuseStartT)
            let effectiveSpanEnd = min(span.tEnd, hypotenuseEndT)
            
            // If there's a gap before this notch, add the hypotenuse point at the notch entry
            if effectiveSpanStart > currentT + 0.0001 {
                let entryPoint = pointOnHypotenuse(start: hypotenuseStart, end: hypotenuseEnd, t: effectiveSpanStart)
                if let last = points.last, GeometryHelpers.distance(last, entryPoint) > 0.001 {
                    points.append(entryPoint)
                }
            }
            
            // Add the axis-aligned notch path (going into the triangle)
            let notchPath = axisAlignedHypotenuseNotchPath(
                tStart: effectiveSpanStart,
                tEnd: effectiveSpanEnd,
                minX: span.minX,
                maxX: span.maxX,
                minY: span.minY,
                maxY: span.maxY,
                size: size
            )
            for point in notchPath {
                if let last = points.last, GeometryHelpers.distance(last, point) > 0.001 {
                    points.append(point)
                }
            }
            
            currentT = effectiveSpanEnd
        }
        
        // Add the final hypotenuse endpoint or corner cut point
        if hasLeftHypotenuseCorner {
            // Go from hypotenuse to the corner point, then down to where the left edge starts
            let hypEntryPoint = CGPoint(x: leftHypotenuseCornerIntersectX, y: leftHypotenuseCornerIntersectY)
            if let last = points.last, GeometryHelpers.distance(last, hypEntryPoint) > 0.001 {
                points.append(hypEntryPoint)
            }
            if leftHypotenuseCornerIsClip {
                points.append(CGPoint(x: 0, y: height))
            } else {
                // Go down to the notch top edge
                points.append(CGPoint(x: leftHypotenuseCornerIntersectX, y: leftHypotenuseCornerEdgeY))
                // Go left to the left edge
                points.append(CGPoint(x: 0, y: leftHypotenuseCornerEdgeY))
            }
        } else {
            let finalPoint = CGPoint(x: 0, y: height)
            if let last = points.last, GeometryHelpers.distance(last, finalPoint) > 0.001 {
                points.append(finalPoint)
            }
        }

        // The effective top of the left edge (after left+hypotenuse corner)
        var leftEdgeStartY: CGFloat = height
        if hasLeftHypotenuseCorner {
            leftEdgeStartY = leftHypotenuseCornerEdgeY
        }
        let leftUpY = hasTopLeft ? topLeftMaxY : 0
        
        // First, go along the left edge from the corner cut (or bottom) upward
        // Note: for hasLeftHypotenuseCorner, we already added (0, leftHypotenuseCornerEdgeY) above
        
        for span in mergedLeft.reversed() {
            let clampedStart = max(span.start, leftUpY)
            let clampedEnd = min(span.end, leftEdgeStartY)
            if clampedEnd <= clampedStart { continue }
            if points.last?.y ?? height > clampedEnd {
                points.append(CGPoint(x: 0, y: clampedEnd))
            }
            points.append(CGPoint(x: span.depth, y: clampedEnd))
            points.append(CGPoint(x: span.depth, y: clampedStart))
            points.append(CGPoint(x: 0, y: clampedStart))
        }
        points.append(CGPoint(x: 0, y: leftUpY))
        if hasTopLeft {
            points.append(CGPoint(x: topLeftMaxX, y: topLeftMaxY))
            points.append(CGPoint(x: topLeftMaxX, y: 0))
        } else {
            points.append(CGPoint(x: 0, y: 0))
        }

        return dedupePoints(points)
    }
    
    /// Creates an axis-aligned rectangular notch path for a hypotenuse notch.
    /// The path goes from the entry point on the hypotenuse, into the triangle along the notch rectangle,
    /// and back out to the exit point on the hypotenuse.
    ///
    /// The hypotenuse runs from (width, 0) to (0, height). A notch rectangle intersects this line,
    /// and we need to carve along the rectangle edges to create an axis-aligned rectangular bite.
    private static func axisAlignedHypotenuseNotchPath(
        tStart: CGFloat,
        tEnd: CGFloat,
        minX: CGFloat,
        maxX: CGFloat,
        minY: CGFloat,
        maxY: CGFloat,
        size: CGSize
    ) -> [CGPoint] {
        let width = max(size.width, 0.0001)
        let height = max(size.height, 0.0001)
        let hypotenuseStart = CGPoint(x: width, y: 0)
        let hypotenuseEnd = CGPoint(x: 0, y: height)
        
        // Calculate entry and exit points on the hypotenuse
        let hypPoint1 = pointOnHypotenuse(start: hypotenuseStart, end: hypotenuseEnd, t: tStart)
        let hypPoint2 = pointOnHypotenuse(start: hypotenuseStart, end: hypotenuseEnd, t: tEnd)
        
        // Check if a point is inside or on the triangle boundary
        func isInsideOrOnTriangle(_ p: CGPoint) -> Bool {
            (p.x / width) + (p.y / height) <= 1.0 + 0.001
        }
        
        // Rectangle corners
        let topLeft = CGPoint(x: minX, y: minY)
        let topRight = CGPoint(x: maxX, y: minY)
        let bottomLeft = CGPoint(x: minX, y: maxY)
        
        // Check which corners are inside the triangle
        let topLeftInside = isInsideOrOnTriangle(topLeft)
        let topRightInside = isInsideOrOnTriangle(topRight)
        let bottomLeftInside = isInsideOrOnTriangle(bottomLeft)
        
        var path: [CGPoint] = [hypPoint1]
        
        // For an axis-aligned rectangular notch, we need to trace from hypPoint1
        // around the interior of the rectangle to hypPoint2.
        // Only include corners that are inside the triangle.
        //
        // The hypotenuse passes through the rectangle, and we need to trace
        // the edges that are INSIDE the triangle (the "notch" part).
        
        // Determine which edge hypPoint1 is on
        let onTopEdge1 = abs(hypPoint1.y - minY) < 0.5
        let onRightEdge1 = abs(hypPoint1.x - maxX) < 0.5
        
        // Determine which edge hypPoint2 is on
        let onBottomEdge2 = abs(hypPoint2.y - maxY) < 0.5
        let onLeftEdge2 = abs(hypPoint2.x - minX) < 0.5
        
        // Build the path by going from hypPoint1 toward interior, then to hypPoint2
        // Only add corners that are inside the triangle
        
        if onTopEdge1 {
            // Enter from top edge - go to top-left corner (if inside)
            if topLeftInside {
                path.append(topLeft)
            }
            if (onBottomEdge2 || onLeftEdge2) && bottomLeftInside {
                // Need to go to bottom-left corner
                path.append(bottomLeft)
            }
        } else if onRightEdge1 {
            // Enter from right edge
            // Only go to top-right corner if it's inside the triangle
            if topRightInside {
                path.append(topRight)
            }
            // Go to top-left corner (if inside)
            if topLeftInside {
                path.append(topLeft)
            }
            // Go to bottom-left corner (if inside)
            if bottomLeftInside {
                path.append(bottomLeft)
            }
        } else {
            // Fallback - use interior path through corners that are inside
            if topLeftInside {
                path.append(topLeft)
            }
            if bottomLeftInside {
                path.append(bottomLeft)
            }
        }
        
        path.append(hypPoint2)
        
        return path
    }

    private static func hypotenuseNotchPath(rect: CGRect, size: CGSize) -> (tStart: CGFloat, tEnd: CGFloat, entry: CGPoint, exit: CGPoint, path: [CGPoint])? {
        let width = max(size.width, 0.0001)
        let height = max(size.height, 0.0001)

        func isInsideTriangle(_ point: CGPoint) -> Bool {
            if point.x < -0.01 || point.y < -0.01 { return false }
            return (point.x / width) + (point.y / height) <= 1.0 + 0.01
        }

        func clipPolygon(_ polygon: [CGPoint], inside: (CGPoint) -> Bool, intersect: (CGPoint, CGPoint) -> CGPoint) -> [CGPoint] {
            guard !polygon.isEmpty else { return [] }
            var output: [CGPoint] = []
            var prev = polygon.last!
            var prevInside = inside(prev)
            for point in polygon {
                let currInside = inside(point)
                if currInside {
                    if !prevInside {
                        output.append(intersect(prev, point))
                    }
                    output.append(point)
                } else if prevInside {
                    output.append(intersect(prev, point))
                }
                prev = point
                prevInside = currInside
            }
            return dedupePoints(output)
        }

        func intersectLine(_ a: CGPoint, _ b: CGPoint, _ valueA: CGFloat, _ valueB: CGFloat) -> CGPoint {
            let t = valueA / (valueA - valueB)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        let rectPoly = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]

        var clipped = rectPoly
        clipped = clipPolygon(clipped, inside: { $0.x >= 0 }, intersect: { a, b in
            let t = (0 - a.x) / (b.x - a.x)
            return CGPoint(x: 0, y: a.y + (b.y - a.y) * t)
        })
        clipped = clipPolygon(clipped, inside: { $0.y >= 0 }, intersect: { a, b in
            let t = (0 - a.y) / (b.y - a.y)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: 0)
        })
        clipped = clipPolygon(clipped, inside: { point in (point.x / width) + (point.y / height) <= 1.0 + 0.0001 }, intersect: { a, b in
            let va = (a.x / width) + (a.y / height) - 1.0
            let vb = (b.x / width) + (b.y / height) - 1.0
            return intersectLine(a, b, va, vb)
        })

        guard clipped.count >= 3 else { return nil }

        func isOnHypotenuse(_ point: CGPoint) -> Bool {
            abs((point.x / width) + (point.y / height) - 1.0) <= 0.001
        }

        let hypotenusePoints = clipped.filter { isOnHypotenuse($0) }
        guard hypotenusePoints.count >= 2 else { return nil }

        func tValue(for point: CGPoint) -> CGFloat {
            (width - point.x) / width
        }

        let sorted = hypotenusePoints.sorted { tValue(for: $0) < tValue(for: $1) }
        let entry = sorted.first!
        let exit = sorted.last!
        let tStart = tValue(for: entry)
        let tEnd = tValue(for: exit)

        let entryIndex = GeometryHelpers.nearestPointIndex(to: entry, in: clipped)
        let exitIndex = GeometryHelpers.nearestPointIndex(to: exit, in: clipped)

        func pathBetween(_ points: [CGPoint], from start: Int, to end: Int, forward: Bool) -> [CGPoint] {
            var path: [CGPoint] = []
            let count = points.count
            var index = start
            while index != end {
                index = forward ? (index + 1) % count : (index - 1 + count) % count
                path.append(points[index])
            }
            return path
        }

        func pathIncludesHypotenuseEdge(_ path: [CGPoint]) -> Bool {
            guard path.count >= 2 else { return false }
            for i in 0..<(path.count - 1) {
                if isOnHypotenuse(path[i]) && isOnHypotenuse(path[i + 1]) {
                    return true
                }
            }
            return false
        }

        let forwardPath = pathBetween(clipped, from: entryIndex, to: exitIndex, forward: true)
        let backwardPath = pathBetween(clipped, from: entryIndex, to: exitIndex, forward: false)

        let forwardHasHyp = pathIncludesHypotenuseEdge(forwardPath)
        let backwardHasHyp = pathIncludesHypotenuseEdge(backwardPath)

        let chosen: [CGPoint]
        if forwardHasHyp && !backwardHasHyp {
            chosen = backwardPath
        } else if backwardHasHyp && !forwardHasHyp {
            chosen = forwardPath
        } else {
            chosen = forwardPath.count <= backwardPath.count ? forwardPath : backwardPath
        }

        var interiorPath = chosen.filter { GeometryHelpers.distance($0, entry) > 0.0001 && GeometryHelpers.distance($0, exit) > 0.0001 }
        interiorPath = dedupePoints(interiorPath)
        guard !interiorPath.isEmpty else { return nil }
        return (tStart: tStart, tEnd: tEnd, entry: entry, exit: exit, path: interiorPath)
    }

    private enum RectEdge: Int, CaseIterable {
        case top = 0
        case right = 1
        case bottom = 2
        case left = 3
    }

    private static func rectEdge(for point: CGPoint, rect: CGRect) -> RectEdge? {
        if abs(point.y - rect.minY) < 0.001 { return .top }
        if abs(point.x - rect.maxX) < 0.001 { return .right }
        if abs(point.y - rect.maxY) < 0.001 { return .bottom }
        if abs(point.x - rect.minX) < 0.001 { return .left }
        return nil
    }

    private static func rectBoundaryPath(
        from entry: CGPoint,
        entryEdge: RectEdge,
        to exit: CGPoint,
        exitEdge: RectEdge,
        rect: CGRect,
        polygon: [CGPoint]
    ) -> [CGPoint] {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]

        func edgeEndCorner(for edge: RectEdge, clockwise: Bool) -> CGPoint {
            switch (edge, clockwise) {
            case (.top, true): return corners[1]
            case (.top, false): return corners[0]
            case (.right, true): return corners[2]
            case (.right, false): return corners[1]
            case (.bottom, true): return corners[3]
            case (.bottom, false): return corners[2]
            case (.left, true): return corners[0]
            case (.left, false): return corners[3]
            }
        }

        func nextEdge(_ edge: RectEdge, clockwise: Bool) -> RectEdge {
            let delta = clockwise ? 1 : 3
            return RectEdge(rawValue: (edge.rawValue + delta) % 4) ?? edge
        }

        func buildPath(clockwise: Bool) -> [CGPoint] {
            var path: [CGPoint] = []
            var edge = entryEdge
            path.append(edgeEndCorner(for: edge, clockwise: clockwise))
            while edge != exitEdge {
                edge = nextEdge(edge, clockwise: clockwise)
                path.append(edgeEndCorner(for: edge, clockwise: clockwise))
            }
            return path
        }

        let cwPath = buildPath(clockwise: true)
        let ccwPath = buildPath(clockwise: false)

        func score(_ path: [CGPoint]) -> Int {
            guard !path.isEmpty else { return 0 }
            var count = 0
            var last = entry
            let bounds = GeometryHelpers.bounds(for: polygon)
            let width = max(bounds.width, 0.0001)
            let height = max(bounds.height, 0.0001)
            let cornerEps: CGFloat = 0.0001

            func isInsideTriangle(_ point: CGPoint) -> Bool {
                let localX = point.x - bounds.minX
                let localY = point.y - bounds.minY
                if localX < -0.01 || localY < -0.01 { return false }
                let value = (localX / width) + (localY / height)
                return value <= 1.0 + 0.01
            }

            func isInsidePolygon(_ point: CGPoint) -> Bool {
                if polygon.count == 3 {
                    return isInsideTriangle(point)
                }
                return GeometryHelpers.pointIsInsidePolygon(point, polygon: polygon)
                    || GeometryHelpers.pointIsOnPolygonEdge(point, polygon: polygon)
            }

            if polygon.count == 3 {
                for corner in path {
                    if corners.contains(where: { abs($0.x - corner.x) < cornerEps && abs($0.y - corner.y) < cornerEps }) {
                        if isInsideTriangle(corner) { count += 10 }
                    }
                }
            }
            for point in path {
                let mid = CGPoint(x: (last.x + point.x) / 2, y: (last.y + point.y) / 2)
                if isInsidePolygon(mid) {
                    count += 1
                }
                last = point
            }
            let mid = CGPoint(x: (last.x + exit.x) / 2, y: (last.y + exit.y) / 2)
            if isInsidePolygon(mid) {
                count += 1
            }
            return count
        }

        return score(cwPath) >= score(ccwPath) ? cwPath : ccwPath
    }

    private static func notchRectanglePoints(size: CGSize, notches: [Cutout]) -> [CGPoint] {
        let width = size.width
        let height = size.height
        let edgeEpsilon: CGFloat = 0.5
        var topLeftMaxX: CGFloat = 0
        var topLeftMaxY: CGFloat = 0
        var topRightMinX: CGFloat = width
        var topRightMaxY: CGFloat = 0
        var bottomRightMinX: CGFloat = width
        var bottomRightMinY: CGFloat = height
        var bottomLeftMaxX: CGFloat = 0
        var bottomLeftMinY: CGFloat = height
        var topSpans: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        var bottomSpans: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        var leftSpans: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        var rightSpans: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []

        for notch in notches {
            let halfWidth = notch.width / 2
            let halfHeight = notch.height / 2
            var minX = max(0, notch.centerX - halfWidth)
            var maxX = min(width, notch.centerX + halfWidth)
            var minY = max(0, notch.centerY - halfHeight)
            var maxY = min(height, notch.centerY + halfHeight)

            if minX <= edgeEpsilon { minX = 0 }
            if maxX >= width - edgeEpsilon { maxX = width }
            if minY <= edgeEpsilon { minY = 0 }
            if maxY >= height - edgeEpsilon { maxY = height }

            let touchesTop = minY <= edgeEpsilon
            let touchesBottom = maxY >= height - edgeEpsilon
            let touchesLeft = minX <= edgeEpsilon
            let touchesRight = maxX >= width - edgeEpsilon

            if touchesTop && touchesLeft {
                topLeftMaxX = max(topLeftMaxX, maxX)
                topLeftMaxY = max(topLeftMaxY, maxY)
            }
            if touchesTop && touchesRight {
                topRightMinX = min(topRightMinX, minX)
                topRightMaxY = max(topRightMaxY, maxY)
            }
            if touchesBottom && touchesRight {
                bottomRightMinX = min(bottomRightMinX, minX)
                bottomRightMinY = min(bottomRightMinY, minY)
            }
            if touchesBottom && touchesLeft {
                bottomLeftMaxX = max(bottomLeftMaxX, maxX)
                bottomLeftMinY = min(bottomLeftMinY, minY)
            }

            let touchesCount = [touchesTop, touchesRight, touchesBottom, touchesLeft].filter { $0 }.count
            if touchesCount == 1 {
                if touchesTop {
                    let depth = maxY
                    if depth > 0 && minX < maxX { topSpans.append((start: minX, end: maxX, depth: depth)) }
                } else if touchesBottom {
                    let depth = height - minY
                    if depth > 0 && minX < maxX { bottomSpans.append((start: minX, end: maxX, depth: depth)) }
                } else if touchesLeft {
                    let depth = maxX
                    if depth > 0 && minY < maxY { leftSpans.append((start: minY, end: maxY, depth: depth)) }
                } else if touchesRight {
                    let depth = width - minX
                    if depth > 0 && minY < maxY { rightSpans.append((start: minY, end: maxY, depth: depth)) }
                }
            }
        }

        let hasTopLeft = topLeftMaxX > 0 && topLeftMaxY > 0
        let hasTopRight = topRightMinX < width && topRightMaxY > 0
        let hasBottomRight = bottomRightMinX < width && bottomRightMinY < height
        let hasBottomLeft = bottomLeftMaxX > 0 && bottomLeftMinY < height
        let mergedTop = mergeEdgeSpans(topSpans)
        let mergedBottom = mergeEdgeSpans(bottomSpans)
        let mergedLeft = mergeEdgeSpans(leftSpans)
        let mergedRight = mergeEdgeSpans(rightSpans)

        var points: [CGPoint] = []
        let startX = hasTopLeft ? topLeftMaxX : 0
        points.append(CGPoint(x: startX, y: 0))

        let topRightX = hasTopRight ? topRightMinX : width
        for span in mergedTop {
            let clampedStart = max(span.start, startX)
            let clampedEnd = min(span.end, topRightX)
            if clampedEnd <= clampedStart { continue }
            if points.last?.x ?? 0 < clampedStart {
                points.append(CGPoint(x: clampedStart, y: 0))
            }
            points.append(CGPoint(x: clampedStart, y: span.depth))
            points.append(CGPoint(x: clampedEnd, y: span.depth))
            points.append(CGPoint(x: clampedEnd, y: 0))
        }
        points.append(CGPoint(x: topRightX, y: 0))
        if hasTopRight {
            points.append(CGPoint(x: topRightX, y: topRightMaxY))
            points.append(CGPoint(x: width, y: topRightMaxY))
        } else {
            points.append(CGPoint(x: width, y: 0))
        }

        let rightDownY = hasBottomRight ? bottomRightMinY : height
        for span in mergedRight {
            let upperBound = hasTopRight ? topRightMaxY : 0
            let clampedStart = max(span.start, upperBound)
            let clampedEnd = min(span.end, rightDownY)
            if clampedEnd <= clampedStart { continue }
            if points.last?.y ?? 0 < clampedStart {
                points.append(CGPoint(x: width, y: clampedStart))
            }
            points.append(CGPoint(x: width - span.depth, y: clampedStart))
            points.append(CGPoint(x: width - span.depth, y: clampedEnd))
            points.append(CGPoint(x: width, y: clampedEnd))
        }
        points.append(CGPoint(x: width, y: rightDownY))
        if hasBottomRight {
            points.append(CGPoint(x: bottomRightMinX, y: bottomRightMinY))
            points.append(CGPoint(x: bottomRightMinX, y: height))
        } else {
            points.append(CGPoint(x: width, y: height))
        }

        let bottomLeftX = hasBottomLeft ? bottomLeftMaxX : 0
        let bottomStartX = hasBottomRight ? bottomRightMinX : width
        for span in mergedBottom.reversed() {
            let clampedStart = max(span.start, bottomLeftX)
            let clampedEnd = min(span.end, bottomStartX)
            if clampedEnd <= clampedStart { continue }
            if points.last?.x ?? width > clampedEnd {
                points.append(CGPoint(x: clampedEnd, y: height))
            }
            points.append(CGPoint(x: clampedEnd, y: height - span.depth))
            points.append(CGPoint(x: clampedStart, y: height - span.depth))
            points.append(CGPoint(x: clampedStart, y: height))
        }
        points.append(CGPoint(x: bottomLeftX, y: height))
        if hasBottomLeft {
            points.append(CGPoint(x: bottomLeftMaxX, y: bottomLeftMinY))
            points.append(CGPoint(x: 0, y: bottomLeftMinY))
        } else {
            points.append(CGPoint(x: 0, y: height))
        }

        let leftUpY = hasTopLeft ? topLeftMaxY : 0
        let leftStartY = hasBottomLeft ? bottomLeftMinY : height
        for span in mergedLeft.reversed() {
            let clampedStart = max(span.start, leftUpY)
            let clampedEnd = min(span.end, leftStartY)
            if clampedEnd <= clampedStart { continue }
            if points.last?.y ?? height > clampedEnd {
                points.append(CGPoint(x: 0, y: clampedEnd))
            }
            points.append(CGPoint(x: span.depth, y: clampedEnd))
            points.append(CGPoint(x: span.depth, y: clampedStart))
            points.append(CGPoint(x: 0, y: clampedStart))
        }
        points.append(CGPoint(x: 0, y: leftUpY))
        if hasTopLeft {
            points.append(CGPoint(x: topLeftMaxX, y: topLeftMaxY))
            points.append(CGPoint(x: topLeftMaxX, y: 0))
        } else {
            points.append(CGPoint(x: 0, y: 0))
        }

        return dedupePoints(points)
    }

    private static func mergeEdgeSpans(_ spans: [(start: CGFloat, end: CGFloat, depth: CGFloat)]) -> [(start: CGFloat, end: CGFloat, depth: CGFloat)] {
        let sorted = spans.sorted { $0.start < $1.start }
        var merged: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        for span in sorted {
            guard let last = merged.last else {
                merged.append(span)
                continue
            }
            if span.start <= last.end + 0.01 {
                let newEnd = max(last.end, span.end)
                let newDepth = max(last.depth, span.depth)
                merged[merged.count - 1] = (start: last.start, end: newEnd, depth: newDepth)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func mergeHypotenuseSpans(_ spans: [(start: CGFloat, end: CGFloat, depth: CGFloat)]) -> [(start: CGFloat, end: CGFloat, depth: CGFloat)] {
        let sorted = spans.sorted { $0.start < $1.start }
        var merged: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        for span in sorted {
            guard let last = merged.last else {
                merged.append(span)
                continue
            }
            if span.start <= last.end + 0.0001 {
                let newEnd = max(last.end, span.end)
                let newDepth = max(last.depth, span.depth)
                merged[merged.count - 1] = (start: last.start, end: newEnd, depth: newDepth)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func applyCornerNotches(to rawPoints: [CGPoint], notches: [Cutout], shape: ShapeKind, size: CGSize) -> [CGPoint] {
        guard !notches.isEmpty, rawPoints.count >= 3 else { return rawPoints }
        var displayPoints = rawPoints.map { displayPoint(fromRaw: $0) }
        displayPoints = reorderCornersClockwise(displayPoints)

        let displaySize = CGSize(width: size.height, height: size.width)
        let orderedNotches = sortNotchesByCorner(notches, points: displayPoints)
        for notch in orderedNotches {
            displayPoints = applyCornerNotchToDisplay(points: displayPoints, notch: notch, shape: shape, displaySize: displaySize)
        }

        return displayPoints.map { rawPoint(fromDisplay: $0) }
    }

    private static func applyCornerNotchToDisplay(points: [CGPoint], notch: Cutout, shape: ShapeKind, displaySize: CGSize) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        var displayWidth = max(notch.height, 0)
        var displayHeight = max(notch.width, 0)
        if displayWidth <= 0 || displayHeight <= 0 {
            return points
        }

        let index = resolveNotchCornerIndex(notch, points: points)
        guard index >= 0 else { return points }

        let count = points.count
        let prevIndex = (index - 1 + count) % count
        let nextIndex = (index + 1) % count
        let corner = points[index]
        let prev = points[prevIndex]
        let next = points[nextIndex]

        var toPrev = unitVector(from: corner, to: prev)
        var toNext = unitVector(from: corner, to: next)

        if shape == .rightTriangle {
            let eps: CGFloat = 0.01
            let cornerA = CGPoint(x: 0, y: 0)
            let cornerB = CGPoint(x: 0, y: displaySize.height)
            let cornerC = CGPoint(x: displaySize.width, y: 0)
            if distance(corner, cornerB) < eps {
                toPrev = CGPoint(x: 1, y: 0)
                toNext = CGPoint(x: 0, y: -1)
            } else if distance(corner, cornerC) < eps {
                toPrev = CGPoint(x: -1, y: 0)
                toNext = CGPoint(x: 0, y: 1)
            } else if distance(corner, cornerA) < eps {
                toPrev = CGPoint(x: 1, y: 0)
                toNext = CGPoint(x: 0, y: 1)
            }
        }

        let maxWidth = max(distance(corner, prev) * 0.98, 0)
        let maxHeight = max(distance(corner, next) * 0.98, 0)
        displayWidth = min(displayWidth, maxWidth)
        displayHeight = min(displayHeight, maxHeight)

        let p1 = CGPoint(x: corner.x + toPrev.x * displayWidth, y: corner.y + toPrev.y * displayWidth)
        let p3 = CGPoint(x: corner.x + toNext.x * displayHeight, y: corner.y + toNext.y * displayHeight)
        let p2 = CGPoint(x: p1.x + toNext.x * displayHeight, y: p1.y + toNext.y * displayHeight)

        var newPoints: [CGPoint] = []
        for i in 0..<count {
            if i == index {
                newPoints.append(p1)
                newPoints.append(p2)
                newPoints.append(p3)
            } else {
                newPoints.append(points[i])
            }
        }

        return dedupePoints(newPoints)
    }

    private static func resolveNotchCornerIndex(_ notch: Cutout, points: [CGPoint]) -> Int {
        if notch.cornerAnchorX >= 0 && notch.cornerAnchorY >= 0 {
            let anchor = CGPoint(x: notch.cornerAnchorX, y: notch.cornerAnchorY)
            return nearestPointIndex(to: anchor, points: points)
        }
        if notch.cornerIndex >= 0 && notch.cornerIndex < points.count {
            return notch.cornerIndex
        }
        if notch.isPlaced {
            let center = displayPoint(fromRaw: CGPoint(x: notch.centerX, y: notch.centerY))
            return nearestPointIndex(to: center, points: points)
        }
        return -1
    }

    private static func sortNotchesByCorner(_ notches: [Cutout], points: [CGPoint]) -> [Cutout] {
        notches.sorted { lhs, rhs in
            let leftIndex = resolveNotchCornerIndex(lhs, points: points)
            let rightIndex = resolveNotchCornerIndex(rhs, points: points)
            if leftIndex != rightIndex {
                return leftIndex < rightIndex
            }
            let leftSize = max(lhs.width, lhs.height)
            let rightSize = max(rhs.width, rhs.height)
            if leftSize != rightSize {
                return leftSize > rightSize
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func nearestPointIndex(to point: CGPoint, points: [CGPoint]) -> Int {
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, candidate) in points.enumerated() {
            let dist = distance(point, candidate)
            if dist < bestDistance {
                bestDistance = dist
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func applyAngleCuts(to basePoints: [CGPoint], shape: ShapeKind, size: CGSize, angleCuts: [AngleCut]) -> (points: [CGPoint], segments: [AngleSegment]) {
        guard !angleCuts.isEmpty else { return (basePoints, []) }
        let baseDisplay = basePoints.map { displayPoint(fromRaw: $0) }
        let baseOrdered = reorderCornersClockwise(baseDisplay)
        var displayPoints = baseOrdered
        var segments: [AngleSegment] = []
        let sortedCuts = angleCuts.sorted { lhs, rhs in
            if lhs.anchorCornerIndex == rhs.anchorCornerIndex {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.anchorCornerIndex < rhs.anchorCornerIndex
        }
        for cut in sortedCuts {
            if cut.anchorCornerIndex < 0 {
                continue
            }
            let result = applyAngleCutDisplay(cut, to: displayPoints, baseOrdered: baseOrdered)
            displayPoints = result.points
            if let segment = result.segment {
                segments.append(AngleSegment(id: segment.id, start: rawPoint(fromDisplay: segment.start), end: rawPoint(fromDisplay: segment.end)))
            }
        }
        let rawPoints = displayPoints.map { rawPoint(fromDisplay: $0) }
        return (rawPoints, segments)
    }

    private static func applyAngleCutDisplay(_ cut: AngleCut, to ordered: [CGPoint], baseOrdered: [CGPoint], referencePolygon: [CGPoint]? = nil) -> (points: [CGPoint], segment: AngleSegment?) {
        guard ordered.count >= 3 else { return (ordered, nil) }
        guard baseOrdered.count >= 3 else { return (ordered, nil) }
        // When a referencePolygon is provided, use it to resolve the correct vertex
        // position for the cut's anchorCornerIndex. This handles the case where the
        // cut's index was assigned from a polygon with notches (e.g. 20 corners) but
        // baseOrdered is a clean rectangle (4 corners) — normalizedIndex wrapping
        // would map the index to the wrong corner.
        let baseCorner: CGPoint
        if let ref = referencePolygon, !ref.isEmpty {
            let refIdx = normalizedIndex(cut.anchorCornerIndex, count: ref.count)
            let refVertex = ref[refIdx]
            // Find the nearest vertex in baseOrdered that matches this position
            baseCorner = baseOrdered.min(by: { distance($0, refVertex) < distance($1, refVertex) }) ?? baseOrdered[0]
        } else {
            let baseAnchorIndex = normalizedIndex(cut.anchorCornerIndex, count: baseOrdered.count)
            baseCorner = baseOrdered[baseAnchorIndex]
        }
        let anchorIndex = nearestVertexIndex(to: baseCorner, in: ordered)
        let prevIndex = normalizedIndex(anchorIndex - 1, count: ordered.count)
        let nextIndex = normalizedIndex(anchorIndex + 1, count: ordered.count)
        let corner = ordered[anchorIndex]
        let prev = ordered[prevIndex]
        let next = ordered[nextIndex]

        let alongEdge1 = abs(cut.anchorOffset)
        let alongEdge2 = abs(cut.secondaryOffset)

        let toNext = unitVector(from: corner, to: next)
        let toPrev = unitVector(from: corner, to: prev)
        let lenNext = distance(corner, next)
        let lenPrev = distance(corner, prev)
        guard alongEdge1 <= lenNext, alongEdge2 <= lenPrev else { return (ordered, nil) }

        let p1 = CGPoint(x: corner.x + toNext.x * alongEdge1, y: corner.y + toNext.y * alongEdge1)
        let p2 = CGPoint(x: corner.x + toPrev.x * alongEdge2, y: corner.y + toPrev.y * alongEdge2)

        var newPoints: [CGPoint] = []
        for (index, point) in ordered.enumerated() {
            if index == anchorIndex {
                newPoints.append(p2)
                newPoints.append(p1)
            } else {
                newPoints.append(point)
            }
        }
        return (dedupePoints(newPoints), AngleSegment(id: cut.id, start: p2, end: p1))
    }

    static func angleDegrees(for piece: Piece, anchorCornerIndex: Int, anchorOffset: Double, secondaryCornerIndex: Int, secondaryOffset: Double, angleCutLimit: Int? = nil) -> Double? {
        let points = cornerPoints(for: piece, includeAngles: false, angleCutLimit: angleCutLimit)
        guard points.count >= 3 else { return nil }
        let anchorIndex = normalizedIndex(anchorCornerIndex, count: points.count)
        let secondaryIndex = normalizedIndex(secondaryCornerIndex, count: points.count)
        guard let anchor = pointAlongPerimeter(points: points, startIndex: anchorIndex, offset: anchorOffset),
              let secondary = pointAlongPerimeter(points: points, startIndex: secondaryIndex, offset: secondaryOffset) else { return nil }

        let tangent = tangentDirection(points: points, segmentStartIndex: anchor.segmentStartIndex)
        let toSecondary = unitVector(from: anchor.point, to: secondary.point)
        let dot = max(min(tangent.x * toSecondary.x + tangent.y * toSecondary.y, 1), -1)
        let radians = acos(dot)
        let acute = min(radians, .pi - radians)
        return Double(acute * 180 / .pi)
    }

    static func secondaryPoint(for piece: Piece, anchorCornerIndex: Int, anchorOffset: Double, angleDegrees: Double, angleCutLimit: Int? = nil) -> (cornerIndex: Int, offset: Double)? {
        let points = cornerPoints(for: piece, includeAngles: false, angleCutLimit: angleCutLimit)
        guard points.count >= 3 else { return nil }
        let anchorIndex = normalizedIndex(anchorCornerIndex, count: points.count)
        guard let anchor = pointAlongPerimeter(points: points, startIndex: anchorIndex, offset: anchorOffset) else { return nil }
        guard let secondary = secondaryPointInfo(points: points, anchor: anchor, angleDegrees: angleDegrees) else { return nil }
        let offset = distance(points[secondary.segmentStartIndex], secondary.point)
        return (cornerIndex: secondary.segmentStartIndex, offset: Double(offset))
    }

    private struct PerimeterPointInfo {
        let point: CGPoint
        let segmentStartIndex: Int
        let t: CGFloat
    }

    private static func normalizedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let mod = index % count
        return mod < 0 ? mod + count : mod
    }

    private static func pointAlongPerimeter(points: [CGPoint], startIndex: Int, offset: Double) -> PerimeterPointInfo? {
        guard points.count >= 2 else { return nil }
        let count = points.count
        var remaining = CGFloat(abs(offset))
        let clockwise = offset >= 0
        var idx = normalizedIndex(startIndex, count: count)
        while remaining >= 0 {
            let next = normalizedIndex(idx + (clockwise ? 1 : -1), count: count)
            let start = points[idx]
            let end = points[next]
            let segLen = distance(start, end)
            if segLen == 0 {
                idx = next
                continue
            }
            if remaining <= segLen {
                let t = remaining / segLen
                if clockwise {
                    let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                    return PerimeterPointInfo(point: point, segmentStartIndex: idx, t: t)
                }
                let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                let segmentStart = next
                let cwT = 1 - t
                return PerimeterPointInfo(point: point, segmentStartIndex: segmentStart, t: cwT)
            }
            remaining -= segLen
            idx = next
        }
        return nil
    }

    // locatePointOnPolygon/projectPoint removed; chamfer points are derived from the current shape.

    private static func tangentDirection(points: [CGPoint], segmentStartIndex: Int) -> CGPoint {
        let count = points.count
        let start = points[segmentStartIndex]
        let end = points[(segmentStartIndex + 1) % count]
        return unitVector(from: start, to: end)
    }

    private static func secondaryPointInfo(points: [CGPoint], anchor: PerimeterPointInfo, angleDegrees: Double) -> PerimeterPointInfo? {
        let tangent = tangentDirection(points: points, segmentStartIndex: anchor.segmentStartIndex)
        let radians = CGFloat(angleDegrees * Double.pi / 180)
        let directions = [rotate(tangent, by: radians), rotate(tangent, by: -radians)]
        var best: PerimeterPointInfo?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for dir in directions {
            for i in 0..<points.count {
                let start = points[i]
                let end = points[(i + 1) % points.count]
                if i == anchor.segmentStartIndex { continue }
                if let hit = raySegmentIntersection(origin: anchor.point, direction: dir, segment: (start, end)) {
                    let segLen = distance(start, end)
                    if segLen == 0 { continue }
                    let t = max(min(distance(start, hit) / segLen, 1), 0)
                    let dist = distance(anchor.point, hit)
                    if dist < bestDistance {
                        bestDistance = dist
                        best = PerimeterPointInfo(point: hit, segmentStartIndex: i, t: t)
                    }
                }
            }
        }
        return best
    }

    private struct InsertionPlanItem {
        let point: CGPoint
        let segmentStartIndex: Int
        let t: CGFloat
        let isAnchor: Bool
    }

    private static func orderedInsertion(anchor: PerimeterPointInfo, secondary: PerimeterPointInfo) -> [InsertionPlanItem] {
        if anchor.segmentStartIndex == secondary.segmentStartIndex {
            if anchor.t < secondary.t {
                return [
                    InsertionPlanItem(point: secondary.point, segmentStartIndex: secondary.segmentStartIndex, t: secondary.t, isAnchor: false),
                    InsertionPlanItem(point: anchor.point, segmentStartIndex: anchor.segmentStartIndex, t: anchor.t, isAnchor: true)
                ]
            }
        }
        let first = anchor.segmentStartIndex > secondary.segmentStartIndex ? anchor : secondary
        let second = first.segmentStartIndex == anchor.segmentStartIndex ? secondary : anchor
        return [
            InsertionPlanItem(point: first.point, segmentStartIndex: first.segmentStartIndex, t: first.t, isAnchor: first.point == anchor.point),
            InsertionPlanItem(point: second.point, segmentStartIndex: second.segmentStartIndex, t: second.t, isAnchor: second.point == anchor.point)
        ]
    }

    private static func insertPoint(points: [CGPoint], segmentStartIndex: Int, t: CGFloat, point: CGPoint) -> (points: [CGPoint], insertedIndex: Int) {
        var newPoints = points
        let count = points.count
        let clampedT = max(min(t, 1), 0)
        let insertIndex = (segmentStartIndex + 1) % count
        if clampedT <= 0.0001 {
            newPoints[segmentStartIndex] = point
            return (newPoints, segmentStartIndex)
        }
        if clampedT >= 0.9999 {
            let endIndex = insertIndex % newPoints.count
            newPoints[endIndex] = point
            return (newPoints, endIndex)
        }
        newPoints.insert(point, at: insertIndex)
        return (newPoints, insertIndex)
    }

    private static func pathIndices(from start: Int, to end: Int, step: Int, count: Int) -> [Int] {
        var indices: [Int] = [start]
        var idx = start
        while idx != end {
            idx = normalizedIndex(idx + step, count: count)
            indices.append(idx)
        }
        return indices
    }

    private static func pathLength(points: [CGPoint], indices: [Int]) -> CGFloat {
        guard indices.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 0..<(indices.count - 1) {
            total += distance(points[indices[i]], points[indices[i + 1]])
        }
        return total
    }

    private static func nearestVertexIndex(to point: CGPoint, in points: [CGPoint]) -> Int {
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, candidate) in points.enumerated() {
            let d = distance(point, candidate)
            if d < bestDistance {
                bestDistance = d
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func targetEdgeSegment(targetEdge: EdgePosition, shape: ShapeKind, bounds: CGRect, size: CGSize) -> (CGPoint, CGPoint) {
        switch shape {
        case .rightTriangle:
            let p0 = CGPoint(x: 0, y: 0)
            let p1 = CGPoint(x: size.width, y: 0)
            let p2 = CGPoint(x: 0, y: size.height)
            switch targetEdge {
            case .legA:
                return (p0, p1)
            case .legB:
                return (p2, p0)
            default:
                return (p1, p2)
            }
        default:
            switch targetEdge {
            case .top:
                return (CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY))
            case .bottom:
                return (CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY))
            case .left:
                return (CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.minY))
            case .right:
                return (CGPoint(x: bounds.maxX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.maxY))
            default:
                return (CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY))
            }
        }
    }

    private static func raySegmentIntersection(origin: CGPoint, direction: CGPoint, segment: (CGPoint, CGPoint)) -> CGPoint? {
        let p = origin
        let r = direction
        let q = segment.0
        let s = CGPoint(x: segment.1.x - segment.0.x, y: segment.1.y - segment.0.y)
        let rxs = r.x * s.y - r.y * s.x
        if abs(rxs) < 0.0001 { return nil }
        let qmp = CGPoint(x: q.x - p.x, y: q.y - p.y)
        let t = (qmp.x * s.y - qmp.y * s.x) / rxs
        let u = (qmp.x * r.y - qmp.y * r.x) / rxs
        if t >= 0 && u >= 0 && u <= 1 {
            return CGPoint(x: p.x + r.x * t, y: p.y + r.y * t)
        }
        return nil
    }

    private static func polygonBounds(_ points: [CGPoint]) -> CGRect {
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

    private static func polygonIsClockwise(_ points: [CGPoint]) -> Bool {
        guard points.count >= 3 else { return true }
        var area: CGFloat = 0
        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]
            area += (p1.x * p2.y) - (p2.x * p1.y)
        }
        return area > 0
    }

    /// Filters polygon points to keep only significant corners (vertices with sharp angle changes).
    /// This removes the intermediate sample points added when curves are sampled into line segments.
    /// A point is considered a significant corner if any of these conditions are met:
    /// 1. The angle change at that vertex exceeds the threshold (default 5°)
    /// 2. The adjacent segment lengths differ significantly (ratio > 2.0)
    /// 3. Either adjacent edge is axis-aligned (horizontal or vertical), indicating a real corner
    /// Filters out points that fall outside the curved piece boundary.
    /// Points are kept if they are inside or on the boundary of the curved piece.
    /// Uses a tolerance to handle points exactly on the curve boundary.
    private static func reorderCornersClockwise(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var ordered = points
        if isClockwise(ordered) {
            ordered.reverse()
        }

        // Find the point closest to the origin (0, 0) as the starting corner.
        // This ensures corner A is always at the top-left of the piece's logical boundary,
        // regardless of curves or notches that may extend beyond that boundary.
        let origin = CGPoint.zero
        let startIndex = ordered.enumerated().min(by: { lhs, rhs in
            let distL = distance(lhs.element, origin)
            let distR = distance(rhs.element, origin)
            return distL < distR
        })?.offset ?? 0
        if startIndex == 0 { return ordered }
        return Array(ordered[startIndex...] + ordered[..<startIndex])
    }

    private static func isClockwise(_ points: [CGPoint]) -> Bool {
        var area: CGFloat = 0
        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]
            area += (p1.x * p2.y) - (p2.x * p1.y)
        }
        return area < 0
    }

    private static func rotate(_ point: CGPoint, by radians: CGFloat) -> CGPoint {
        let cosv = cos(radians)
        let sinv = sin(radians)
        return CGPoint(x: point.x * cosv - point.y * sinv, y: point.x * sinv + point.y * cosv)
    }

    private static func unitVector(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        return CGPoint(x: dx / length, y: dy / length)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    private static func dedupePoints(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, distance(point, last) < 0.0001 {
                continue
            }
            result.append(point)
        }
        if result.count > 1, let first = result.first, let last = result.last, distance(first, last) < 0.0001 {
            result.removeLast()
        }
        return result
    }

    private static func polygonPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private static func cutoutCornerPoints(for cutout: Cutout) -> [CGPoint] {
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

    private static func applyAngleCutsDisplay(to basePoints: [CGPoint], angleCuts: [AngleCut], referencePolygon: [CGPoint]? = nil) -> [CGPoint] {
        guard !angleCuts.isEmpty else { return basePoints }
        var displayPoints = basePoints
        let baseOrdered = reorderCornersClockwise(displayPoints)
        for cut in angleCuts {
            if cut.anchorCornerIndex < 0 {
                continue
            }
            let ordered = reorderCornersClockwise(displayPoints)
            let result = applyAngleCutDisplay(cut, to: ordered, baseOrdered: baseOrdered, referencePolygon: referencePolygon)
            displayPoints = result.points
        }
        return displayPoints
    }

    private static func roundedPolygonPath(points: [CGPoint], cornerRadii: [CornerRadius], baseCorners: [CGPoint]? = nil) -> Path {
        var path = Path()
        guard points.count >= 3 else { return polygonPath(points) }
        let count = points.count
        var radiusMap: [Int: CornerRadius] = [:]
        for corner in cornerRadii where corner.cornerIndex >= 0 {
            let targetIndex: Int
            if let base = baseCorners, corner.cornerIndex < base.count {
                let origin = base[corner.cornerIndex]
                targetIndex = points.enumerated().min { lhs, rhs in
                    distance(lhs.element, origin) < distance(rhs.element, origin)
                }?.offset ?? corner.cornerIndex
            } else {
                targetIndex = corner.cornerIndex
            }
            radiusMap[targetIndex] = corner
        }
        for index in 0..<count {
            let prev = points[(index - 1 + count) % count]
            let curr = points[index]
            let next = points[(index + 1) % count]
            guard let corner = radiusMap[index], corner.radius > 0 else {
                if index == 0 {
                    path.move(to: curr)
                } else {
                    path.addLine(to: curr)
                }
                continue
            }

            let v1 = unitVector(from: curr, to: prev)
            let v2 = unitVector(from: curr, to: next)
            let dot = max(min(v1.x * v2.x + v1.y * v2.y, 1), -1)
            let angleSmall = acos(dot)
            if angleSmall < 0.0001 {
                if index == 0 {
                    path.move(to: curr)
                } else {
                    path.addLine(to: curr)
                }
                continue
            }

            let lenPrev = distance(curr, prev)
            let lenNext = distance(curr, next)
            let tanHalf = tan(angleSmall / 2)
            let tanHalfAbs = abs(tanHalf)
            if tanHalfAbs <= 0.0001 {
                if index == 0 {
                    path.move(to: curr)
                } else {
                    path.addLine(to: curr)
                }
                continue
            }

            let maxRadius = min(lenPrev, lenNext) * tanHalfAbs
            let radius = min(CGFloat(corner.radius), maxRadius)
            if radius <= 0.0001 {
                if index == 0 {
                    path.move(to: curr)
                } else {
                    path.addLine(to: curr)
                }
                continue
            }

            let t = radius / tanHalfAbs
            let p1 = CGPoint(x: curr.x + v1.x * t, y: curr.y + v1.y * t)
            let p2 = CGPoint(x: curr.x + v2.x * t, y: curr.y + v2.y * t)

            if index == 0 {
                path.move(to: p1)
            } else {
                path.addLine(to: p1)
            }

            let bisector = unitVector(from: .zero, to: CGPoint(x: v1.x + v2.x, y: v1.y + v2.y))
            let sinHalf = sin(angleSmall / 2)
            if sinHalf <= 0.0001 {
                path.addLine(to: p2)
                continue
            }

            let centerOffset = radius / sinHalf
            let center = CGPoint(x: curr.x + bisector.x * centerOffset,
                                 y: curr.y + bisector.y * centerOffset)

            let startRadians = atan2(p1.y - center.y, p1.x - center.x)
            let endRadians = atan2(p2.y - center.y, p2.x - center.x)
            var delta = endRadians - startRadians
            while delta <= -CGFloat.pi { delta += 2 * CGFloat.pi }
            while delta > CGFloat.pi { delta -= 2 * CGFloat.pi }
            let arcClockwise = delta < 0
            let startAngle = Angle(radians: startRadians)
            let endAngle = Angle(radians: endRadians)
            path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: arcClockwise)
        }

        path.closeSubpath()
        return path
    }

    /// Builds a path that combines curved edges with rounded corners.
    /// Curved edges take priority - corner radii are only applied to corners not adjacent to curved edges.
    private static func roundedCurvedPolygonPath(
        points: [CGPoint],
        cornerRadii: [CornerRadius],
        baseCorners: [CGPoint]?,
        radiusBaseCorners: [CGPoint]? = nil,
        curves: [CurvedEdge],
        shape: ShapeKind,
        piece: Piece
    ) -> Path {
        var path = Path()
        guard points.count >= 3 else { return polygonPath(points) }

        let count = points.count
        let curvesByEdge = Dictionary(grouping: curves, by: { $0.edge })
        let edgeCurves = curvesByEdge.compactMapValues { curves in
            curves.first(where: { !$0.hasSpan && $0.radius > 0 }) ?? curves.first(where: { $0.radius > 0 })
        }
        let bounds = polygonBounds(points)
        let hypotenuseBounds = baseCorners.map { polygonBounds($0) } ?? bounds
        let occupiedCorners = cornerIndicesOnCurvedEdges(points: baseCorners ?? points, shape: shape, curves: curves, requireConvex: true)

        // CAD-style hypotenuse t-values for consistent curve subdivision.
        var pointHypotenuseT: [Int: CGFloat] = [:]
        if shape == .rightTriangle, (curvesByEdge[.hypotenuse]?.contains { $0.radius > 0 } ?? false) {
            let hypStart = CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY)
            let hypEnd = CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY)
            let hypDx = hypEnd.x - hypStart.x
            let hypDy = hypEnd.y - hypStart.y
            let hypLengthSquared = hypDx * hypDx + hypDy * hypDy
            if hypLengthSquared > 0.0001 {
                let tolerance = hypotenuseTolerance(for: hypotenuseBounds)
                let tTolerance: CGFloat = 0.02
                for index in 0..<points.count {
                    let point = points[index]
                    let px = point.x - hypStart.x
                    let py = point.y - hypStart.y
                    let t = (px * hypDx + py * hypDy) / hypLengthSquared
                    let projX = hypStart.x + t * hypDx
                    let projY = hypStart.y + t * hypDy
                    let perpDist = sqrt((point.x - projX) * (point.x - projX) + (point.y - projY) * (point.y - projY))
                    if perpDist <= tolerance && t >= -tTolerance && t <= 1.0 + tTolerance {
                        pointHypotenuseT[index] = max(0, min(1, t))
                    }
                }
            }
        }

        // Build radius map for non-curved corners only
        var radiusMap: [Int: CornerRadius] = [:]
        for corner in cornerRadii where corner.cornerIndex >= 0 && !occupiedCorners.contains(corner.cornerIndex) {
            let targetIndex: Int
            if let base = radiusBaseCorners, corner.cornerIndex < base.count {
                let origin = base[corner.cornerIndex]
                targetIndex = points.enumerated().min { lhs, rhs in
                    distance(lhs.element, origin) < distance(rhs.element, origin)
                }?.offset ?? corner.cornerIndex
            } else {
                targetIndex = corner.cornerIndex
            }
            radiusMap[targetIndex] = corner
        }

        // Edge-based control overrides (use first curve per edge, span or not)
        var edgeControlOverrides: [EdgePosition: CGPoint] = [:]
        for (edge, curve) in edgeCurves where curve.radius > 0 {
            if let geometry = fullEdgeGeometry(edge: edge, bounds: bounds, hypotenuseBounds: hypotenuseBounds, shape: shape) {
                let mid = CGPoint(x: (geometry.start.x + geometry.end.x) / 2, y: (geometry.start.y + geometry.end.y) / 2)
                let direction = curve.isConcave ? -1.0 : 1.0
                edgeControlOverrides[edge] = CGPoint(
                    x: mid.x + geometry.normal.x * curve.radius * 2 * direction,
                    y: mid.y + geometry.normal.y * curve.radius * 2 * direction
                )
            }
        }

        func segmentTValue(start: CGPoint, end: CGPoint, index: Int, nextIndex: Int, edge: EdgePosition, geometry: (start: CGPoint, end: CGPoint, normal: CGPoint)) -> (t0: CGFloat, t1: CGFloat) {
            if edge == .hypotenuse, let preT0 = pointHypotenuseT[index], let preT1 = pointHypotenuseT[nextIndex] {
                return (preT0, preT1)
            }
            let t0 = tForEdge(point: start, geometry: geometry, edge: edge)
            let t1 = tForEdge(point: end, geometry: geometry, edge: edge)
            return (t0, t1)
        }

        var drawPoints = points
        var spanInfosByEdge: [EdgePosition: [SpanInfo]] = [:]
        let pointCount = points.count

        let boundarySegments = boundarySegments(for: points, shape: shape, bounds: bounds, hypotenuseBounds: shape == .rightTriangle ? hypotenuseBounds : nil)
        for curve in curves where curve.hasSpan && curve.radius > 0 {
            guard pointCount > 1 else { continue }
            guard let span = spanIndices(for: curve, boundarySegments: boundarySegments, pointCount: pointCount, bounds: bounds, shape: shape) else { continue }
            if span.start == span.end { continue }
            let spanStart = points[span.start]
            let spanEnd = points[span.end]
            guard let spanEdge = edgeForSpanPoints(
                start: spanStart,
                end: spanEnd,
                points: points,
                bounds: bounds,
                hypotenuseBounds: hypotenuseBounds,
                shape: shape
            ) else { continue }
            guard let fullGeometry = fullEdgeGeometry(edge: spanEdge, bounds: bounds, hypotenuseBounds: hypotenuseBounds, shape: shape) else { continue }
            let edgeSegments = edgeSegmentsForPoints(
                points: points,
                edge: spanEdge,
                shape: shape,
                bounds: bounds,
                hypotenuseBounds: hypotenuseBounds
            )
            guard !edgeSegments.isEmpty else { continue }
            guard spanPathIsValid(
                points: points,
                startIndex: span.start,
                endIndex: span.end,
                edge: spanEdge,
                shape: shape,
                hypotenuseBounds: hypotenuseBounds,
                bounds: bounds
            ) else { continue }

            let spanDx = spanEnd.x - spanStart.x
            let spanDy = spanEnd.y - spanStart.y
            let spanDenom = spanDx * spanDx + spanDy * spanDy
            guard spanDenom > 0.0001 else { continue }

            func spanParam(_ point: CGPoint) -> CGFloat {
                return ((point.x - spanStart.x) * spanDx + (point.y - spanStart.y) * spanDy) / spanDenom
            }

            let sStart = spanParam(spanStart)
            let sEnd = spanParam(spanEnd)
            let sMin = min(sStart, sEnd)
            let sMax = max(sStart, sEnd)
            let direction = curve.isConcave ? -1.0 : 1.0

            if abs(sMax - sMin) < 0.0001 { continue }

            let mid = CGPoint(x: (spanStart.x + spanEnd.x) / 2, y: (spanStart.y + spanEnd.y) / 2)
            let control = CGPoint(
                x: mid.x + fullGeometry.normal.x * curve.radius * 2 * direction,
                y: mid.y + fullGeometry.normal.y * curve.radius * 2 * direction
            )

            let spanInfo = SpanInfo(curve: curve, edge: spanEdge, spanStart: spanStart, spanEnd: spanEnd, sMin: sMin, sMax: sMax, control: control)
            spanInfosByEdge[spanEdge, default: []].append(spanInfo)

            var edgePointIndices = Set<Int>()
            for segment in edgeSegments {
                edgePointIndices.insert(segment.startIndex)
                edgePointIndices.insert(segment.endIndex)
            }

            for pointIndex in edgePointIndices {
                let point = points[pointIndex]
                let t = spanParam(point)
                if t < sMin - 0.0001 || t > sMax + 0.0001 { continue }
                drawPoints[pointIndex] = quadPoint(start: spanStart, control: control, end: spanEnd, t: t)
            }
        }

        func spanControlOverride(edge: EdgePosition, start: CGPoint, end: CGPoint) -> (curve: CurvedEdge, control: CGPoint)? {
            guard let infos = spanInfosByEdge[edge] else { return nil }
            for info in infos {
                let spanDx = info.spanEnd.x - info.spanStart.x
                let spanDy = info.spanEnd.y - info.spanStart.y
                let spanDenom = spanDx * spanDx + spanDy * spanDy
                guard spanDenom > 0.0001 else { continue }
                let segT0 = ((start.x - info.spanStart.x) * spanDx + (start.y - info.spanStart.y) * spanDy) / spanDenom
                let segT1 = ((end.x - info.spanStart.x) * spanDx + (end.y - info.spanStart.y) * spanDy) / spanDenom
                let segMin = min(segT0, segT1)
                let segMax = max(segT0, segT1)
                if segMax < info.sMin || segMin > info.sMax { continue }
                let denom = max(info.sMax - info.sMin, 0.0001)
                let t0 = (segT0 - info.sMin) / denom
                let t1 = (segT1 - info.sMin) / denom
                let segment = quadSubsegment(
                    start: info.spanStart,
                    control: info.control,
                    end: info.spanEnd,
                    t0: t0,
                    t1: t1
                )
                return (info.curve, segment.control)
            }
            return nil
        }

        func hasCurveForSegment(edge: EdgePosition?, start: CGPoint, end: CGPoint) -> Bool {
            guard let edge else { return false }
            if spanControlOverride(edge: edge, start: start, end: end) != nil {
                return true
            }
            if let edgeCurve = edgeCurves[edge], edgeCurve.radius > 0 {
                return true
            }
            return false
        }

        func resolvedEdge(forSegmentAt index: Int, start: CGPoint, end: CGPoint) -> EdgePosition? {
            _ = index
            return edgeForSegment(start: start, end: end, bounds: bounds, shape: shape, hypotenuseBounds: hypotenuseBounds)
        }

        struct CornerArc {
            let start: CGPoint
            let end: CGPoint
            let center: CGPoint?
            let radius: CGFloat
            let startAngle: Angle?
            let endAngle: Angle?
            let clockwise: Bool
        }

        let isClockwise = polygonIsClockwise(points)
        var cornerArcs: [Int: CornerArc] = [:]
        var edgeToNextMap: [Int: EdgePosition?] = [:]

        for index in 0..<count {
            let prevIndex = (index - 1 + count) % count
            let nextIndex = (index + 1) % count
            let prev = points[prevIndex]
            let curr = points[index]
            let next = points[nextIndex]
            let prevDraw = drawPoints[prevIndex]
            let nextDraw = drawPoints[nextIndex]

            let edgeFromPrev = resolvedEdge(forSegmentAt: prevIndex, start: prev, end: curr)
            let edgeToNext = resolvedEdge(forSegmentAt: index, start: curr, end: next)
            let hasCurveOnPrevEdge = hasCurveForSegment(edge: edgeFromPrev, start: prev, end: curr)
            let hasCurveOnNextEdge = hasCurveForSegment(edge: edgeToNext, start: curr, end: next)

            edgeToNextMap[index] = edgeToNext

            guard let corner = radiusMap[index], corner.radius > 0 else { continue }
            let isConcave = isConcaveCorner(prev: prev, curr: curr, next: next, clockwise: isClockwise)
            let cornerPrev = isConcave ? prev : (hasCurveOnPrevEdge ? prevDraw : prev)
            let cornerNext = isConcave ? next : (hasCurveOnNextEdge ? nextDraw : next)
            let cornerCurr = curr

            let v1 = unitVector(from: cornerCurr, to: cornerPrev)
            let v2 = unitVector(from: cornerCurr, to: cornerNext)
            let dot = max(min(v1.x * v2.x + v1.y * v2.y, 1), -1)
            let angleSmall = acos(dot)
            guard angleSmall >= 0.0001 else { continue }

            let lenPrev = distance(cornerCurr, cornerPrev)
            let lenNext = distance(cornerCurr, cornerNext)
            let tanHalf = tan(angleSmall / 2)
            let tanHalfAbs = abs(tanHalf)
            guard tanHalfAbs > 0.0001 else { continue }

            let maxRadius = min(lenPrev, lenNext) * tanHalfAbs
            let radius = min(CGFloat(corner.radius), maxRadius)
            guard radius > 0.0001 else { continue }

            let t = radius / tanHalfAbs
            let p1 = CGPoint(x: cornerCurr.x + v1.x * t, y: cornerCurr.y + v1.y * t)
            let p2 = CGPoint(x: cornerCurr.x + v2.x * t, y: cornerCurr.y + v2.y * t)

            let bisector = unitVector(from: .zero, to: CGPoint(x: v1.x + v2.x, y: v1.y + v2.y))
            let sinHalf = sin(angleSmall / 2)
            if sinHalf > 0.0001 {
                let centerOffset = radius / sinHalf
                let center = CGPoint(x: cornerCurr.x + bisector.x * centerOffset,
                                     y: cornerCurr.y + bisector.y * centerOffset)
                let startRadians = atan2(p1.y - center.y, p1.x - center.x)
                let endRadians = atan2(p2.y - center.y, p2.x - center.x)
                var delta = endRadians - startRadians
                while delta <= -CGFloat.pi { delta += 2 * CGFloat.pi }
                while delta > CGFloat.pi { delta -= 2 * CGFloat.pi }
                let arcClockwise = delta < 0
                cornerArcs[index] = CornerArc(
                    start: p1,
                    end: p2,
                    center: center,
                    radius: radius,
                    startAngle: Angle(radians: startRadians),
                    endAngle: Angle(radians: endRadians),
                    clockwise: arcClockwise
                )
            } else {
                cornerArcs[index] = CornerArc(
                    start: p1,
                    end: p2,
                    center: nil,
                    radius: radius,
                    startAngle: nil,
                    endAngle: nil,
                    clockwise: false
                )
            }
        }

        for index in 0..<count {
            let nextIndex = (index + 1) % count
            let curr = points[index]
            let next = points[nextIndex]
            let currDraw = drawPoints[index]
            let nextDraw = drawPoints[nextIndex]

            let arc = cornerArcs[index]
            let nextArc = cornerArcs[nextIndex]
            let startPoint = arc?.start ?? currDraw

            if index == 0 {
                path.move(to: startPoint)
            }

            if let arc, let center = arc.center, let startAngle = arc.startAngle, let endAngle = arc.endAngle {
                path.addArc(center: center, radius: arc.radius, startAngle: startAngle, endAngle: endAngle, clockwise: arc.clockwise)
            } else if let arc {
                path.addLine(to: arc.end)
            }

            let segmentStart = arc?.end ?? currDraw
            let segmentEnd = nextArc?.start ?? nextDraw

            if let resolvedEdge = edgeToNextMap[index] ?? nil {
                let normal = edgeNormal(for: resolvedEdge, start: segmentStart, end: segmentEnd)
                let spanOverride = spanControlOverride(edge: resolvedEdge, start: curr, end: next)
                var curveForSegment: CurvedEdge? = spanOverride?.curve
                var controlOverride: CGPoint? = spanOverride?.control
                if curveForSegment == nil, let edgeCurve = edgeCurves[resolvedEdge] {
                    curveForSegment = edgeCurve
                    if let fullGeometry = fullEdgeGeometry(edge: resolvedEdge, bounds: bounds, hypotenuseBounds: hypotenuseBounds, shape: shape),
                       let baseControl = edgeControlOverrides[resolvedEdge] {
                        let t0 = tForEdge(point: curr, geometry: fullGeometry, edge: resolvedEdge)
                        let t1 = tForEdge(point: next, geometry: fullGeometry, edge: resolvedEdge)
                        let segment = quadSubsegment(
                            start: fullGeometry.start,
                            control: baseControl,
                            end: fullGeometry.end,
                            t0: t0,
                            t1: t1
                        )
                        controlOverride = segment.control
                    }
                }
                if let curveForSegment, curveForSegment.radius > 0 {
                    addEdgeWithCurve(path: &path, from: segmentStart, to: segmentEnd, curve: curveForSegment, normal: normal, controlOverride: controlOverride)
                } else {
                    path.addLine(to: segmentEnd)
                }
            } else {
                path.addLine(to: segmentEnd)
            }
        }

        path.closeSubpath()
        return path
    }
    
    /// Adds a curved edge segment to the path
    private static func addCurvedEdgeSegment(
        path: inout Path,
        from: CGPoint,
        to: CGPoint,
        curve: CurvedEdge,
        edge: EdgePosition,
        bounds: CGRect,
        shape: ShapeKind
    ) {
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let normal = edgeNormal(for: edge, shape: shape)
        let direction = curve.isConcave ? -1.0 : 1.0
        let control = CGPoint(
            x: mid.x + normal.x * curve.radius * 2 * direction,
            y: mid.y + normal.y * curve.radius * 2 * direction
        )
        path.addQuadCurve(to: to, control: control)
    }
    
    /// Returns the outward normal for an edge
    private static func edgeNormal(for edge: EdgePosition, shape: ShapeKind) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: 0, y: -1)
        case .right: return CGPoint(x: 1, y: 0)
        case .bottom: return CGPoint(x: 0, y: 1)
        case .left: return CGPoint(x: -1, y: 0)
        case .legA: return CGPoint(x: 0, y: -1)
        case .legB: return CGPoint(x: -1, y: 0)
        case .hypotenuse: return CGPoint(x: 0.7071, y: 0.7071) // Normalized diagonal
        }
    }

    static func concaveCornerIndices(points: [CGPoint]) -> Set<Int> {
        guard points.count > 2 else { return [] }
        let clockwise = polygonIsClockwise(points)
        var indices = Set<Int>()
        for index in 0..<points.count {
            let prev = points[(index - 1 + points.count) % points.count]
            let curr = points[index]
            let next = points[(index + 1) % points.count]
            if isConcaveCorner(prev: prev, curr: curr, next: next, clockwise: clockwise) {
                indices.insert(index)
            }
        }
        return indices
    }

    private static func isConcaveCorner(prev: CGPoint, curr: CGPoint, next: CGPoint, clockwise: Bool) -> Bool {
        let v1 = CGPoint(x: curr.x - prev.x, y: curr.y - prev.y)
        let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
        let cross = v1.x * v2.y - v1.y * v2.x
        return clockwise ? cross > 0 : cross < 0
    }

    private static func curvedRectanglePath(width: CGFloat, height: CGFloat, curves: [CurvedEdge]) -> Path {
        let curveMap = curveLookup(curves)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))

        addEdge(path: &path, from: CGPoint(x: 0, y: 0), to: CGPoint(x: width, y: 0), edge: .top, curveMap: curveMap, normal: CGPoint(x: 0, y: -1), controlOverride: nil)
        addEdge(path: &path, from: CGPoint(x: width, y: 0), to: CGPoint(x: width, y: height), edge: .right, curveMap: curveMap, normal: CGPoint(x: 1, y: 0), controlOverride: nil)
        addEdge(path: &path, from: CGPoint(x: width, y: height), to: CGPoint(x: 0, y: height), edge: .bottom, curveMap: curveMap, normal: CGPoint(x: 0, y: 1), controlOverride: nil)
        addEdge(path: &path, from: CGPoint(x: 0, y: height), to: CGPoint(x: 0, y: 0), edge: .left, curveMap: curveMap, normal: CGPoint(x: -1, y: 0), controlOverride: nil)

        path.closeSubpath()
        return path
    }

    private static func curvedRightTriangle(width: CGFloat, height: CGFloat, curves: [CurvedEdge]) -> Path {
        let curveMap = curveLookup(curves)
        let p0 = CGPoint(x: 0, y: 0)
        let p1 = CGPoint(x: width, y: 0)
        let p2 = CGPoint(x: 0, y: height)

        var path = Path()
        path.move(to: p0)
        addEdge(path: &path, from: p0, to: p1, edge: .legA, curveMap: curveMap, normal: CGPoint(x: 0, y: -1), controlOverride: nil)
        addEdge(path: &path, from: p1, to: p2, edge: .hypotenuse, curveMap: curveMap, normal: CGPoint(x: 0.7, y: 0.7), controlOverride: nil)
        addEdge(path: &path, from: p2, to: p0, edge: .legB, curveMap: curveMap, normal: CGPoint(x: -1, y: 0), controlOverride: nil)
        path.closeSubpath()
        return path
    }

    private static func curveLookup(_ curves: [CurvedEdge]) -> [EdgePosition: [CurvedEdge]] {
        var map: [EdgePosition: [CurvedEdge]] = [:]
        for curve in curves where curve.radius > 0 {
            map[curve.edge, default: []].append(curve)
        }
        // Sort each edge's curves by edge progress so they're drawn in order.
        // Full-edge curves (no span) get progress 0..1.
        for (edge, edgeCurves) in map {
            map[edge] = edgeCurves.sorted { a, b in
                let aStart: Double = (a.hasSpan && a.usesEdgeProgress) ? min(a.startEdgeProgress, a.endEdgeProgress) : 0.0
                let bStart: Double = (b.hasSpan && b.usesEdgeProgress) ? min(b.startEdgeProgress, b.endEdgeProgress) : 0.0
                return aStart < bStart
            }
        }
        return map
    }

    private static func addEdge(path: inout Path, from: CGPoint, to: CGPoint, edge: EdgePosition, curveMap: [EdgePosition: [CurvedEdge]], normal: CGPoint, controlOverride: CGPoint?) {
        guard let edgeCurves = curveMap[edge], !edgeCurves.isEmpty else {
            path.addLine(to: to)
            return
        }

        // Collect all segment curves (with span) and at most one full-edge curve.
        let segmentCurves = edgeCurves.filter { $0.hasSpan && $0.usesEdgeProgress }
        let fullEdgeCurve = edgeCurves.first(where: { !$0.hasSpan || !$0.usesEdgeProgress })

        // If there are segment curves, draw them in order along the edge.
        if !segmentCurves.isEmpty {
            // Edge progress is stored as coordinate-based (left→right for top/bottom,
            // top→bottom for left/right). But curvedRectanglePath walks bottom
            // right→left and left bottom→top. Flip progress for those edges so
            // interpolation between from→to produces correct physical positions.
            let needsFlip = (edge == .bottom || edge == .left)

            // Build sorted list of (startProgress, endProgress, curve)
            let segments: [(p0: CGFloat, p1: CGFloat, curve: CurvedEdge)] = segmentCurves.map { curve in
                var p0 = CGFloat(min(curve.startEdgeProgress, curve.endEdgeProgress))
                var p1 = CGFloat(max(curve.startEdgeProgress, curve.endEdgeProgress))
                if needsFlip {
                    let flippedP0 = 1.0 - p1
                    let flippedP1 = 1.0 - p0
                    p0 = flippedP0
                    p1 = flippedP1
                }
                return (p0, p1, curve)
            }.sorted { $0.p0 < $1.p0 }

            // Walk the edge from progress 0 to 1, drawing straight gaps and curves.
            var currentProgress: CGFloat = 0.0

            for seg in segments {
                // Straight segment from current position to curve start
                if seg.p0 > currentProgress + 0.001 {
                    let gapEnd = CGPoint(
                        x: from.x + (to.x - from.x) * seg.p0,
                        y: from.y + (to.y - from.y) * seg.p0
                    )
                    path.addLine(to: gapEnd)
                }

                // Curved segment
                let curveStart = CGPoint(
                    x: from.x + (to.x - from.x) * seg.p0,
                    y: from.y + (to.y - from.y) * seg.p0
                )
                let curveEnd = CGPoint(
                    x: from.x + (to.x - from.x) * seg.p1,
                    y: from.y + (to.y - from.y) * seg.p1
                )

                // Move to curveStart if we're not already there
                if currentProgress < seg.p0 - 0.001 {
                    // We already drew the line above
                } else if currentProgress < 0.001 && seg.p0 < 0.001 {
                    // At the start of edge, no line needed
                }

                let segMid = CGPoint(
                    x: (curveStart.x + curveEnd.x) / 2,
                    y: (curveStart.y + curveEnd.y) / 2
                )
                let direction = seg.curve.isConcave ? -1.0 : 1.0
                let segControl = CGPoint(
                    x: segMid.x + normal.x * seg.curve.radius * 2 * direction,
                    y: segMid.y + normal.y * seg.curve.radius * 2 * direction
                )
                path.addQuadCurve(to: curveEnd, control: segControl)

                currentProgress = seg.p1
            }

            // Straight segment from last curve end to edge end
            if currentProgress < 0.999 {
                path.addLine(to: to)
            }
            return
        }

        // Full-edge curve (only one possible per edge)
        guard let curve = fullEdgeCurve, curve.radius > 0 else {
            path.addLine(to: to)
            return
        }

        let control: CGPoint
        if let controlOverride {
            control = controlOverride
        } else {
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let direction = curve.isConcave ? -1.0 : 1.0
            control = CGPoint(
                x: mid.x + normal.x * curve.radius * 2 * direction,
                y: mid.y + normal.y * curve.radius * 2 * direction
            )
        }
        path.addQuadCurve(to: to, control: control)
    }

    private static func curvedPolygonPath(points: [CGPoint], shape: ShapeKind, curves: [CurvedEdge], baseBounds: CGRect?) -> Path {
        guard points.count >= 2 else { return Path() }
        let curvesByEdge = Dictionary(grouping: curves, by: { $0.edge })
        let edgeCurves = curvesByEdge.compactMapValues { curves in
            curves.first(where: { !$0.hasSpan && $0.radius > 0 })
        }
        let bounds = polygonBounds(points)
        let hypotenuseBounds = baseBounds ?? bounds
        let eps: CGFloat = 0.01
        _ = polygonIsClockwise(points)
        var drawPoints = points

        // CAD-style parametric approach: compute t-values for all points on each edge
        // A point is on the hypotenuse if it lies on the line AND has t in [0,1]
        var pointHypotenuseT: [Int: CGFloat] = [:]  // Maps point index to t-value on hypotenuse
        var hypotenuseSegmentIndices: Set<Int> = []
        
        if shape == .rightTriangle, (curvesByEdge[.hypotenuse]?.contains { $0.radius > 0 } ?? false) {
            let hypStart = CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY)
            let hypEnd = CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY)
            let hypLength = distance(hypStart, hypEnd)
            guard hypLength > 0.0001 else { return polygonPath(points) }
            
            // Direction vector of hypotenuse
            let hypDx = hypEnd.x - hypStart.x
            let hypDy = hypEnd.y - hypStart.y
            
            // For each point, compute its t-value on the hypotenuse line
            // t = projection of (point - hypStart) onto hypotenuse direction / length
            for index in 0..<points.count {
                let point = points[index]
                let px = point.x - hypStart.x
                let py = point.y - hypStart.y
                
                // Project onto hypotenuse direction
                let t = (px * hypDx + py * hypDy) / (hypLength * hypLength)
                
                // Check if point is actually ON the line (perpendicular distance)
                let projX = hypStart.x + t * hypDx
                let projY = hypStart.y + t * hypDy
                let perpDist = sqrt((point.x - projX) * (point.x - projX) + (point.y - projY) * (point.y - projY))
                
                // Point is on hypotenuse if perpendicular distance is small AND t is in valid range
                // Use larger tolerance for floating-point precision from booleanDifference
            let tolerance = hypotenuseTolerance(for: hypotenuseBounds)
            let tTolerance: CGFloat = 0.02
                if perpDist <= tolerance && t >= -tTolerance && t <= 1.0 + tTolerance {
                    pointHypotenuseT[index] = max(0, min(1, t))  // Clamp to [0,1]
                }
            }
            
            // A segment is on the hypotenuse if BOTH endpoints have valid t-values
            // AND the segment is diagonal (not horizontal/vertical notch edges)
            for index in 0..<points.count {
                let nextIndex = (index + 1) % points.count
                guard let t0 = pointHypotenuseT[index], let t1 = pointHypotenuseT[nextIndex] else { continue }
                _ = t0; _ = t1  // Silence unused variable warnings
                
                // Verify segment is actually along the hypotenuse (diagonal), not a notch edge
                let start = points[index]
                let end = points[nextIndex]
                let dx = end.x - start.x
                let dy = end.y - start.y
                
                // For a segment to be ON the hypotenuse, it must be diagonal (neither horizontal nor vertical)
                // Notch edges connecting hypotenuse points are horizontal or vertical
                if abs(dx) < eps || abs(dy) < eps { continue }
                
                hypotenuseSegmentIndices.insert(index)
            }
        }
        
        // Determine which points should actually be projected onto the hypotenuse curve.
        // A point should only be projected if it's an endpoint of a diagonal hypotenuse segment.
        // Points that are only connected to horizontal/vertical edges (notch interior corners)
        // should NOT be projected - they need to maintain their square corner positions.
        var hypotenuseProjectablePoints: Set<Int> = []
        for segmentIndex in hypotenuseSegmentIndices {
            let nextIndex = (segmentIndex + 1) % points.count
            hypotenuseProjectablePoints.insert(segmentIndex)
            hypotenuseProjectablePoints.insert(nextIndex)
        }
        
        // For hypotenuse points that are connected to notch edges (interior edges of cutouts),
        // we need to extend those edges straight to the curve instead of projecting the point.
        // This applies to horizontal/vertical edges (square to legs) AND angled edges (custom angle).
        // The notch edge direction is defined by a point on the edge and a direction vector.
        struct NotchEdgeExtension {
            let interiorPoint: CGPoint  // The interior corner point (stays fixed)
            let direction: CGPoint      // Unit direction vector along the edge
        }
        var notchEdgeExtensions: [Int: NotchEdgeExtension] = [:]
        
        // Find hypotenuse points that are connected to notch edges (non-diagonal segments)
        for pointIndex in hypotenuseProjectablePoints {
            let point = points[pointIndex]
            let prevIndex = (pointIndex - 1 + points.count) % points.count
            let nextIndex = (pointIndex + 1) % points.count
            let prevPoint = points[prevIndex]
            let nextPoint = points[nextIndex]
            
            // Check if previous segment is a notch edge (NOT on hypotenuse diagonal)
            // A segment is a notch edge if it's not in hypotenuseSegmentIndices
            let prevSegmentIndex = prevIndex  // Segment from prevPoint to point
            let nextSegmentIndex = pointIndex // Segment from point to nextPoint
            
            let prevIsNotchEdge = !hypotenuseSegmentIndices.contains(prevSegmentIndex)
            let nextIsNotchEdge = !hypotenuseSegmentIndices.contains(nextSegmentIndex)
            
            // Prefer the notch edge that connects to an interior corner
            if prevIsNotchEdge {
                // Edge goes from prevPoint (interior) to point (on hypotenuse)
                let dx = point.x - prevPoint.x
                let dy = point.y - prevPoint.y
                let length = sqrt(dx * dx + dy * dy)
                if length > eps {
                    let direction = CGPoint(x: dx / length, y: dy / length)
                    notchEdgeExtensions[pointIndex] = NotchEdgeExtension(
                        interiorPoint: prevPoint,
                        direction: direction
                    )
                }
            } else if nextIsNotchEdge {
                // Edge goes from point (on hypotenuse) to nextPoint (interior)
                let dx = nextPoint.x - point.x
                let dy = nextPoint.y - point.y
                let length = sqrt(dx * dx + dy * dy)
                if length > eps {
                    // Direction is from interior toward hypotenuse (reverse)
                    let direction = CGPoint(x: -dx / length, y: -dy / length)
                    notchEdgeExtensions[pointIndex] = NotchEdgeExtension(
                        interiorPoint: nextPoint,
                        direction: direction
                    )
                }
            }
        }
        
        // Helper function to find where a ray (line from point in direction) intersects a quadratic Bezier
        // Returns the intersection point on the curve that is in the direction from linePoint
        func rayQuadIntersection(
            linePoint: CGPoint,
            direction: CGPoint,
            curveStart: CGPoint,
            curveControl: CGPoint,
            curveEnd: CGPoint,
            nearT: CGFloat
        ) -> CGPoint? {
            // Parametric ray: R(s) = linePoint + s * direction, s >= 0
            // Quadratic Bezier: B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
            //
            // We need to find t where the ray intersects the curve.
            // Substituting and solving:
            // linePoint + s * direction = B(t)
            //
            // This gives us two equations (x and y). We can eliminate s:
            // (B(t).x - linePoint.x) / direction.x = (B(t).y - linePoint.y) / direction.y
            // Cross multiply:
            // (B(t).x - linePoint.x) * direction.y = (B(t).y - linePoint.y) * direction.x
            //
            // Let B(t) = a*t² + b*t + c for each coordinate
            // Bx(t) = ax*t² + bx*t + cx where:
            //   ax = curveStart.x - 2*curveControl.x + curveEnd.x
            //   bx = 2*(curveControl.x - curveStart.x)
            //   cx = curveStart.x
            // Similarly for y
            
            let ax = curveStart.x - 2 * curveControl.x + curveEnd.x
            let bx = 2 * (curveControl.x - curveStart.x)
            let cx = curveStart.x
            
            let ay = curveStart.y - 2 * curveControl.y + curveEnd.y
            let by = 2 * (curveControl.y - curveStart.y)
            let cy = curveStart.y
            
            // Equation: (ax*t² + bx*t + cx - linePoint.x) * direction.y 
            //         = (ay*t² + by*t + cy - linePoint.y) * direction.x
            //
            // Expanding:
            // ax*dy*t² + bx*dy*t + (cx - lx)*dy = ay*dx*t² + by*dx*t + (cy - ly)*dx
            //
            // Rearranging to standard form A*t² + B*t + C = 0:
            let dx = direction.x
            let dy = direction.y
            let lx = linePoint.x
            let ly = linePoint.y
            
            let A = ax * dy - ay * dx
            let B = bx * dy - by * dx
            let C = (cx - lx) * dy - (cy - ly) * dx
            
            var solutions: [CGFloat] = []
            if abs(A) < 0.0001 {
                // Linear case
                if abs(B) > 0.0001 {
                    solutions.append(-C / B)
                }
            } else {
                let discriminant = B * B - 4 * A * C
                if discriminant >= 0 {
                    let sqrtD = sqrt(discriminant)
                    solutions.append((-B + sqrtD) / (2 * A))
                    solutions.append((-B - sqrtD) / (2 * A))
                }
            }
            
            // Filter valid t values (on the curve) and check that s >= 0 (in the ray direction)
            var validSolutions: [(t: CGFloat, s: CGFloat)] = []
            for t in solutions {
                guard t >= -0.01 && t <= 1.01 else { continue }
                let clampedT = max(0, min(1, t))
                let curvePoint = quadPoint(start: curveStart, control: curveControl, end: curveEnd, t: clampedT)
                
                // Calculate s (how far along the ray)
                let s: CGFloat
                if abs(dx) > abs(dy) {
                    s = (curvePoint.x - lx) / dx
                } else if abs(dy) > 0.0001 {
                    s = (curvePoint.y - ly) / dy
                } else {
                    continue
                }
                
                // s should be positive (in the direction of the ray)
                if s >= -0.01 {
                    validSolutions.append((clampedT, s))
                }
            }
            
            // Pick the solution closest to nearT
            guard let best = validSolutions.min(by: { abs($0.t - nearT) < abs($1.t - nearT) }) else {
                return nil
            }
            return quadPoint(start: curveStart, control: curveControl, end: curveEnd, t: best.t)
        }
        
        // Edge-based control overrides for non-span curves
        var edgeControlOverrides: [EdgePosition: CGPoint] = [:]
        for (edge, curve) in edgeCurves where curve.radius > 0 {
            if let geometry = fullEdgeGeometry(edge: edge, bounds: bounds, hypotenuseBounds: hypotenuseBounds, shape: shape) {
                let mid = CGPoint(x: (geometry.start.x + geometry.end.x) / 2, y: (geometry.start.y + geometry.end.y) / 2)
                let direction = curve.isConcave ? -1.0 : 1.0
                edgeControlOverrides[edge] = CGPoint(
                    x: mid.x + geometry.normal.x * curve.radius * 2 * direction,
                    y: mid.y + geometry.normal.y * curve.radius * 2 * direction
                )
            }
        }

        func segmentTValue(start: CGPoint, end: CGPoint, index: Int, nextIndex: Int, edge: EdgePosition, geometry: (start: CGPoint, end: CGPoint, normal: CGPoint)) -> (t0: CGFloat, t1: CGFloat) {
            if edge == .hypotenuse, let preT0 = pointHypotenuseT[index], let preT1 = pointHypotenuseT[nextIndex] {
                return (preT0, preT1)
            }
            let t0 = tForEdge(point: start, geometry: geometry, edge: edge)
            let t1 = tForEdge(point: end, geometry: geometry, edge: edge)
            return (t0, t1)
        }
        
        // Span-based control overrides for span curves
        var spanControlOverrides: [UUID: [Int: CGPoint]] = [:]
        let pointCount = points.count
        let boundarySegments = boundarySegments(for: points, shape: shape, bounds: bounds, hypotenuseBounds: shape == .rightTriangle ? hypotenuseBounds : nil)
        for curve in curves where curve.hasSpan && curve.radius > 0 {
            guard pointCount > 1 else { continue }
            guard let span = spanIndices(for: curve, boundarySegments: boundarySegments, pointCount: pointCount, bounds: bounds, shape: shape) else { continue }
            if span.start == span.end { continue }
            let spanStart = points[span.start]
            let spanEnd = points[span.end]
            guard let spanEdge = edgeForSpanPoints(
                start: spanStart,
                end: spanEnd,
                points: points,
                bounds: bounds,
                hypotenuseBounds: hypotenuseBounds,
                shape: shape
            ) else { continue }
            guard let fullGeometry = fullEdgeGeometry(edge: spanEdge, bounds: bounds, hypotenuseBounds: hypotenuseBounds, shape: shape) else { continue }
            let edgeSegments = edgeSegmentsForPoints(
                points: points,
                edge: spanEdge,
                shape: shape,
                bounds: bounds,
                hypotenuseBounds: hypotenuseBounds
            )
            guard !edgeSegments.isEmpty else { continue }
            guard spanPathIsValid(
                points: points,
                startIndex: span.start,
                endIndex: span.end,
                edge: spanEdge,
                shape: shape,
                hypotenuseBounds: hypotenuseBounds,
                bounds: bounds
            ) else { continue }
            let spanDx = spanEnd.x - spanStart.x
            let spanDy = spanEnd.y - spanStart.y
            let spanDenom = spanDx * spanDx + spanDy * spanDy
            guard spanDenom > 0.0001 else { continue }

            func spanParam(_ point: CGPoint) -> CGFloat {
                return ((point.x - spanStart.x) * spanDx + (point.y - spanStart.y) * spanDy) / spanDenom
            }

            let sStart = spanParam(spanStart)
            let sEnd = spanParam(spanEnd)
            let sMin = min(sStart, sEnd)
            let sMax = max(sStart, sEnd)
            let direction = curve.isConcave ? -1.0 : 1.0

            if abs(sMax - sMin) < 0.0001 {
                continue
            }

            let mid = CGPoint(x: (spanStart.x + spanEnd.x) / 2, y: (spanStart.y + spanEnd.y) / 2)
            let control = CGPoint(
                x: mid.x + fullGeometry.normal.x * curve.radius * 2 * direction,
                y: mid.y + fullGeometry.normal.y * curve.radius * 2 * direction
            )

            for edgeSegment in edgeSegments {
                let segT0 = spanParam(edgeSegment.start)
                let segT1 = spanParam(edgeSegment.end)
                let segMin = min(segT0, segT1)
                let segMax = max(segT0, segT1)
                if segMax < sMin || segMin > sMax { continue }
                let t0 = (segT0 - sMin) / max(sMax - sMin, 0.0001)
                let t1 = (segT1 - sMin) / max(sMax - sMin, 0.0001)
                let segment = quadSubsegment(
                    start: spanStart,
                    control: control,
                    end: spanEnd,
                    t0: t0,
                    t1: t1
                )
                spanControlOverrides[curve.id, default: [:]][edgeSegment.startIndex] = segment.control
            }

            for pointIndex in 0..<points.count {
                let point = points[pointIndex]
                let t = spanParam(point)
                if t < sMin - 0.0001 || t > sMax + 0.0001 { continue }
                switch spanEdge {
                case .left, .right, .legB:
                    if abs(point.x - fullGeometry.start.x) > 1.0 { continue }
                case .top, .bottom, .legA:
                    if abs(point.y - fullGeometry.start.y) > 1.0 { continue }
                case .hypotenuse:
                    // Only project points that are endpoints of diagonal hypotenuse segments.
                    // This excludes notch interior corners which should maintain square positions.
                    if !hypotenuseProjectablePoints.contains(pointIndex) { continue }
                    if !pointIsOnEdge(point, edge: .hypotenuse, bounds: hypotenuseBounds, shape: shape, tolerance: hypotenuseTolerance(for: hypotenuseBounds)) {
                        continue
                    }
                    
                    // Check if this point is connected to a notch edge
                    // If so, extend that edge straight to the curve instead of projecting parametrically
                    if let notchExtension = notchEdgeExtensions[pointIndex] {
                        if let intersection = rayQuadIntersection(
                            linePoint: notchExtension.interiorPoint,
                            direction: notchExtension.direction,
                            curveStart: spanStart,
                            curveControl: control,
                            curveEnd: spanEnd,
                            nearT: t
                        ) {
                            drawPoints[pointIndex] = intersection
                            continue
                        }
                    }
                }
                drawPoints[pointIndex] = quadPoint(start: spanStart, control: control, end: spanEnd, t: t)
            }
        }

        // Identify notch edge extension points for non-hypotenuse curved edges.
        // When booleanDifference clips a notch to the straight edge and the curve then
        // projects those edge points inward, the notch geometry can invert (interior corners
        // end up outside the projected edge points). To fix this, we detect edge points
        // connected to interior (notch) segments and extend those segments to meet the curve
        // via rayQuadIntersection, just as the hypotenuse already does.
        struct NonHypExtension {
            let interiorPoint: CGPoint
            let direction: CGPoint
            let length: CGFloat
        }
        var nonHypNotchExtensions: [Int: NonHypExtension] = [:]
        let edgeTol: CGFloat = 0.5
        for (nhEdge, nhCurve) in edgeCurves where nhCurve.radius > 0 && nhEdge != .hypotenuse {
            for index in 0..<points.count {
                let nextIndex = (index + 1) % points.count
                let a = points[index]
                let b = points[nextIndex]
                let aOnEdge = pointIsOnEdge(a, edge: nhEdge, bounds: hypotenuseBounds, shape: shape, tolerance: edgeTol)
                let bOnEdge = pointIsOnEdge(b, edge: nhEdge, bounds: hypotenuseBounds, shape: shape, tolerance: edgeTol)
                if aOnEdge == bOnEdge {
                    continue
                }

                let onEdgeIndex = aOnEdge ? index : nextIndex
                let onEdgePoint = aOnEdge ? a : b
                let interiorPoint = aOnEdge ? b : a
                let dx = onEdgePoint.x - interiorPoint.x
                let dy = onEdgePoint.y - interiorPoint.y
                let length = sqrt(dx * dx + dy * dy)
                if length <= eps {
                    continue
                }
                let direction = CGPoint(x: dx / length, y: dy / length)
                let candidate = NonHypExtension(interiorPoint: interiorPoint, direction: direction, length: length)
                if let existing = nonHypNotchExtensions[onEdgeIndex], existing.length >= candidate.length {
                    continue
                }
                nonHypNotchExtensions[onEdgeIndex] = candidate
            }
        }

        // Project edge points onto full-edge curves so notch edges meet the curve.
        for (edge, curve) in edgeCurves where curve.radius > 0 {
            guard let geometry = fullEdgeGeometry(edge: edge, bounds: bounds, hypotenuseBounds: hypotenuseBounds, shape: shape),
                  let control = edgeControlOverrides[edge] else { continue }
            let tolerance = edge == .hypotenuse ? hypotenuseTolerance(for: hypotenuseBounds) : 0.5
            let spanRange: (min: CGFloat, max: CGFloat)?
            if curve.hasSpan, curve.usesEdgeProgress {
                spanRange = (CGFloat(min(curve.startEdgeProgress, curve.endEdgeProgress)),
                             CGFloat(max(curve.startEdgeProgress, curve.endEdgeProgress)))
            } else {
                spanRange = nil
            }
            for pointIndex in 0..<points.count {
                let point = points[pointIndex]
                if edge == .hypotenuse {
                    // Only project points that are endpoints of diagonal hypotenuse segments.
                    // This excludes notch interior corners which should maintain square positions.
                    guard hypotenuseProjectablePoints.contains(pointIndex) else { continue }
                    guard let preT = pointHypotenuseT[pointIndex] else { continue }
                    
                    // Check if this point is connected to a notch edge
                    // If so, extend that edge straight to the curve instead of projecting parametrically
                    if let notchExtension = notchEdgeExtensions[pointIndex] {
                        if let intersection = rayQuadIntersection(
                            linePoint: notchExtension.interiorPoint,
                            direction: notchExtension.direction,
                            curveStart: geometry.start,
                            curveControl: control,
                            curveEnd: geometry.end,
                            nearT: preT
                        ) {
                            drawPoints[pointIndex] = intersection
                            continue
                        }
                    }
                    
                    // Standard parametric projection for non-notch hypotenuse points
                    if let spanRange, (preT < spanRange.min - 0.0001 || preT > spanRange.max + 0.0001) {
                        continue
                    }
                    drawPoints[pointIndex] = quadPoint(start: geometry.start, control: control, end: geometry.end, t: preT)
                } else {
                    if !pointIsOnEdge(point, edge: edge, bounds: hypotenuseBounds, shape: shape, tolerance: tolerance) {
                        continue
                    }
                    let t = tForEdge(point: point, geometry: geometry, edge: edge)
                    if let spanRange, (t < spanRange.min - 0.0001 || t > spanRange.max + 0.0001) {
                        continue
                    }
                    // For notch edge points, extend the notch edge to meet the curve
                    // instead of simple parametric projection (which can invert geometry
                    // when the curve is inward of the straight edge at this location)
                    if let notchExt = nonHypNotchExtensions[pointIndex] {
                        if let intersection = rayQuadIntersection(
                            linePoint: notchExt.interiorPoint,
                            direction: notchExt.direction,
                            curveStart: geometry.start,
                            curveControl: control,
                            curveEnd: geometry.end,
                            nearT: t
                        ) {
                            drawPoints[pointIndex] = intersection
                            continue
                        }
                    }
                    drawPoints[pointIndex] = quadPoint(start: geometry.start, control: control, end: geometry.end, t: t)
                }
            }
        }

        var path = Path()
        path.move(to: drawPoints[0])
        let count = points.count
        for index in 0..<count {
            let start = drawPoints[index]
            let end = drawPoints[(index + 1) % count]
            let originalStart = points[index]
            let originalEnd = points[(index + 1) % count]
            let nextIndex = (index + 1) % count
            
            // For hypotenuse segments, use pre-computed t-values (CAD-style parametric approach)
            let isHypotenuseSegment = hypotenuseSegmentIndices.contains(index)
            
            var edge = edgeForSegment(start: originalStart, end: originalEnd, bounds: bounds, shape: shape, hypotenuseBounds: hypotenuseBounds)
            
            // Override edge detection for hypotenuse segments identified parametrically
            if edge == nil && isHypotenuseSegment {
                edge = .hypotenuse
            }
            
            guard let resolvedEdge = edge else {
                path.addLine(to: end)
                continue
            }
            
            let normal = edgeNormal(for: resolvedEdge, start: start, end: end)
            var segmentControl: CGPoint? = nil
            var curveForSegment: CurvedEdge? = nil
            
            if let curvesForEdge = curvesByEdge[resolvedEdge] {
                if let spanCurve = curvesForEdge.first(where: { $0.hasSpan && spanControlOverrides[$0.id]?[index] != nil }) {
                    curveForSegment = spanCurve
                    segmentControl = spanControlOverrides[spanCurve.id]?[index]
                } else if let edgeCurve = curvesForEdge.first(where: { $0.radius > 0 }) {
                    if let fullGeometry = fullEdgeGeometry(edge: resolvedEdge, bounds: bounds, hypotenuseBounds: hypotenuseBounds, shape: shape),
                       let baseControl = edgeControlOverrides[resolvedEdge] {
                        let tValues = segmentTValue(start: originalStart, end: originalEnd, index: index, nextIndex: nextIndex, edge: resolvedEdge, geometry: fullGeometry)
                        let t0 = tValues.t0
                        let t1 = tValues.t1

                        if edgeCurve.hasSpan, edgeCurve.usesEdgeProgress {
                            let sMin = CGFloat(min(edgeCurve.startEdgeProgress, edgeCurve.endEdgeProgress))
                            let sMax = CGFloat(max(edgeCurve.startEdgeProgress, edgeCurve.endEdgeProgress))
                            let segMin = min(t0, t1)
                            let segMax = max(t0, t1)
                            if segMax < sMin || segMin > sMax {
                                curveForSegment = nil
                            } else {
                                curveForSegment = edgeCurve
                                let segment = quadSubsegment(
                                    start: fullGeometry.start,
                                    control: baseControl,
                                    end: fullGeometry.end,
                                    t0: t0,
                                    t1: t1
                                )
                                segmentControl = segment.control
                            }
                        } else {
                            curveForSegment = edgeCurve
                            let segment = quadSubsegment(
                                start: fullGeometry.start,
                                control: baseControl,
                                end: fullGeometry.end,
                                t0: t0,
                                t1: t1
                            )
                            segmentControl = segment.control
                        }
                    }
                }
            }
            addEdgeWithCurve(path: &path, from: start, to: end, curve: curveForSegment, normal: normal, controlOverride: segmentControl)
        }
        path.closeSubpath()
        return path
    }
    
    private static func addEdgeWithCurve(path: inout Path, from: CGPoint, to: CGPoint, curve: CurvedEdge?, normal: CGPoint, controlOverride: CGPoint?) {
        guard let curve, curve.radius > 0 else {
            path.addLine(to: to)
            return
        }
        let control: CGPoint
        if let controlOverride {
            control = controlOverride
        } else {
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let direction = curve.isConcave ? -1.0 : 1.0
            control = CGPoint(
                x: mid.x + normal.x * curve.radius * 2 * direction,
                y: mid.y + normal.y * curve.radius * 2 * direction
            )
        }
        path.addQuadCurve(to: to, control: control)
    }

    private static func fullEdgeGeometry(edge: EdgePosition, bounds: CGRect, hypotenuseBounds: CGRect, shape: ShapeKind) -> (start: CGPoint, end: CGPoint, normal: CGPoint)? {
        switch shape {
        case .rightTriangle:
            switch edge {
            case .legA:
                return (CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.minY), CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY), CGPoint(x: 0, y: -1))
            case .legB:
                return (CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY), CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.minY), CGPoint(x: -1, y: 0))
            case .hypotenuse:
                let start = CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY)
                let end = CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY)
                let direction = unitVector(from: start, to: end)
                let normal = CGPoint(x: direction.y, y: -direction.x)
                return (start, end, normal)
            default:
                return nil
            }
        default:
            switch edge {
            case .top:
                return (CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY), CGPoint(x: 0, y: -1))
            case .right:
                return (CGPoint(x: bounds.maxX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: 1, y: 0))
            case .bottom:
                return (CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: 0, y: 1))
            case .left:
                return (CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: -1, y: 0))
            default:
                return nil
            }
        }
    }

    private static func tForEdge(point: CGPoint, geometry: (start: CGPoint, end: CGPoint, normal: CGPoint), edge: EdgePosition) -> CGFloat {
        switch edge {
        case .top, .bottom, .legA:
            let denom = geometry.end.x - geometry.start.x
            if abs(denom) < 0.0001 { return 0 }
            return (point.x - geometry.start.x) / denom
        case .left, .right, .legB:
            let denom = geometry.end.y - geometry.start.y
            if abs(denom) < 0.0001 { return 0 }
            return (point.y - geometry.start.y) / denom
        case .hypotenuse:
            // Use projection onto the hypotenuse line instead of raw distance
            // This correctly handles points that are slightly off the line (e.g., from booleanDifference)
            let dx = geometry.end.x - geometry.start.x
            let dy = geometry.end.y - geometry.start.y
            let lengthSquared = dx * dx + dy * dy
            if lengthSquared < 0.0001 { return 0 }
            let px = point.x - geometry.start.x
            let py = point.y - geometry.start.y
            return (px * dx + py * dy) / lengthSquared
        }
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func isFullEdgeSpanCurve(_ curve: CurvedEdge, for edge: EdgePosition, shape: ShapeKind) -> Bool {
        if curve.usesEdgeProgress {
            let low = min(curve.startEdgeProgress, curve.endEdgeProgress)
            let high = max(curve.startEdgeProgress, curve.endEdgeProgress)
            return low <= 0.02 && high >= 0.98
        }
        if curve.usesCornerIndices {
            let adjacent = cornersAdjacentToEdge(edge, shape: shape)
            guard adjacent.count == 2 else { return false }
            let set = Set(adjacent)
            return set.contains(curve.startCornerIndex) && set.contains(curve.endCornerIndex)
        }
        return false
    }

    private static func quadSplit(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat)
        -> (left: (start: CGPoint, control: CGPoint, end: CGPoint), right: (start: CGPoint, control: CGPoint, end: CGPoint)) {
        let p0 = start
        let p1 = control
        let p2 = end
        let p01 = lerp(p0, p1, t)
        let p12 = lerp(p1, p2, t)
        let p012 = lerp(p01, p12, t)
        return (
            left: (start: p0, control: p01, end: p012),
            right: (start: p012, control: p12, end: p2)
        )
    }

    private static func quadSubsegment(start: CGPoint, control: CGPoint, end: CGPoint, t0: CGFloat, t1: CGFloat)
        -> (start: CGPoint, control: CGPoint, end: CGPoint) {
        let clampedT0 = min(max(t0, 0), 1)
        let clampedT1 = min(max(t1, 0), 1)
        let low = min(clampedT0, clampedT1)
        let high = max(clampedT0, clampedT1)
        if high <= 0.0001 {
            return (start: start, control: control, end: start)
        }
        if low <= 0.0001 && high >= 0.9999 {
            return (start: start, control: control, end: end)
        }
        let firstSplit = quadSplit(start: start, control: control, end: end, t: high)
        if low <= 0.0001 {
            return firstSplit.left
        }
        let t = high <= 0.0001 ? 0 : low / high
        let secondSplit = quadSplit(start: firstSplit.left.start, control: firstSplit.left.control, end: firstSplit.left.end, t: t)
        return secondSplit.right
    }

    private static func edgeForSegment(start: CGPoint, end: CGPoint, bounds: CGRect, shape: ShapeKind, hypotenuseBounds: CGRect) -> EdgePosition? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let eps: CGFloat = 0.01
        let edgeTolerance: CGFloat = 0.5
        switch shape {
        case .rightTriangle:
            // For right triangles, we need to check if the segment is actually ON the edge,
            // not just has the same orientation. This prevents notch segments from being
            // misclassified as leg edges.
            if abs(dy) < eps {
                // Horizontal segment - check if it's on legA (y = minY in display coords)
                let y = (start.y + end.y) / 2
                if abs(y - hypotenuseBounds.minY) < edgeTolerance {
                    return .legA
                }
            }
            if abs(dx) < eps {
                // Vertical segment - check if it's on legB (x = minX in display coords)
                let x = (start.x + end.x) / 2
                if abs(x - hypotenuseBounds.minX) < edgeTolerance {
                    return .legB
                }
            }
            // Check hypotenuse - diagonal segments near the hypotenuse line
            return segmentIsOnHypotenuse(start: start, end: end, bounds: hypotenuseBounds) ? .hypotenuse : nil
        default:
            if abs(dy) < eps {
                let y = (start.y + end.y) / 2
                if abs(y - bounds.minY) < edgeTolerance {
                    return .top
                }
                if abs(y - bounds.maxY) < edgeTolerance {
                    return .bottom
                }
            }
            if abs(dx) < eps {
                let x = (start.x + end.x) / 2
                if abs(x - bounds.minX) < edgeTolerance {
                    return .left
                }
                if abs(x - bounds.maxX) < edgeTolerance {
                    return .right
                }
            }
            return nil
        }
    }

    private static func segmentIsOnHypotenuse(start: CGPoint, end: CGPoint, bounds: CGRect) -> Bool {
        let a = CGPoint(x: bounds.maxX, y: bounds.minY)
        let b = CGPoint(x: bounds.minX, y: bounds.maxY)
        // CAD-style tolerance scaled to model size (small absolute floor).
        let tolerance = hypotenuseTolerance(for: bounds)
        let startDist = pointLineDistance(point: start, a: a, b: b)
        let endDist = pointLineDistance(point: end, a: a, b: b)
        let isOnHyp = startDist <= tolerance && endDist <= tolerance
        
        // Additional check: segment must be diagonal (not horizontal or vertical)
        // This filters out notch edges that happen to have both endpoints near the hypotenuse
        let dx = abs(end.x - start.x)
        let dy = abs(end.y - start.y)
        let segmentLength = sqrt(dx * dx + dy * dy)
        let isDiagonal = dx > 0.01 && dy > 0.01 && segmentLength > 0.1
        
        return isOnHyp && isDiagonal
    }

    private static func hypotenuseTolerance(for bounds: CGRect) -> CGFloat {
        let scale = max(max(bounds.width, bounds.height), 1)
        return max(0.05, scale * 0.002)
    }

    private static func segmentIsNearHypotenuse(start: CGPoint, end: CGPoint, bounds: CGRect, tolerance: CGFloat) -> Bool {
        let a = CGPoint(x: bounds.maxX, y: bounds.minY)
        let b = CGPoint(x: bounds.minX, y: bounds.maxY)
        return pointLineDistance(point: start, a: a, b: b) <= tolerance &&
            pointLineDistance(point: end, a: a, b: b) <= tolerance
    }

    private static func pointLineDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let denom = max(sqrt(dx * dx + dy * dy), 0.0001)
        return abs(dy * point.x - dx * point.y + b.x * a.y - b.y * a.x) / denom
    }

    private static func pointIsOnEdge(_ point: CGPoint, edge: EdgePosition, bounds: CGRect, shape: ShapeKind, tolerance: CGFloat) -> Bool {
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
            return abs(point.y - bounds.minY) <= tolerance
        case .legB:
            return abs(point.x - bounds.minX) <= tolerance
        case .hypotenuse:
            guard shape == .rightTriangle else { return false }
            let start = CGPoint(x: bounds.maxX, y: bounds.minY)
            let end = CGPoint(x: bounds.minX, y: bounds.maxY)
            let distance = pointLineDistance(point: point, a: start, b: end)
            if distance > tolerance { return false }
            let minX = min(start.x, end.x) - tolerance
            let maxX = max(start.x, end.x) + tolerance
            let minY = min(start.y, end.y) - tolerance
            let maxY = max(start.y, end.y) + tolerance
            return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }
    }

    private static func edgeNormal(for edge: EdgePosition, start: CGPoint, end: CGPoint) -> CGPoint {
        switch edge {
        case .top:
            return CGPoint(x: 0, y: -1)
        case .bottom:
            return CGPoint(x: 0, y: 1)
        case .left:
            return CGPoint(x: -1, y: 0)
        case .right:
            return CGPoint(x: 1, y: 0)
        case .legA:
            return CGPoint(x: 0, y: -1)
        case .legB:
            return CGPoint(x: -1, y: 0)
        case .hypotenuse:
            let direction = unitVector(from: start, to: end)
            return CGPoint(x: direction.y, y: -direction.x)
        }
    }
    
    // MARK: - Span Curve Support
    
    private static func quadPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let clamped = min(max(t, 0), 1)
        let inv = 1 - clamped
        let x = inv * inv * start.x + 2 * inv * clamped * control.x + clamped * clamped * end.x
        let y = inv * inv * start.y + 2 * inv * clamped * control.y + clamped * clamped * end.y
        return CGPoint(x: x, y: y)
    }
    
    private static func edgeForSpanPoints(
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint],
        bounds: CGRect,
        hypotenuseBounds: CGRect,
        shape: ShapeKind
    ) -> EdgePosition? {
        let edgeTolerance: CGFloat = 0.5
        switch shape {
        case .rightTriangle:
            let onLegA = abs(start.y - hypotenuseBounds.minY) < edgeTolerance && abs(end.y - hypotenuseBounds.minY) < edgeTolerance
            if onLegA { return .legA }
            let onLegB = abs(start.x - hypotenuseBounds.minX) < edgeTolerance && abs(end.x - hypotenuseBounds.minX) < edgeTolerance
            if onLegB { return .legB }
            let a = CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY)
            let b = CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY)
            let tolerance = hypotenuseTolerance(for: hypotenuseBounds)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let denom = max(dx * dx + dy * dy, 0.0001)
            let tStart = ((start.x - a.x) * dx + (start.y - a.y) * dy) / denom
            let tEnd = ((end.x - a.x) * dx + (end.y - a.y) * dy) / denom
            let tTolerance: CGFloat = 0.02
            let onHypotenuse = pointLineDistance(point: start, a: a, b: b) <= tolerance &&
                pointLineDistance(point: end, a: a, b: b) <= tolerance &&
                tStart >= -tTolerance && tStart <= 1 + tTolerance &&
                tEnd >= -tTolerance && tEnd <= 1 + tTolerance
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
            return edgeForSpanPointsBySegments(
                start: start,
                end: end,
                points: points,
                bounds: bounds,
                hypotenuseBounds: hypotenuseBounds,
                shape: shape,
                tolerance: edgeTolerance
            )
        }
    }

    private static func edgeForSpanPointsBySegments(
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint],
        bounds: CGRect,
        hypotenuseBounds: CGRect,
        shape: ShapeKind,
        tolerance: CGFloat
    ) -> EdgePosition? {
        guard points.count > 1 else { return nil }
        let count = points.count
        var bestStart: (edge: EdgePosition, distance: CGFloat)?
        var bestEnd: (edge: EdgePosition, distance: CGFloat)?
        for index in 0..<count {
            let segStart = points[index]
            let segEnd = points[(index + 1) % count]
            guard let edge = edgeForSegment(
                start: segStart,
                end: segEnd,
                bounds: bounds,
                shape: shape,
                hypotenuseBounds: hypotenuseBounds
            ) else { continue }
            let distStart = pointSegmentDistance(point: start, a: segStart, b: segEnd)
            let distEnd = pointSegmentDistance(point: end, a: segStart, b: segEnd)
            if distStart < (bestStart?.distance ?? .greatestFiniteMagnitude) {
                bestStart = (edge, distStart)
            }
            if distEnd < (bestEnd?.distance ?? .greatestFiniteMagnitude) {
                bestEnd = (edge, distEnd)
            }
        }
        guard let startEdge = bestStart, let endEdge = bestEnd else { return nil }
        if startEdge.edge == endEdge.edge && startEdge.distance <= tolerance && endEdge.distance <= tolerance {
            return startEdge.edge
        }
        return nil
    }

    private static func pointSegmentDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let denom = dx * dx + dy * dy
        if denom < 0.0001 {
            return distance(point, a)
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / denom))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return distance(point, proj)
    }

    private static func edgeSegmentsForPoints(
        points: [CGPoint],
        edge: EdgePosition,
        shape: ShapeKind,
        bounds: CGRect,
        hypotenuseBounds: CGRect
    ) -> [BoundarySegment] {
        guard points.count > 1 else { return [] }
        let eps: CGFloat = 0.001
        var rawSegments: [(EdgePosition, Int, Int, CGPoint, CGPoint)] = []
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            if shape == .rightTriangle {
                if abs(dy) < eps, abs(a.y - bounds.minY) < eps {
                    rawSegments.append((.legA, i, (i + 1) % points.count, a, b))
                } else if abs(dx) < eps, abs(a.x - bounds.minX) < eps {
                    rawSegments.append((.legB, i, (i + 1) % points.count, a, b))
                } else if segmentIsOnHypotenuse(start: a, end: b, bounds: hypotenuseBounds) {
                    rawSegments.append((.hypotenuse, i, (i + 1) % points.count, a, b))
                }
            } else {
                if abs(dy) < eps {
                    if abs(a.y - bounds.minY) < eps {
                        rawSegments.append((.top, i, (i + 1) % points.count, a, b))
                    } else if abs(a.y - bounds.maxY) < eps {
                        rawSegments.append((.bottom, i, (i + 1) % points.count, a, b))
                    }
                } else if abs(dx) < eps {
                    if abs(a.x - bounds.minX) < eps {
                        rawSegments.append((.left, i, (i + 1) % points.count, a, b))
                    } else if abs(a.x - bounds.maxX) < eps {
                        rawSegments.append((.right, i, (i + 1) % points.count, a, b))
                    }
                }
            }
        }
        let edgeSegments = rawSegments.filter { $0.0 == edge }.sorted { lhs, rhs in
            switch edge {
            case .top, .bottom, .legA:
                return min(lhs.3.x, lhs.4.x) < min(rhs.3.x, rhs.4.x)
            case .left, .right, .legB:
                return min(lhs.3.y, lhs.4.y) < min(rhs.3.y, rhs.4.y)
            case .hypotenuse:
                let midL = CGPoint(x: (lhs.3.x + lhs.4.x) / 2, y: (lhs.3.y + lhs.4.y) / 2)
                let midR = CGPoint(x: (rhs.3.x + rhs.4.x) / 2, y: (rhs.3.y + rhs.4.y) / 2)
                let tL = ((hypotenuseBounds.maxX - midL.x) / max(hypotenuseBounds.maxX - hypotenuseBounds.minX, 0.0001))
                let tR = ((hypotenuseBounds.maxX - midR.x) / max(hypotenuseBounds.maxX - hypotenuseBounds.minX, 0.0001))
                return tL < tR
            }
        }
        return edgeSegments.enumerated().map { index, segment in
            BoundarySegment(edge: segment.0, index: index, startIndex: segment.1, endIndex: segment.2, start: segment.3, end: segment.4)
        }
    }

    static func spanPathIsValid(
        points: [CGPoint],
        startIndex: Int,
        endIndex: Int,
        edge: EdgePosition,
        shape: ShapeKind,
        hypotenuseBounds: CGRect,
        bounds: CGRect
    ) -> Bool {
        guard points.count > 1 else { return false }
        let count = points.count
        if startIndex < 0 || endIndex < 0 || startIndex >= count || endIndex >= count { return false }
        if startIndex == endIndex { return false }

        let edgeSegments = edgeSegmentsForPoints(
            points: points,
            edge: edge,
            shape: shape,
            bounds: bounds,
            hypotenuseBounds: hypotenuseBounds
        )
        guard !edgeSegments.isEmpty else { return false }
        let startPoint = points[startIndex]
        let endPoint = points[endIndex]
        if !pointIsOnEdgeSegments(point: startPoint, segments: edgeSegments) ||
            !pointIsOnEdgeSegments(point: endPoint, segments: edgeSegments) {
            return false
        }
        var edgeEndpoints: Set<Int> = []
        for segment in edgeSegments {
            edgeEndpoints.insert(segment.startIndex)
            edgeEndpoints.insert(segment.endIndex)
        }
        if !edgeEndpoints.contains(startIndex) || !edgeEndpoints.contains(endIndex) {
            return false
        }

        func segmentEdge(_ a: CGPoint, _ b: CGPoint) -> EdgePosition? {
            return edgeForSegment(start: a, end: b, bounds: bounds, shape: shape, hypotenuseBounds: hypotenuseBounds)
        }

        func validate(step: Int) -> Bool {
            var index = startIndex
            var hasTarget = false
            var spanIndices: [Int] = []
            while index != endIndex {
                let next = (index + step + count) % count
                spanIndices.append(index)
                let segStart = step > 0 ? points[index] : points[next]
                let segEnd = step > 0 ? points[next] : points[index]
                if let segEdge = segmentEdge(segStart, segEnd) {
                    if segEdge != edge { return false }
                    hasTarget = true
                }
                index = next
            }
            spanIndices.append(endIndex)
            guard hasTarget else { return false }
            return spanCoversWholeEdgeSegments(
                indices: spanIndices,
                edgeSegments: edgeSegments
            )
        }

        return validate(step: 1) || validate(step: -1)
    }

    private static func spanCoversWholeEdgeSegments(indices: [Int], edgeSegments: [BoundarySegment]) -> Bool {
        guard indices.count >= 2 else { return false }
        let spanSet = Set(indices)
        for segment in edgeSegments {
            let a = segment.startIndex
            let b = segment.endIndex
            let hasA = spanSet.contains(a)
            let hasB = spanSet.contains(b)
            if hasA != hasB {
                return false
            }
        }
        return true
    }

    private static func pointIsOnEdgeSegments(point: CGPoint, segments: [BoundarySegment]) -> Bool {
        let eps: CGFloat = 0.01
        for segment in segments {
            let dx = segment.end.x - segment.start.x
            let dy = segment.end.y - segment.start.y
            if abs(dx) < eps {
                let within = point.y >= min(segment.start.y, segment.end.y) - eps &&
                    point.y <= max(segment.start.y, segment.end.y) + eps
                if abs(point.x - segment.start.x) < eps && within {
                    return true
                }
            } else if abs(dy) < eps {
                let within = point.x >= min(segment.start.x, segment.end.x) - eps &&
                    point.x <= max(segment.start.x, segment.end.x) + eps
                if abs(point.y - segment.start.y) < eps && within {
                    return true
                }
            } else {
                let dist = pointSegmentDistance(point: point, a: segment.start, b: segment.end)
                if dist <= eps {
                    return true
                }
            }
        }
        return false
    }
}
