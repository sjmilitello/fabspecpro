import SwiftUI

struct AngleSegment {
    let id: UUID
    let start: CGPoint
    let end: CGPoint
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

    static func path(for piece: Piece) -> Path {
        let rawSize = pieceSize(for: piece)
        let notches = piece.cutouts.filter { $0.isNotch && $0.kind != .circle && $0.centerX >= 0 && $0.centerY >= 0 }
        if piece.shape == .rectangle, (!notches.isEmpty || !piece.angleCuts.isEmpty) {
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: piece.angleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            if piece.curvedEdges.isEmpty {
                return polygonPath(displayPoints)
            }
            return curvedPolygonPath(points: displayPoints, shape: .rectangle, curves: piece.curvedEdges, baseBounds: nil)
        }
        if piece.shape == .rightTriangle, !piece.angleCuts.isEmpty {
            let result = angledRightTrianglePoints(size: rawSize, angleCuts: piece.angleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            if piece.curvedEdges.isEmpty {
                return polygonPath(displayPoints)
            }
            let displaySize = CGSize(width: rawSize.height, height: rawSize.width)
            let baseBounds = CGRect(origin: .zero, size: displaySize)
            return curvedPolygonPath(points: displayPoints, shape: .rightTriangle, curves: piece.curvedEdges, baseBounds: baseBounds)
        }
        let size = displaySize(for: piece)
        return path(for: piece.shape, size: size, curves: piece.curvedEdges)
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

    static func angleSegments(for piece: Piece) -> [AngleSegment] {
        let rawSize = pieceSize(for: piece)
        if piece.shape == .rectangle {
            let notches = piece.cutouts.filter { $0.isNotch && $0.kind != .circle && $0.centerX >= 0 && $0.centerY >= 0 }
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: piece.angleCuts)
            return result.segments.map { segment in
                AngleSegment(id: segment.id, start: displayPoint(fromRaw: segment.start), end: displayPoint(fromRaw: segment.end))
            }
        }
        if piece.shape == .rightTriangle {
            let result = angledRightTrianglePoints(size: rawSize, angleCuts: piece.angleCuts)
            return result.segments.map { segment in
                AngleSegment(id: segment.id, start: displayPoint(fromRaw: segment.start), end: displayPoint(fromRaw: segment.end))
            }
        }
        return []
    }

    static func cornerPoints(for piece: Piece, includeAngles: Bool = true, angleCutLimit: Int? = nil) -> [CGPoint] {
        let rawSize = pieceSize(for: piece)
        switch piece.shape {
        case .rectangle:
            let notches = piece.cutouts.filter { $0.isNotch && $0.kind != .circle && $0.centerX >= 0 && $0.centerY >= 0 }
            let angleCuts: [AngleCut]
            if let limit = angleCutLimit {
                angleCuts = Array(piece.angleCuts.prefix(max(0, limit)))
            } else {
                angleCuts = includeAngles ? piece.angleCuts : []
            }
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            let displayPoints = result.points.map { displayPoint(fromRaw: $0) }
            return reorderCornersClockwise(displayPoints)
        case .rightTriangle:
            let angleCuts: [AngleCut]
            if let limit = angleCutLimit {
                angleCuts = Array(piece.angleCuts.prefix(max(0, limit)))
            } else {
                angleCuts = includeAngles ? piece.angleCuts : []
            }
            let result = angledRightTrianglePoints(size: rawSize, angleCuts: angleCuts)
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
            let notches = piece.cutouts.filter { $0.isNotch && $0.kind != .circle && $0.centerX >= 0 && $0.centerY >= 0 }
            let angleCuts: [AngleCut]
            if let limit = angleCutLimit {
                angleCuts = Array(piece.angleCuts.prefix(max(0, limit)))
            } else {
                angleCuts = includeAngles ? piece.angleCuts : []
            }
            let result = angledRectanglePoints(size: rawSize, notches: notches, angleCuts: angleCuts)
            return result.points.map { displayPoint(fromRaw: $0) }
        case .rightTriangle:
            let angleCuts: [AngleCut]
            if let limit = angleCutLimit {
                angleCuts = Array(piece.angleCuts.prefix(max(0, limit)))
            } else {
                angleCuts = includeAngles ? piece.angleCuts : []
            }
            let result = angledRightTrianglePoints(size: rawSize, angleCuts: angleCuts)
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

    private static func angledRightTrianglePath(size: CGSize, angleCuts: [AngleCut]) -> Path {
        let result = angledRightTrianglePoints(size: size, angleCuts: angleCuts)
        return polygonPath(result.points)
    }

    private static func angledRectanglePoints(size: CGSize, notches: [Cutout], angleCuts: [AngleCut]) -> (points: [CGPoint], segments: [AngleSegment]) {
        let base = notches.isEmpty ? rectanglePoints(size: size) : notchRectanglePoints(size: size, notches: notches)
        return applyAngleCuts(to: base, shape: .rectangle, size: size, angleCuts: angleCuts)
    }

    private static func angledRightTrianglePoints(size: CGSize, angleCuts: [AngleCut]) -> (points: [CGPoint], segments: [AngleSegment]) {
        let base = rightTrianglePoints(size: size)
        return applyAngleCuts(to: base, shape: .rightTriangle, size: size, angleCuts: angleCuts)
    }

    private static func rectanglePoints(size: CGSize) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
    }

    private static func rightTrianglePoints(size: CGSize) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height)]
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
        }

        let hasTopLeft = topLeftMaxX > 0 && topLeftMaxY > 0
        let hasTopRight = topRightMinX < width && topRightMaxY > 0
        let hasBottomRight = bottomRightMinX < width && bottomRightMinY < height
        let hasBottomLeft = bottomLeftMaxX > 0 && bottomLeftMinY < height

        var points: [CGPoint] = []
        let startX = hasTopLeft ? topLeftMaxX : 0
        points.append(CGPoint(x: startX, y: 0))

        let topRightX = hasTopRight ? topRightMinX : width
        points.append(CGPoint(x: topRightX, y: 0))
        if hasTopRight {
            points.append(CGPoint(x: topRightX, y: topRightMaxY))
            points.append(CGPoint(x: width, y: topRightMaxY))
        } else {
            points.append(CGPoint(x: width, y: 0))
        }

        let rightDownY = hasBottomRight ? bottomRightMinY : height
        points.append(CGPoint(x: width, y: rightDownY))
        if hasBottomRight {
            points.append(CGPoint(x: bottomRightMinX, y: bottomRightMinY))
            points.append(CGPoint(x: bottomRightMinX, y: height))
        } else {
            points.append(CGPoint(x: width, y: height))
        }

        let bottomLeftX = hasBottomLeft ? bottomLeftMaxX : 0
        points.append(CGPoint(x: bottomLeftX, y: height))
        if hasBottomLeft {
            points.append(CGPoint(x: bottomLeftMaxX, y: bottomLeftMinY))
            points.append(CGPoint(x: 0, y: bottomLeftMinY))
        } else {
            points.append(CGPoint(x: 0, y: height))
        }

        let leftUpY = hasTopLeft ? topLeftMaxY : 0
        points.append(CGPoint(x: 0, y: leftUpY))
        if hasTopLeft {
            points.append(CGPoint(x: topLeftMaxX, y: topLeftMaxY))
            points.append(CGPoint(x: topLeftMaxX, y: 0))
        } else {
            points.append(CGPoint(x: 0, y: 0))
        }

        return dedupePoints(points)
    }

    private static func applyAngleCuts(to basePoints: [CGPoint], shape: ShapeKind, size: CGSize, angleCuts: [AngleCut]) -> (points: [CGPoint], segments: [AngleSegment]) {
        guard !angleCuts.isEmpty else { return (basePoints, []) }
        var displayPoints = basePoints.map { displayPoint(fromRaw: $0) }
        let baseOrdered = reorderCornersClockwise(displayPoints)
        var segments: [AngleSegment] = []
        for cut in angleCuts {
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

    private static func reorderCornersClockwise(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var ordered = points
        if !isClockwise(ordered) {
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
        return area > 0
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

    private static func curvedRectanglePath(width: CGFloat, height: CGFloat, curves: [CurvedEdge]) -> Path {
        let curveMap = curveLookup(curves)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))

        addEdge(path: &path, from: CGPoint(x: 0, y: 0), to: CGPoint(x: width, y: 0), edge: .top, curveMap: curveMap, normal: CGPoint(x: 0, y: -1))
        addEdge(path: &path, from: CGPoint(x: width, y: 0), to: CGPoint(x: width, y: height), edge: .right, curveMap: curveMap, normal: CGPoint(x: 1, y: 0))
        addEdge(path: &path, from: CGPoint(x: width, y: height), to: CGPoint(x: 0, y: height), edge: .bottom, curveMap: curveMap, normal: CGPoint(x: 0, y: 1))
        addEdge(path: &path, from: CGPoint(x: 0, y: height), to: CGPoint(x: 0, y: 0), edge: .left, curveMap: curveMap, normal: CGPoint(x: -1, y: 0))

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
        addEdge(path: &path, from: p0, to: p1, edge: .legA, curveMap: curveMap, normal: CGPoint(x: 0, y: -1))
        addEdge(path: &path, from: p1, to: p2, edge: .hypotenuse, curveMap: curveMap, normal: CGPoint(x: 0.7, y: 0.7))
        addEdge(path: &path, from: p2, to: p0, edge: .legB, curveMap: curveMap, normal: CGPoint(x: -1, y: 0))
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

    private static func addEdge(path: inout Path, from: CGPoint, to: CGPoint, edge: EdgePosition, curveMap: [EdgePosition: CurvedEdge], normal: CGPoint) {
        guard let curve = curveMap[edge], curve.radius > 0 else {
            path.addLine(to: to)
            return
        }
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let direction = curve.isConcave ? -1.0 : 1.0
        let control = CGPoint(
            x: mid.x + normal.x * curve.radius * direction,
            y: mid.y + normal.y * curve.radius * direction
        )
        path.addQuadCurve(to: to, control: control)
    }

    private static func curvedPolygonPath(points: [CGPoint], shape: ShapeKind, curves: [CurvedEdge], baseBounds: CGRect?) -> Path {
        guard points.count >= 2 else { return Path() }
        let curveMap = curveLookup(curves)
        let bounds = polygonBounds(points)
        let hypotenuseBounds = baseBounds ?? bounds
        let eps: CGFloat = 0.01
        var hypotenuseSegmentIndex: Int?

        if shape == .rightTriangle, curveMap[.hypotenuse] != nil {
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
        var path = Path()
        path.move(to: points[0])
        let count = points.count
        for index in 0..<count {
            let start = points[index]
            let end = points[(index + 1) % count]
            var edge = edgeForSegment(start: start, end: end, bounds: bounds, shape: shape, hypotenuseBounds: hypotenuseBounds)
            if edge == nil, shape == .rightTriangle, curveMap[.hypotenuse] != nil, hypotenuseSegmentIndex == index {
                edge = .hypotenuse
            }
            guard let resolvedEdge = edge else {
                path.addLine(to: end)
                continue
            }
            let normal = edgeNormal(for: resolvedEdge, start: start, end: end)
            addEdge(path: &path, from: start, to: end, edge: resolvedEdge, curveMap: curveMap, normal: normal)
        }
        path.closeSubpath()
        return path
    }

    private static func edgeForSegment(start: CGPoint, end: CGPoint, bounds: CGRect, shape: ShapeKind, hypotenuseBounds: CGRect) -> EdgePosition? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let eps: CGFloat = 0.01
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
                if abs(y - bounds.minY) < eps {
                    return .top
                }
                if abs(y - bounds.maxY) < eps {
                    return .bottom
                }
            }
            if abs(dx) < eps {
                let x = (start.x + end.x) / 2
                if abs(x - bounds.minX) < eps {
                    return .left
                }
                if abs(x - bounds.maxX) < eps {
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
}
