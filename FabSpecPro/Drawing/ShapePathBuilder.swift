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

enum CutoutCornerPosition: Int {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

enum ShapePathBuilder {
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

    static func boundarySegments(for piece: Piece) -> [BoundarySegment] {
        let points = displayPolygonPoints(for: piece, includeAngles: true)
        guard points.count >= 2 else { return [] }
        let eps: CGFloat = 0.001
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0

        var rawSegments: [(EdgePosition, Int, Int, CGPoint, CGPoint)] = []
        for i in 0..<points.count {
            let a = points[i]
            let nextIndex = (i + 1) % points.count
            let b = points[nextIndex]
            let dx = b.x - a.x
            let dy = b.y - a.y
            if piece.shape == .rightTriangle {
                if abs(dy) < eps, abs(a.y - minY) < eps {
                    rawSegments.append((.legA, i, nextIndex, a, b))
                } else if abs(dx) < eps, abs(a.x - minX) < eps {
                    rawSegments.append((.legB, i, nextIndex, a, b))
                } else if segmentIsOnHypotenuse(start: a, end: b, bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)) {
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
        let edges: [EdgePosition] = piece.shape == .rightTriangle ? [.legA, .hypotenuse, .legB] : [.top, .right, .bottom, .left]
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
        let notches = notchCandidates(for: piece, size: rawSize)
        let pieceAngleCuts = boundaryAngleCuts(for: piece)
        let activeCurves = piece.curvedEdges.filter { $0.radius > 0 }
        
        // Filter out corner radii that conflict with curved edges
        let curveOccupiedCorners = cornerIndicesOccupiedByCurves(curves: activeCurves, shape: piece.shape)
        let cornerRadii = allCornerRadii.filter { !curveOccupiedCorners.contains($0.cornerIndex) }
        
        if piece.shape == .rectangle, (!notches.isEmpty || !piece.angleCuts.isEmpty) {
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: pieceAngleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            
            // Handle curves + radii together, or just one, or neither
            if !activeCurves.isEmpty {
                // Always use the proven edge-based curvedPolygonPath
                // Corner indices are used to set the edge property, but rendering uses edge-based approach
                let curvedPath = curvedPolygonPath(points: displayPoints, shape: .rectangle, curves: activeCurves, baseBounds: nil)
                if !cornerRadii.isEmpty {
                    return applyCornerRadiiToPath(curvedPath, cornerRadii: cornerRadii, piece: piece, displayPoints: displayPoints)
                }
                return curvedPath
            }
            if !cornerRadii.isEmpty {
                let ordered = reorderCornersClockwise(displayPoints)
                let baseCorners = cornerPoints(for: piece, includeAngles: false)
                return roundedPolygonPath(points: ordered, cornerRadii: cornerRadii, baseCorners: baseCorners)
            }
            return polygonPath(displayPoints)
        }
        if piece.shape == .rightTriangle, (!notches.isEmpty || !piece.angleCuts.isEmpty) {
            let result = angledRightTrianglePoints(size: rawSize, notches: notches, angleCuts: pieceAngleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            let displaySize = CGSize(width: rawSize.height, height: rawSize.width)
            let baseBounds = CGRect(origin: .zero, size: displaySize)
            
            // Handle curves + radii together, or just one, or neither
            if !activeCurves.isEmpty {
                // Always use the proven edge-based curvedPolygonPath
                // Corner indices are used to set the edge property, but rendering uses edge-based approach
                let curvedPath = curvedPolygonPath(points: displayPoints, shape: .rightTriangle, curves: activeCurves, baseBounds: baseBounds)
                if !cornerRadii.isEmpty {
                    return applyCornerRadiiToPath(curvedPath, cornerRadii: cornerRadii, piece: piece, displayPoints: displayPoints)
                }
                return curvedPath
            }
            if !cornerRadii.isEmpty {
                let ordered = reorderCornersClockwise(displayPoints)
                let baseCorners = cornerPoints(for: piece, includeAngles: false)
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
                    let baseCorners = cornerPoints(for: piece, includeAngles: false)
                    return roundedPolygonPath(points: ordered, cornerRadii: cornerRadii, baseCorners: baseCorners)
                }
            case .rightTriangle:
                let localNotches = notchCandidates(for: piece, size: rawSize)
                let base = localNotches.isEmpty ? rightTrianglePoints(size: rawSize) : notchRightTrianglePoints(size: rawSize, notches: localNotches)
                let displayPoints = base.map { displayPoint(fromRaw: $0) }
                
                if !activeCurves.isEmpty {
                    // Always use the proven edge-based curvedRightTriangle
                    let size = displaySize(for: piece)
                    let curvedPath = curvedRightTriangle(width: size.width, height: size.height, curves: activeCurves)
                    if !cornerRadii.isEmpty {
                        return applyCornerRadiiToPath(curvedPath, cornerRadii: cornerRadii, piece: piece, displayPoints: displayPoints)
                    }
                    return curvedPath
                }
                if !cornerRadii.isEmpty {
                    let ordered = reorderCornersClockwise(displayPoints)
                    let baseCorners = cornerPoints(for: piece, includeAngles: false)
                    return roundedPolygonPath(points: ordered, cornerRadii: cornerRadii, baseCorners: baseCorners)
                }
            default:
                break
            }
        }
        let size = displaySize(for: piece)
        return path(for: piece.shape, size: size, curves: piece.curvedEdges)
    }
    
    /// Applies corner radii to corners of a path that aren't affected by curves.
    /// This allows curves and corner radii to coexist on different parts of the same piece.
    private static func applyCornerRadiiToPath(_ basePath: Path, cornerRadii: [CornerRadius], piece: Piece, displayPoints: [CGPoint]) -> Path {
        // Get the base corner count for the shape
        let baseCornerCount = pieceCornerCount(for: piece)
        
        // If the polygon has been modified by cutouts/notches (more points than base corners),
        // the unified renderer can't handle it safely - return the curved path as-is
        if displayPoints.count > baseCornerCount {
            return basePath
        }
        
        // Get the base corners for reference
        let baseCorners = cornerPoints(for: piece, includeAngles: false)
        let ordered = reorderCornersClockwise(displayPoints)
        
        // Build a new path that combines curved edges with rounded corners
        return roundedCurvedPolygonPath(
            points: ordered,
            cornerRadii: cornerRadii,
            baseCorners: baseCorners,
            curves: piece.curvedEdges.filter { $0.radius > 0 },
            shape: piece.shape,
            piece: piece
        )
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
            guard cutout.centerX >= 0 && cutout.centerY >= 0 else { return false }
            return cutout.isNotch || cutoutTouchesBoundary(cutout: cutout, size: size, shape: piece.shape)
        }
    }

    static func cutoutTouchesBoundary(cutout: Cutout, size: CGSize, shape: ShapeKind) -> Bool {
        let halfWidth = cutout.width / 2
        let halfHeight = cutout.height / 2
        let minX = cutout.centerX - halfWidth
        let maxX = cutout.centerX + halfWidth
        let minY = cutout.centerY - halfHeight
        let maxY = cutout.centerY + halfHeight
        let eps: CGFloat = 0.01
        switch shape {
        case .rightTriangle:
            let touchesTop = minY <= eps
            let touchesLeft = minX <= eps
            let touchesHypotenuse = cutoutTouchesHypotenuse(minX: minX, maxX: maxX, minY: minY, maxY: maxY, size: size, eps: eps)
            return touchesTop || touchesLeft || touchesHypotenuse
        default:
            return minX <= eps || minY <= eps || maxX >= size.width - eps || maxY >= size.height - eps
        }
    }

    private static func cutoutTouchesHypotenuse(minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat, size: CGSize, eps: CGFloat) -> Bool {
        let width = max(size.width, 0.0001)
        let height = max(size.height, 0.0001)
        let corners = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY)
        ]
        var minValue = CGFloat.greatestFiniteMagnitude
        var maxValue = -CGFloat.greatestFiniteMagnitude
        for corner in corners {
            let value = (corner.x / width) + (corner.y / height) - 1
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
        }
        if abs(minValue) <= eps || abs(maxValue) <= eps {
            return true
        }
        return minValue < -eps && maxValue > eps
    }

