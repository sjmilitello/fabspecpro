import SwiftUI

/// Centralized geometry utility functions used across ShapePathBuilder, DrawingCanvasView, PieceEditorView, and PDFRenderer.
/// This eliminates code duplication and ensures consistent behavior for geometric calculations.
enum GeometryHelpers {
    
    // MARK: - Basic Vector Operations
    
    /// Calculate the Euclidean distance between two points.
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }
    
    /// Calculate the unit vector from one point to another.
    static func unitVector(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        return CGPoint(x: dx / length, y: dy / length)
    }
    
    /// Normalize a vector to unit length.
    static func normalized(_ point: CGPoint) -> CGPoint {
        let length = max(sqrt(point.x * point.x + point.y * point.y), 0.0001)
        return CGPoint(x: point.x / length, y: point.y / length)
    }
    
    /// Rotate a vector by the given angle in radians.
    static func rotate(_ point: CGPoint, by radians: CGFloat) -> CGPoint {
        let cosv = cos(radians)
        let sinv = sin(radians)
        return CGPoint(x: point.x * cosv - point.y * sinv, y: point.x * sinv + point.y * cosv)
    }
    
    /// Linear interpolation between two points.
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    // MARK: - Cutout Helpers

    static func cutoutRotationAngle(cutout: Cutout, size: CGSize, shape: ShapeKind) -> CGFloat {
        guard shape == .rightTriangle else { return 0 }
        switch cutout.orientation {
        case .hypotenuse:
            let width = max(size.width, 0.0001)
            let height = max(size.height, 0.0001)
            return -atan2(height, width)
        case .custom:
            // Simple direct mapping: user angle → rotation angle
            // The negative sign makes positive angles rotate clockwise (toward hypotenuse)
            return -cutout.customAngleDegrees * .pi / 180
        case .legs:
            return 0
        }
    }

    static func cutoutCornerPoints(cutout: Cutout, size: CGSize, shape: ShapeKind) -> [CGPoint] {
        let center = CGPoint(x: cutout.centerX, y: cutout.centerY)
        let angle = cutoutRotationAngle(cutout: cutout, size: size, shape: shape)
        // For hypotenuse-aligned cutouts, swap width/height so that:
        // - width is perpendicular to the hypotenuse
        // - height (length) is parallel to the hypotenuse
        // For custom angles, do NOT swap - just rotate from the "square to legs" baseline.
        // This ensures smooth rotation as the angle changes from 0° to 90°.
        let shouldSwapDimensions = shape == .rightTriangle && cutout.orientation == .hypotenuse
        let halfWidth = (shouldSwapDimensions ? cutout.height : cutout.width) / 2
        let halfHeight = (shouldSwapDimensions ? cutout.width : cutout.height) / 2
        let base = [
            CGPoint(x: center.x - halfWidth, y: center.y - halfHeight),
            CGPoint(x: center.x + halfWidth, y: center.y - halfHeight),
            CGPoint(x: center.x + halfWidth, y: center.y + halfHeight),
            CGPoint(x: center.x - halfWidth, y: center.y + halfHeight)
        ]

        if abs(angle) < 0.0001 {
            return base
        }

        return base.map { point in
            let translated = CGPoint(x: point.x - center.x, y: point.y - center.y)
            let rotated = rotate(translated, by: angle)
            return CGPoint(x: center.x + rotated.x, y: center.y + rotated.y)
        }
    }
    
    // MARK: - Index Operations
    
    /// Normalize an index to be within bounds, handling negative indices.
    static func normalizedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let mod = index % count
        return mod < 0 ? mod + count : mod
    }
    
    // MARK: - Polygon Operations
    
    /// Remove duplicate consecutive points from a polygon.
    static func dedupePoints(_ points: [CGPoint], tolerance: CGFloat = 0.0001) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, distance(point, last) < tolerance {
                continue
            }
            result.append(point)
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           distance(first, last) < tolerance {
            result.removeLast()
        }
        return result
    }
    
    /// Determine if a polygon's vertices are ordered clockwise.
    /// Uses the shoelace formula - positive area means clockwise in screen coordinates.
    static func polygonIsClockwise(_ points: [CGPoint]) -> Bool {
        guard points.count >= 3 else { return true }
        var area: CGFloat = 0
        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]
            area += (p1.x * p2.y) - (p2.x * p1.y)
        }
        return area > 0
    }
    
    /// Calculate the bounding rectangle for a set of points.
    static func bounds(for points: [CGPoint]) -> CGRect {
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
    
    /// Find the index of the nearest point in an array to a given point.
    static func nearestPointIndex(to point: CGPoint, in points: [CGPoint]) -> Int {
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
    
    /// Calculate the centroid of a polygon.
    static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
    
    // MARK: - Line and Segment Operations
    
    /// Calculate the perpendicular distance from a point to an infinite line defined by two points.
    static func pointLineDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let denom = max(sqrt(dx * dx + dy * dy), 0.0001)
        return abs(dy * point.x - dx * point.y + b.x * a.y - b.y * a.x) / denom
    }
    
    /// Calculate the distance from a point to a line segment.
    static func pointSegmentDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
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
    
    /// Calculate the outward normal for a line segment based on polygon winding.
    static func outwardNormal(from start: CGPoint, to end: CGPoint, clockwise: Bool) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let ux = dx / length
        let uy = dy / length
        let left = CGPoint(x: -uy, y: ux)
        let right = CGPoint(x: uy, y: -ux)
        return clockwise ? left : right
    }
    
    /// Find the intersection point of a ray with a line segment, if any.
    static func raySegmentIntersection(origin: CGPoint, direction: CGPoint, segment: (CGPoint, CGPoint)) -> CGPoint? {
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
    
    // MARK: - Quadratic Bezier Operations
    
    /// Calculate a point on a quadratic Bezier curve at parameter t.
    static func quadBezierPoint(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let clamped = min(max(t, 0), 1)
        let inv = 1 - clamped
        let x = inv * inv * start.x + 2 * inv * clamped * control.x + clamped * clamped * end.x
        let y = inv * inv * start.y + 2 * inv * clamped * control.y + clamped * clamped * end.y
        return CGPoint(x: x, y: y)
    }
    
    /// Split a quadratic Bezier curve at parameter t into two curves.
    static func quadSplit(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat)
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
    
    /// Extract a subsegment of a quadratic Bezier curve between parameters t0 and t1.
    static func quadSubsegment(start: CGPoint, control: CGPoint, end: CGPoint, t0: CGFloat, t1: CGFloat)
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
    
    // MARK: - Polygon Point-in-Polygon Test
    
    /// Determine if a point is inside a polygon using ray casting.
    static func pointIsInsidePolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside = !inside
            }
            j = i
        }
        return inside
    }

    /// Determine if a point lies on a polygon edge within a tolerance.
    static func pointIsOnPolygonEdge(_ point: CGPoint, polygon: [CGPoint], tolerance: CGFloat = 0.001) -> Bool {
        guard polygon.count >= 2 else { return false }
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            if pointSegmentDistance(point: point, a: a, b: b) <= tolerance {
                return true
            }
        }
        return false
    }

    // MARK: - Polygon Clipping (Axis-Aligned Rectangle Subtraction)

    private enum RectEdge: Int, CaseIterable {
        case top = 0
        case right = 1
        case bottom = 2
        case left = 3
    }

    static func subtractAxisAlignedRect(from polygon: [CGPoint], rect: CGRect) -> [CGPoint] {
        guard polygon.count >= 3 else { return polygon }
        guard rect.width > 0.0001, rect.height > 0.0001 else { return polygon }

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let eps: CGFloat = 0.0001

        func isInsideRect(_ point: CGPoint) -> Bool {
            point.x >= minX - eps && point.x <= maxX + eps && point.y >= minY - eps && point.y <= maxY + eps
        }

        func rectEdge(for point: CGPoint) -> RectEdge? {
            if abs(point.y - minY) < 0.001 { return .top }
            if abs(point.x - maxX) < 0.001 { return .right }
            if abs(point.y - maxY) < 0.001 { return .bottom }
            if abs(point.x - minX) < 0.001 { return .left }
            return nil
        }

        var output: [CGPoint] = []
        var entryPoint: CGPoint?
        var entryEdge: RectEdge?

        for i in 0..<polygon.count {
            let start = polygon[i]
            let end = polygon[(i + 1) % polygon.count]
            let intersections = segmentRectIntersections(a: start, b: end, rect: rect)
                .sorted { $0.t < $1.t }

            var points: [(point: CGPoint, edge: RectEdge?)] = [(start, rectEdge(for: start))]
            for inter in intersections {
                points.append((inter.point, inter.edge))
            }
            points.append((end, rectEdge(for: end)))

            var deduped: [(point: CGPoint, edge: RectEdge?)] = []
            for item in points {
                if let last = deduped.last, distance(item.point, last.point) < eps { continue }
                deduped.append(item)
            }
            if deduped.count < 2 { continue }

            for index in 0..<(deduped.count - 1) {
                let p0 = deduped[index].point
                let p1 = deduped[index + 1].point
                let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                let inside = isInsideRect(mid)

                if !inside {
                    if output.isEmpty || distance(output.last ?? p0, p0) > eps {
                        output.append(p0)
                    }
                    output.append(p1)
                } else {
                    if entryPoint == nil {
                        entryPoint = p0
                        entryEdge = deduped[index].edge ?? rectEdge(for: p0)
                    }
                    if let entry = entryPoint, let entryEdgeValue = entryEdge,
                       let exitEdge = deduped[index + 1].edge ?? rectEdge(for: p1) {
                        let path = rectBoundaryPath(
                            from: entry,
                            entryEdge: entryEdgeValue,
                            to: p1,
                            exitEdge: exitEdge,
                            rect: rect,
                            polygon: polygon
                        )
                        output.append(contentsOf: path)
                        output.append(p1)
                        entryPoint = nil
                        entryEdge = nil
                    }
                }
            }
        }

        return dedupePoints(output)
    }

    private static func rectEdges(_ rect: CGRect) -> [(edge: RectEdge, start: CGPoint, end: CGPoint)] {
        let tl = CGPoint(x: rect.minX, y: rect.minY)
        let tr = CGPoint(x: rect.maxX, y: rect.minY)
        let br = CGPoint(x: rect.maxX, y: rect.maxY)
        let bl = CGPoint(x: rect.minX, y: rect.maxY)
        return [
            (edge: .top, start: tl, end: tr),
            (edge: .right, start: tr, end: br),
            (edge: .bottom, start: br, end: bl),
            (edge: .left, start: bl, end: tl)
        ]
    }

    private static func segmentRectIntersections(
        a: CGPoint,
        b: CGPoint,
        rect: CGRect
    ) -> [(t: CGFloat, point: CGPoint, edge: RectEdge)] {
        let edges = rectEdges(rect)
        var intersections: [(t: CGFloat, point: CGPoint, edge: RectEdge)] = []
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let denom = ab.x * ab.x + ab.y * ab.y
        guard denom > 0.000001 else { return intersections }
        for edge in edges {
            if let overlapPoints = colinearOverlapPoints(a: a, b: b, edgeStart: edge.start, edgeEnd: edge.end) {
                for point in overlapPoints {
                    let t = ((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / denom
                    intersections.append((t: t, point: point, edge: edge.edge))
                }
                continue
            }
            if let point = segmentSegmentIntersection(a1: a, a2: b, b1: edge.start, b2: edge.end) {
                let t = ((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / denom
                intersections.append((t: t, point: point, edge: edge.edge))
            }
        }
        return intersections
    }
    private static func colinearOverlapPoints(
        a: CGPoint,
        b: CGPoint,
        edgeStart: CGPoint,
        edgeEnd: CGPoint
    ) -> [CGPoint]? {
        let eps: CGFloat = 0.0001
        let isHorizontal = abs(a.y - b.y) < eps && abs(edgeStart.y - edgeEnd.y) < eps
        let isVertical = abs(a.x - b.x) < eps && abs(edgeStart.x - edgeEnd.x) < eps
        if isHorizontal, abs(a.y - edgeStart.y) < eps {
            let minX = max(min(a.x, b.x), min(edgeStart.x, edgeEnd.x))
            let maxX = min(max(a.x, b.x), max(edgeStart.x, edgeEnd.x))
            if maxX >= minX {
                return [CGPoint(x: minX, y: a.y), CGPoint(x: maxX, y: a.y)]
            }
        }
        if isVertical, abs(a.x - edgeStart.x) < eps {
            let minY = max(min(a.y, b.y), min(edgeStart.y, edgeEnd.y))
            let maxY = min(max(a.y, b.y), max(edgeStart.y, edgeEnd.y))
            if maxY >= minY {
                return [CGPoint(x: a.x, y: minY), CGPoint(x: a.x, y: maxY)]
            }
        }
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
            CGPoint(x: rect.minX, y: rect.minY), // TL
            CGPoint(x: rect.maxX, y: rect.minY), // TR
            CGPoint(x: rect.maxX, y: rect.maxY), // BR
            CGPoint(x: rect.minX, y: rect.maxY)  // BL
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
            for point in path {
                let mid = CGPoint(x: (last.x + point.x) / 2, y: (last.y + point.y) / 2)
                if pointIsInsidePolygon(mid, polygon: polygon) || pointIsOnPolygonEdge(mid, polygon: polygon) { count += 1 }
                last = point
            }
            let mid = CGPoint(x: (last.x + exit.x) / 2, y: (last.y + exit.y) / 2)
            if pointIsInsidePolygon(mid, polygon: polygon) || pointIsOnPolygonEdge(mid, polygon: polygon) { count += 1 }
            return count
        }

        let useCw = score(cwPath) >= score(ccwPath)
        return useCw ? cwPath : ccwPath
    }
    
    // MARK: - Segment Length Calculations (for notch measurements)
    
    /// Calculate the total length of polygon segments on a vertical or horizontal line within a range.
    static func segmentLengthOnLine(points: [CGPoint], isVertical: Bool, value: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat) -> CGFloat {
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
    
    /// Calculate the weighted center of polygon segments on a vertical or horizontal line within a range.
    static func segmentCenterOnLine(points: [CGPoint], isVertical: Bool, value: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat) -> CGFloat {
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
    
    // MARK: - Line-Line Intersection
    
    /// Find the intersection point of two infinite lines, each defined by a point and direction.
    /// Returns nil if lines are parallel.
    static func lineLineIntersection(
        point1: CGPoint, direction1: CGPoint,
        point2: CGPoint, direction2: CGPoint
    ) -> CGPoint? {
        let cross = direction1.x * direction2.y - direction1.y * direction2.x
        if abs(cross) < 0.0001 { return nil }
        
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        let t = (dx * direction2.y - dy * direction2.x) / cross
        
        return CGPoint(x: point1.x + t * direction1.x, y: point1.y + t * direction1.y)
    }
    
    /// Find the intersection point of two line segments.
    /// Returns nil if segments don't intersect.
    static func segmentSegmentIntersection(
        a1: CGPoint, a2: CGPoint,
        b1: CGPoint, b2: CGPoint
    ) -> CGPoint? {
        let d1 = CGPoint(x: a2.x - a1.x, y: a2.y - a1.y)
        let d2 = CGPoint(x: b2.x - b1.x, y: b2.y - b1.y)
        let cross = d1.x * d2.y - d1.y * d2.x
        if abs(cross) < 0.0001 { return nil }
        
        let dx = b1.x - a1.x
        let dy = b1.y - a1.y
        let t = (dx * d2.y - dy * d2.x) / cross
        let u = (dx * d1.y - dy * d1.x) / cross
        
        if t >= 0 && t <= 1 && u >= 0 && u <= 1 {
            return CGPoint(x: a1.x + t * d1.x, y: a1.y + t * d1.y)
        }
        return nil
    }
    
    // MARK: - Arc Geometry for Corner-Based Curves
    
    /// Calculate the arc parameters for a curve spanning two corner points.
    /// The curve bulges outward (or inward if concave) perpendicular to the chord.
    /// Returns the control point for a quadratic Bezier approximation and the tangent points
    /// where lines should meet the arc.
    static func arcGeometryForCornerCurve(
        startPoint: CGPoint,
        endPoint: CGPoint,
        radius: CGFloat,
        isConcave: Bool
    ) -> (controlPoint: CGPoint, tangentStart: CGPoint, tangentEnd: CGPoint)? {
        let chordLength = distance(startPoint, endPoint)
        guard chordLength > 0.001 else { return nil }
        
        // Midpoint of the chord
        let midpoint = CGPoint(
            x: (startPoint.x + endPoint.x) / 2,
            y: (startPoint.y + endPoint.y) / 2
        )
        
        // Direction along the chord
        let chordDir = unitVector(from: startPoint, to: endPoint)
        
        // Perpendicular direction (outward normal)
        // For convex, bulge outward; for concave, bulge inward
        let perpDir: CGPoint
        if isConcave {
            perpDir = CGPoint(x: chordDir.y, y: -chordDir.x)
        } else {
            perpDir = CGPoint(x: -chordDir.y, y: chordDir.x)
        }
        
        // For a quadratic Bezier curve, the control point offset from midpoint
        // is approximately 2 * radius for a good arc approximation
        let controlOffset = radius * 2
        let controlPoint = CGPoint(
            x: midpoint.x + perpDir.x * controlOffset,
            y: midpoint.y + perpDir.y * controlOffset
        )
        
        // For tangent points, we use the start and end points directly
        // since the incoming/outgoing lines will connect to these points
        // The Bezier curve naturally provides smooth tangent transitions
        return (controlPoint: controlPoint, tangentStart: startPoint, tangentEnd: endPoint)
    }
}
