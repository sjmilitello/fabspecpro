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
        if result.count > 1, distance(result.first!, result.last!) < tolerance {
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
}