    private static func cutoutIsInsideTriangle(cutout: Cutout, size: CGSize) -> Bool {
        let width = max(size.width, 0.0001)
        let height = max(size.height, 0.0001)
        let halfWidth = cutout.width / 2
        let halfHeight = cutout.height / 2
        let minX = cutout.centerX - halfWidth
        let maxX = cutout.centerX + halfWidth
        let minY = cutout.centerY - halfHeight
        let maxY = cutout.centerY + halfHeight
        let corners = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY)
        ]
        for corner in corners {
            if corner.x < -0.01 || corner.y < -0.01 {
                return false
            }
            if (corner.x / width) + (corner.y / height) > 1.0 + 0.01 {
                return false
            }
        }
        return true
    }

    private static func cutoutHypotenuseSpan(minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat, size: CGSize) -> (start: CGFloat, end: CGFloat, depth: CGFloat)? {
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
        return (start: start, end: end, depth: depth)
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
        let cornerCount = pieceCornerCount(for: piece)
        return piece.angleCuts.filter { $0.anchorCornerIndex >= 0 && $0.anchorCornerIndex < cornerCount }
    }

    private static func pieceCornerRadii(for piece: Piece) -> [CornerRadius] {
        let cornerCount = pieceCornerCount(for: piece)
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

    static func cutoutPath(_ cutout: Cutout, angleCuts: [AngleCut], cornerRadii: [CornerRadius]) -> Path {
        switch cutout.kind {
        case .circle:
            return cutoutPath(cutout)
        case .square, .rectangle:
            var points = reorderCornersClockwise(cutoutCornerPoints(for: cutout))
            if !angleCuts.isEmpty {
                points = applyAngleCutsDisplay(to: points, angleCuts: angleCuts)
            }
            let localRadii = cornerRadii.filter { $0.cornerIndex >= 0 }
            if !localRadii.isEmpty {
                let baseCorners = reorderCornersClockwise(cutoutCornerPoints(for: cutout))
                return roundedPolygonPath(points: points, cornerRadii: localRadii, baseCorners: baseCorners)
            }
            return polygonPath(points)
        }
    }

    static func cornerLabelCount(for piece: Piece) -> Int {
        pieceCornerCount(for: piece) + interiorCutouts(for: piece).count * 4
    }

    static func pieceCornerCount(for piece: Piece) -> Int {
        baseCornerPoints(for: piece).count
    }

    static func interiorCutouts(for piece: Piece) -> [Cutout] {
        let rawSize = pieceSize(for: piece)
        return piece.cutouts.filter { cutout in
            guard cutout.centerX >= 0 && cutout.centerY >= 0 else { return false }
            guard cutout.kind != .circle else { return false }
            guard !cutout.isNotch else { return false }
            if piece.shape == .rightTriangle {
                return cutoutIsInsideTriangle(cutout: cutout, size: rawSize) &&
                    !cutoutTouchesBoundary(cutout: cutout, size: rawSize, shape: piece.shape)
            }
            return !cutoutTouchesBoundary(cutout: cutout, size: rawSize, shape: piece.shape)
        }
    }

    static func cutoutCornerRanges(for piece: Piece) -> [(cutout: Cutout, range: Range<Int>)] {
        let baseCount = pieceCornerCount(for: piece)
        var nextIndex = baseCount
        var ranges: [(Cutout, Range<Int>)] = []
        for cutout in interiorCutouts(for: piece) {
            let range = nextIndex..<(nextIndex + 4)
            ranges.append((cutout, range))
            nextIndex += 4
        }
        return ranges
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
        if piece.shape == .rectangle {
            let notches = notchCandidates(for: piece, size: rawSize)
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: boundaryAngleCuts(for: piece))
            return result.segments.map { segment in
                AngleSegment(id: segment.id, start: displayPoint(fromRaw: segment.start), end: displayPoint(fromRaw: segment.end))
            }
        }
        if piece.shape == .rightTriangle {
            let notches = notchCandidates(for: piece, size: rawSize)
            let result = angledRightTrianglePoints(size: rawSize, notches: notches, angleCuts: boundaryAngleCuts(for: piece))
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
            if let limit = angleCutLimit {
                angleCuts = Array(boundaryAngleCuts(for: piece).prefix(max(0, limit)))
            } else {
                angleCuts = includeAngles ? boundaryAngleCuts(for: piece) : []
            }
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        case .rightTriangle:
            let notches = notchCandidates(for: piece, size: rawSize)
            let angleCuts: [AngleCut]
            if let limit = angleCutLimit {
                angleCuts = Array(boundaryAngleCuts(for: piece).prefix(max(0, limit)))
            } else {
                angleCuts = includeAngles ? boundaryAngleCuts(for: piece) : []
            }
            let result = angledRightTrianglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        default:
            return []
        }
    }

    static func displayPolygonPoints(for piece: Piece, includeAngles: Bool = true, angleCutLimit: Int? = nil) -> [CGPoint] {
        let rawSize = pieceSize(for: piece)
        switch piece.shape {
        case .rectangle:
            let notches = notchCandidates(for: piece, size: rawSize)
            let angleCuts: [AngleCut]
            if let limit = angleCutLimit {
                angleCuts = Array(boundaryAngleCuts(for: piece).prefix(max(0, limit)))
            } else {
                angleCuts = includeAngles ? boundaryAngleCuts(for: piece) : []
            }
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            return result.points.map { displayPoint(fromRaw: $0) }
        case .rightTriangle:
            let notches = notchCandidates(for: piece, size: rawSize)
            let angleCuts: [AngleCut]
            if let limit = angleCutLimit {
                angleCuts = Array(boundaryAngleCuts(for: piece).prefix(max(0, limit)))
            } else {
                angleCuts = includeAngles ? boundaryAngleCuts(for: piece) : []
            }
            let result = angledRightTrianglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            return result.points.map { displayPoint(fromRaw: $0) }
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

    private static func angledRectanglePoints(size: CGSize, notches: [Cutout], angleCuts: [AngleCut]) -> (points: [CGPoint], segments: [AngleSegment]) {
        let base = notches.isEmpty ? rectanglePoints(size: size) : notchRectanglePoints(size: size, notches: notches)
        return applyAngleCuts(to: base, shape: .rectangle, size: size, angleCuts: angleCuts)
    }

    private static func angledRightTrianglePoints(size: CGSize, notches: [Cutout], angleCuts: [AngleCut]) -> (points: [CGPoint], segments: [AngleSegment]) {
        let base = notches.isEmpty ? rightTrianglePoints(size: size) : notchRightTrianglePoints(size: size, notches: notches)
        return applyAngleCuts(to: base, shape: .rightTriangle, size: size, angleCuts: angleCuts)
    }

    private static func rectanglePoints(size: CGSize) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
    }

    private static func rightTrianglePoints(size: CGSize) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height)]
    }

    private static func notchRightTrianglePoints(size: CGSize, notches: [Cutout]) -> [CGPoint] {
        let width = size.width
        let height = size.height
        let edgeEpsilon: CGFloat = 0.5
        var topSpans: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        var leftSpans: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        var hypotenuseSpans: [(start: CGFloat, end: CGFloat, depth: CGFloat)] = []
        var cornerNotches: [Cutout] = []

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
            let touchesLeft = minX <= edgeEpsilon
            let touchesHypotenuse = cutoutTouchesHypotenuse(minX: minX, maxX: maxX, minY: minY, maxY: maxY, size: size, eps: edgeEpsilon)
            let touchesCount = [touchesTop, touchesLeft, touchesHypotenuse].filter { $0 }.count

            if touchesCount >= 2 {
                cornerNotches.append(notch)
                continue
            }

            if touchesTop {
                topSpans.append((start: minX, end: maxX, depth: maxY))
            } else if touchesLeft {
                leftSpans.append((start: minY, end: maxY, depth: maxX))
            } else if touchesHypotenuse, let span = cutoutHypotenuseSpan(minX: minX, maxX: maxX, minY: minY, maxY: maxY, size: size) {
                hypotenuseSpans.append(span)
            }
        }

        let mergedTop = mergeEdgeSpans(topSpans)
        let mergedLeft = mergeEdgeSpans(leftSpans)
        let mergedHypotenuse = mergeHypotenuseSpans(hypotenuseSpans)

        var points: [CGPoint] = []
        points.append(CGPoint(x: 0, y: 0))

        for span in mergedTop {
            let clampedStart = max(span.start, 0)
            let clampedEnd = min(span.end, width)
            if clampedEnd <= clampedStart { continue }
            if points.last?.x ?? 0 < clampedStart {
                points.append(CGPoint(x: clampedStart, y: 0))
            }
            points.append(CGPoint(x: clampedStart, y: span.depth))
            points.append(CGPoint(x: clampedEnd, y: span.depth))
            points.append(CGPoint(x: clampedEnd, y: 0))
        }
        points.append(CGPoint(x: width, y: 0))

        let hypStart = CGPoint(x: width, y: 0)
        let hypEnd = CGPoint(x: 0, y: height)
        let inward = hypotenuseInwardNormal(size: size)
        var currentT: CGFloat = 0
        for span in mergedHypotenuse {
            let startT = max(0, min(1, span.start))
            let endT = max(0, min(1, span.end))
            if endT <= startT { continue }
            if currentT < startT {
                points.append(pointOnHypotenuse(start: hypStart, end: hypEnd, t: startT))
            }
            let start = pointOnHypotenuse(start: hypStart, end: hypEnd, t: startT)
            let end = pointOnHypotenuse(start: hypStart, end: hypEnd, t: endT)
            let p1 = CGPoint(x: start.x + inward.x * span.depth, y: start.y + inward.y * span.depth)
            let p2 = CGPoint(x: end.x + inward.x * span.depth, y: end.y + inward.y * span.depth)
            points.append(p1)
            points.append(p2)
            points.append(end)
            currentT = endT
        }
        points.append(CGPoint(x: 0, y: height))

        for span in mergedLeft.reversed() {
            let clampedStart = max(span.start, 0)
            let clampedEnd = min(span.end, height)
            if clampedEnd <= clampedStart { continue }
            if points.last?.y ?? height > clampedEnd {
                points.append(CGPoint(x: 0, y: clampedEnd))
            }
            points.append(CGPoint(x: span.depth, y: clampedEnd))
            points.append(CGPoint(x: span.depth, y: clampedStart))
            points.append(CGPoint(x: 0, y: clampedStart))
        }
        points.append(CGPoint(x: 0, y: 0))

        var rawPoints = dedupePoints(points)
        if !cornerNotches.isEmpty {
            rawPoints = applyCornerNotches(to: rawPoints, notches: cornerNotches)
        }
        return rawPoints
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
                    topSpans.append((start: minX, end: maxX, depth: maxY))
                } else if touchesBottom {
                    bottomSpans.append((start: minX, end: maxX, depth: height - minY))
                } else if touchesLeft {
                    leftSpans.append((start: minY, end: maxY, depth: maxX))
                } else if touchesRight {
                    rightSpans.append((start: minY, end: maxY, depth: width - minX))
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

    private static func applyCornerNotches(to rawPoints: [CGPoint], notches: [Cutout]) -> [CGPoint] {
        guard !notches.isEmpty, rawPoints.count >= 3 else { return rawPoints }
        var displayPoints = rawPoints.map { displayPoint(fromRaw: $0) }
        displayPoints = reorderCornersClockwise(displayPoints)

        let orderedNotches = sortNotchesByCorner(notches, points: displayPoints)
        for notch in orderedNotches {
            displayPoints = applyCornerNotchToDisplay(points: displayPoints, notch: notch)
        }

        return displayPoints.map { rawPoint(fromDisplay: $0) }
    }

    private static func applyCornerNotchToDisplay(points: [CGPoint], notch: Cutout) -> [CGPoint] {
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

        let toPrev = unitVector(from: corner, to: prev)
        let toNext = unitVector(from: corner, to: next)

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
        if notch.centerX >= 0 && notch.centerY >= 0 {
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
        var displayPoints = basePoints.map { displayPoint(fromRaw: $0) }
        let baseOrdered = reorderCornersClockwise(displayPoints)
        var segments: [AngleSegment] = []
        for cut in angleCuts {
            if cut.anchorCornerIndex < 0 {
                continue
            }
            let ordered = reorderCornersClockwise(displayPoints)
            let result = applyAngleCutDisplay(cut, to: ordered, baseOrdered: baseOrdered)
            displayPoints = result.points
            if let segment = result.segment {
                segments.append(AngleSegment(id: segment.id, start: rawPoint(fromDisplay: segment.start), end: rawPoint(fromDisplay: segment.end)))
            }
        }
        let rawPoints = displayPoints.map { rawPoint(fromDisplay: $0) }
        return (rawPoints, segments)
    }

    private static func applyAngleCutDisplay(_ cut: AngleCut, to ordered: [CGPoint], baseOrdered: [CGPoint]) -> (points: [CGPoint], segment: AngleSegment?) {
        guard ordered.count >= 3 else { return (ordered, nil) }
        guard baseOrdered.count >= 3 else { return (ordered, nil) }
        let baseAnchorIndex = normalizedIndex(cut.anchorCornerIndex, count: baseOrdered.count)
        let baseCorner = baseOrdered[baseAnchorIndex]
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

    private static func reorderCornersClockwise(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var ordered = points
        if isClockwise(ordered) {
            ordered.reverse()
        }

        let bounds = polygonBounds(ordered)
        let midY = bounds.minY + (bounds.height / 2)
        let topCandidates = ordered.enumerated().filter { $0.element.y <= midY }
        let startIndex = topCandidates.min(by: { lhs, rhs in
            if lhs.element.x == rhs.element.x {
                return lhs.element.y < rhs.element.y
            }
            return lhs.element.x < rhs.element.x
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
        if result.count > 1, distance(result.first!, result.last!) < 0.0001 {
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

    private static func applyAngleCutsDisplay(to basePoints: [CGPoint], angleCuts: [AngleCut]) -> [CGPoint] {
        guard !angleCuts.isEmpty else { return basePoints }
        var displayPoints = basePoints
        let baseOrdered = reorderCornersClockwise(displayPoints)
        for cut in angleCuts {
            if cut.anchorCornerIndex < 0 {
                continue
            }
            let ordered = reorderCornersClockwise(displayPoints)
            let result = applyAngleCutDisplay(cut, to: ordered, baseOrdered: baseOrdered)
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
        curves: [CurvedEdge],
        shape: ShapeKind,
        piece: Piece
    ) -> Path {
        var path = Path()
        guard points.count >= 3 else { return polygonPath(points) }
        
        let count = points.count
        let curveMap = curveLookup(curves)
        let occupiedCorners = cornerIndicesOccupiedByCurves(curves: curves, shape: shape)
        
        // Build radius map for non-curved corners only
        var radiusMap: [Int: CornerRadius] = [:]
        for corner in cornerRadii where corner.cornerIndex >= 0 && !occupiedCorners.contains(corner.cornerIndex) {
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
        
        // Determine which edges have curves
        func edgeForCornerPair(fromIndex: Int, toIndex: Int) -> EdgePosition? {
            switch shape {
            case .rectangle:
                // Corners: 0=A (top-left), 1=B (top-right), 2=C (bottom-right), 3=D (bottom-left)
                let pair = (fromIndex, toIndex)
                switch pair {
                case (0, 1), (1, 0): return .top
                case (1, 2), (2, 1): return .right
                case (2, 3), (3, 2): return .bottom
                case (3, 0), (0, 3): return .left
                default: return nil
                }
            case .rightTriangle:
                // Corners: 0=A (top-left), 1=B (top-right), 2=C (bottom-left)
                let pair = (fromIndex, toIndex)
                switch pair {
                case (0, 1), (1, 0): return .legA
                case (1, 2), (2, 1): return .hypotenuse
                case (2, 0), (0, 2): return .legB
                default: return nil
                }
            default:
                return nil
            }
        }
        
        let bounds = polygonBounds(points)
        
        for index in 0..<count {
            let prevIndex = (index - 1 + count) % count
            let nextIndex = (index + 1) % count
            let prev = points[prevIndex]
            let curr = points[index]
            let next = points[nextIndex]
            
            // Check if the edge from curr to next has a curve
            let edgeToNext = edgeForCornerPair(fromIndex: index, toIndex: nextIndex)
            let hasCurveOnNextEdge = edgeToNext.flatMap { curveMap[$0] }?.radius ?? 0 > 0
            
            // Handle corner at curr
            if let corner = radiusMap[index], corner.radius > 0 {
                // Apply corner radius
                let v1 = unitVector(from: curr, to: prev)
                let v2 = unitVector(from: curr, to: next)
                let dot = max(min(v1.x * v2.x + v1.y * v2.y, 1), -1)
                let angleSmall = acos(dot)
                
                if angleSmall >= 0.0001 {
                    let lenPrev = distance(curr, prev)
                    let lenNext = distance(curr, next)
                    let tanHalf = tan(angleSmall / 2)
                    let tanHalfAbs = abs(tanHalf)
                    
                    if tanHalfAbs > 0.0001 {
                        let maxRadius = min(lenPrev, lenNext) * tanHalfAbs
                        let radius = min(CGFloat(corner.radius), maxRadius)
                        
                        if radius > 0.0001 {
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
                            
                            if sinHalf > 0.0001 {
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
                            } else {
                                path.addLine(to: p2)
                            }
                            
                            // Now handle the edge to next point
                            if hasCurveOnNextEdge, let edge = edgeToNext, let curve = curveMap[edge] {
                                let p2End = next
                                addCurvedEdgeSegment(path: &path, from: p2, to: p2End, curve: curve, edge: edge, bounds: bounds, shape: shape)
                            }
                            continue
                        }
                    }
                }
            }
            
            // No corner radius at this corner, handle normally
            if index == 0 {
                path.move(to: curr)
            } else {
                path.addLine(to: curr)
            }
            
            // Handle curved edge to next point if applicable
            if hasCurveOnNextEdge, let edge = edgeToNext, let curve = curveMap[edge] {
                addCurvedEdgeSegment(path: &path, from: curr, to: next, curve: curve, edge: edge, bounds: bounds, shape: shape)
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

    private static func curveLookup(_ curves: [CurvedEdge]) -> [EdgePosition: CurvedEdge] {
        var map: [EdgePosition: CurvedEdge] = [:]
        for curve in curves {
            map[curve.edge] = curve
        }
        return map
    }

    private static func addEdge(path: inout Path, from: CGPoint, to: CGPoint, edge: EdgePosition, curveMap: [EdgePosition: CurvedEdge], normal: CGPoint, controlOverride: CGPoint?) {
        guard let curve = curveMap[edge], curve.radius > 0 else {
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
        var hypotenuseSegmentIndex: Int?

        if shape == .rightTriangle, (curvesByEdge[.hypotenuse]?.contains { $0.radius > 0 } ?? false) {
            let a = CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY)
            let b = CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY)
            var bestDistance = CGFloat.greatestFiniteMagnitude
            var bestLength: CGFloat = 0
            for index in 0..<points.count {
                let start = points[index]
                let end = points[(index + 1) % points.count]
                let dx = end.x - start.x
                let dy = end.y - start.y
                if abs(dx) < eps || abs(dy) < eps { continue }
                let distanceToLine = (pointLineDistance(point: start, a: a, b: b) + pointLineDistance(point: end, a: a, b: b)) / 2
                let length = distance(start, end)
                if distanceToLine < bestDistance || (abs(distanceToLine - bestDistance) < 0.001 && length > bestLength) {
                    bestDistance = distanceToLine
                    bestLength = length
                    hypotenuseSegmentIndex = index
                }
            }
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
        
        // Span-based control overrides for span curves
        var spanControlOverrides: [UUID: [Int: CGPoint]] = [:]
        let pointCount = points.count
        for curve in curves where curve.hasSpan && curve.radius > 0 {
            guard pointCount > 1 else { continue }
            let startIndex = normalizedIndex(curve.startCornerIndex, count: pointCount)
            let endIndex = normalizedIndex(curve.endCornerIndex, count: pointCount)
            if startIndex == endIndex { continue }
            if startIndex < 0 || endIndex < 0 || startIndex >= pointCount || endIndex >= pointCount { continue }
            let spanStart = points[startIndex]
            let spanEnd = points[endIndex]
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
                startIndex: startIndex,
                endIndex: endIndex,
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
                    continue
                }
                drawPoints[pointIndex] = quadPoint(start: spanStart, control: control, end: spanEnd, t: t)
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
            var edge = edgeForSegment(start: originalStart, end: originalEnd, bounds: bounds, shape: shape, hypotenuseBounds: hypotenuseBounds)
            if edge == nil, shape == .rightTriangle, (curvesByEdge[.hypotenuse]?.contains { $0.radius > 0 } ?? false), hypotenuseSegmentIndex == index {
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
                } else if let edgeCurve = curvesForEdge.first(where: { !$0.hasSpan }) {
                    curveForSegment = edgeCurve
                    if let fullGeometry = fullEdgeGeometry(edge: resolvedEdge, bounds: bounds, hypotenuseBounds: hypotenuseBounds, shape: shape),
                       let baseControl = edgeControlOverrides[resolvedEdge] {
                        let t0 = tForEdge(point: originalStart, geometry: fullGeometry, edge: resolvedEdge)
                        let t1 = tForEdge(point: originalEnd, geometry: fullGeometry, edge: resolvedEdge)
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
            let total = distance(geometry.start, geometry.end)
            if total < 0.0001 { return 0 }
            return distance(geometry.start, point) / total
        }
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
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
            if abs(dy) < eps {
                return .legA
            }
            if abs(dx) < eps {
                return .legB
            }
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
        let tolerance: CGFloat = 1.0
        return pointLineDistance(point: start, a: a, b: b) <= tolerance &&
            pointLineDistance(point: end, a: a, b: b) <= tolerance
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
            let eps: CGFloat = 0.01
            let onLegA = abs(start.y - hypotenuseBounds.minY) < edgeTolerance && abs(end.y - hypotenuseBounds.minY) < edgeTolerance
            if onLegA { return .legA }
            let onLegB = abs(start.x - hypotenuseBounds.minX) < edgeTolerance && abs(end.x - hypotenuseBounds.minX) < edgeTolerance
            if onLegB { return .legB }
            let a = CGPoint(x: hypotenuseBounds.maxX, y: hypotenuseBounds.minY)
            let b = CGPoint(x: hypotenuseBounds.minX, y: hypotenuseBounds.maxY)
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
            }
        }
        return false
    }
}
