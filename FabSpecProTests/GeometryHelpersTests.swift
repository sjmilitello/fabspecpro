//
//  GeometryHelpersTests.swift
//  FabSpecProTests
//
//  Tests for GeometryHelpers utility functions.
//

import Foundation
import Testing
@testable import FabSpecPro

// MARK: - Distance and Vector Tests

struct GeometryHelpersDistanceTests {
    
    @Test func distanceBetweenSamePoint() {
        let point = CGPoint(x: 5, y: 5)
        let result = GeometryHelpers.distance(point, point)
        #expect(result == 0)
    }
    
    @Test func distanceHorizontal() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 10, y: 0)
        let result = GeometryHelpers.distance(a, b)
        #expect(result == 10)
    }
    
    @Test func distanceVertical() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 0, y: 10)
        let result = GeometryHelpers.distance(a, b)
        #expect(result == 10)
    }
    
    @Test func distanceDiagonal() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 3, y: 4)
        let result = GeometryHelpers.distance(a, b)
        #expect(result == 5) // 3-4-5 triangle
    }
    
    @Test func unitVectorHorizontal() {
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 10, y: 0)
        let result = GeometryHelpers.unitVector(from: from, to: to)
        #expect(abs(result.x - 1) < 0.0001)
        #expect(abs(result.y) < 0.0001)
    }
    
    @Test func unitVectorDiagonal() {
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 1, y: 1)
        let result = GeometryHelpers.unitVector(from: from, to: to)
        let expected = 1.0 / sqrt(2.0)
        #expect(abs(result.x - expected) < 0.0001)
        #expect(abs(result.y - expected) < 0.0001)
    }
    
    @Test func unitVectorSamePoint() {
        let point = CGPoint(x: 5, y: 5)
        let result = GeometryHelpers.unitVector(from: point, to: point)
        #expect(result.x == 0)
        #expect(result.y == 0)
    }
}

// MARK: - Rotation Tests

struct GeometryHelpersRotationTests {
    
    @Test func rotate90Degrees() {
        let point = CGPoint(x: 1, y: 0)
        let result = GeometryHelpers.rotate(point, by: .pi / 2)
        #expect(abs(result.x) < 0.0001)
        #expect(abs(result.y - 1) < 0.0001)
    }
    
    @Test func rotate180Degrees() {
        let point = CGPoint(x: 1, y: 0)
        let result = GeometryHelpers.rotate(point, by: .pi)
        #expect(abs(result.x + 1) < 0.0001)
        #expect(abs(result.y) < 0.0001)
    }
    
    @Test func rotateFullCircle() {
        let point = CGPoint(x: 3, y: 4)
        let result = GeometryHelpers.rotate(point, by: 2 * .pi)
        #expect(abs(result.x - 3) < 0.0001)
        #expect(abs(result.y - 4) < 0.0001)
    }
}

// MARK: - Point Deduplication Tests

struct GeometryHelpersDedupeTests {
    
    @Test func dedupeEmptyArray() {
        let result = GeometryHelpers.dedupePoints([])
        #expect(result.isEmpty)
    }
    
    @Test func dedupeSinglePoint() {
        let points = [CGPoint(x: 1, y: 2)]
        let result = GeometryHelpers.dedupePoints(points)
        #expect(result.count == 1)
    }
    
    @Test func dedupeNoDuplicates() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1)
        ]
        let result = GeometryHelpers.dedupePoints(points)
        #expect(result.count == 4)
    }
    
    @Test func dedupeWithDuplicates() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 0)
        ]
        let result = GeometryHelpers.dedupePoints(points)
        #expect(result.count == 2)
    }
    
    @Test func dedupeClosePoints() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.0001, y: 0.0001), // Close enough to be considered duplicate
            CGPoint(x: 1, y: 0)
        ]
        let result = GeometryHelpers.dedupePoints(points)
        #expect(result.count == 2)
    }
}

// MARK: - Bounds Tests

struct GeometryHelpersBoundsTests {
    
    @Test func boundsEmptyArray() {
        let result = GeometryHelpers.bounds(for: [])
        #expect(result == .zero)
    }
    
    @Test func boundsSinglePoint() {
        let points = [CGPoint(x: 5, y: 10)]
        let result = GeometryHelpers.bounds(for: points)
        #expect(result.minX == 5)
        #expect(result.minY == 10)
        #expect(result.width == 0)
        #expect(result.height == 0)
    }
    
    @Test func boundsRectangle() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 5),
            CGPoint(x: 0, y: 5)
        ]
        let result = GeometryHelpers.bounds(for: points)
        #expect(result.minX == 0)
        #expect(result.minY == 0)
        #expect(result.width == 10)
        #expect(result.height == 5)
    }
}

// MARK: - Polygon Winding Tests

struct GeometryHelpersWindingTests {
    
    @Test func clockwiseSquare() {
        // Clockwise square (negative area)
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 1),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 1, y: 0)
        ]
        let result = GeometryHelpers.polygonIsClockwise(points)
        #expect(result == true)
    }
    
    @Test func counterClockwiseSquare() {
        // Counter-clockwise square (positive area)
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1)
        ]
        let result = GeometryHelpers.polygonIsClockwise(points)
        #expect(result == false)
    }
}

// MARK: - Index Normalization Tests

struct GeometryHelpersIndexTests {
    
    @Test func normalizePositiveIndex() {
        let result = GeometryHelpers.normalizedIndex(2, count: 4)
        #expect(result == 2)
    }
    
    @Test func normalizeNegativeIndex() {
        let result = GeometryHelpers.normalizedIndex(-1, count: 4)
        #expect(result == 3)
    }
    
    @Test func normalizeOverflowIndex() {
        let result = GeometryHelpers.normalizedIndex(5, count: 4)
        #expect(result == 1)
    }
    
    @Test func nearestPointIndex() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10)
        ]
        let target = CGPoint(x: 9, y: 1)
        let result = GeometryHelpers.nearestPointIndex(to: target, in: points)
        #expect(result == 1) // Closest to (10, 0)
    }
}

// MARK: - Ray-Segment Intersection Tests

struct GeometryHelpersIntersectionTests {
    
    @Test func rayIntersectsSegment() {
        let origin = CGPoint(x: 0, y: 0)
        let direction = CGPoint(x: 1, y: 0) // Pointing right
        let segment = (CGPoint(x: 5, y: -5), CGPoint(x: 5, y: 5))
        
        let result = GeometryHelpers.raySegmentIntersection(origin: origin, direction: direction, segment: segment)
        #expect(result != nil)
        #expect(abs(result!.x - 5) < 0.0001)
        #expect(abs(result!.y) < 0.0001)
    }
    
    @Test func rayMissesSegment() {
        let origin = CGPoint(x: 0, y: 0)
        let direction = CGPoint(x: 1, y: 0) // Pointing right
        let segment = (CGPoint(x: 5, y: 10), CGPoint(x: 5, y: 20)) // Above the ray
        
        let result = GeometryHelpers.raySegmentIntersection(origin: origin, direction: direction, segment: segment)
        #expect(result == nil)
    }
    
    @Test func rayBehindOrigin() {
        let origin = CGPoint(x: 0, y: 0)
        let direction = CGPoint(x: 1, y: 0) // Pointing right
        let segment = (CGPoint(x: -5, y: -5), CGPoint(x: -5, y: 5)) // Behind the origin
        
        let result = GeometryHelpers.raySegmentIntersection(origin: origin, direction: direction, segment: segment)
        #expect(result == nil)
    }
}

// MARK: - Point-Line Distance Tests

struct GeometryHelpersLineDistanceTests {
    
    @Test func pointOnLine() {
        let point = CGPoint(x: 5, y: 0)
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 10, y: 0)
        
        let result = GeometryHelpers.pointLineDistance(point: point, a: a, b: b)
        #expect(result < 0.0001)
    }
    
    @Test func pointAboveLine() {
        let point = CGPoint(x: 5, y: 3)
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 10, y: 0)
        
        let result = GeometryHelpers.pointLineDistance(point: point, a: a, b: b)
        #expect(abs(result - 3) < 0.0001)
    }
    
    @Test func pointSegmentDistanceOnSegment() {
        let point = CGPoint(x: 5, y: 0)
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 10, y: 0)
        
        let result = GeometryHelpers.pointSegmentDistance(point: point, a: a, b: b)
        #expect(result < 0.0001)
    }
    
    @Test func pointSegmentDistanceBeyondEnd() {
        let point = CGPoint(x: 15, y: 0)
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 10, y: 0)
        
        let result = GeometryHelpers.pointSegmentDistance(point: point, a: a, b: b)
        #expect(abs(result - 5) < 0.0001) // Distance to endpoint (10, 0)
    }
}

// MARK: - Quadratic Bezier Tests

struct GeometryHelpersBezierTests {
    
    @Test func bezierPointAtStart() {
        let start = CGPoint(x: 0, y: 0)
        let control = CGPoint(x: 5, y: 10)
        let end = CGPoint(x: 10, y: 0)
        
        let result = GeometryHelpers.quadBezierPoint(t: 0, start: start, control: control, end: end)
        #expect(abs(result.x) < 0.0001)
        #expect(abs(result.y) < 0.0001)
    }
    
    @Test func bezierPointAtEnd() {
        let start = CGPoint(x: 0, y: 0)
        let control = CGPoint(x: 5, y: 10)
        let end = CGPoint(x: 10, y: 0)
        
        let result = GeometryHelpers.quadBezierPoint(t: 1, start: start, control: control, end: end)
        #expect(abs(result.x - 10) < 0.0001)
        #expect(abs(result.y) < 0.0001)
    }
    
    @Test func bezierPointAtMiddle() {
        let start = CGPoint(x: 0, y: 0)
        let control = CGPoint(x: 5, y: 10)
        let end = CGPoint(x: 10, y: 0)
        
        let result = GeometryHelpers.quadBezierPoint(t: 0.5, start: start, control: control, end: end)
        #expect(abs(result.x - 5) < 0.0001)
        #expect(abs(result.y - 5) < 0.0001) // Midpoint of quadratic
    }
    
    @Test func quadSplitPreservesEndpoints() {
        let start = CGPoint(x: 0, y: 0)
        let control = CGPoint(x: 5, y: 10)
        let end = CGPoint(x: 10, y: 0)
        
        let (left, right) = GeometryHelpers.quadSplit(start: start, control: control, end: end, t: 0.5)
        
        // Left segment starts at original start
        #expect(abs(left.start.x) < 0.0001)
        #expect(abs(left.start.y) < 0.0001)
        
        // Right segment ends at original end
        #expect(abs(right.end.x - 10) < 0.0001)
        #expect(abs(right.end.y) < 0.0001)
        
        // Split point matches
        #expect(abs(left.end.x - right.start.x) < 0.0001)
        #expect(abs(left.end.y - right.start.y) < 0.0001)
    }
}

// MARK: - Coordinate System Transformation Tests

struct GeometryHelpersCoordinateTests {
    
    @Test func displayPointFromRaw() {
        let raw = CGPoint(x: 5, y: 10)
        let display = GeometryHelpers.displayPoint(fromRaw: raw)
        #expect(display.x == 10)
        #expect(display.y == 5)
    }
    
    @Test func rawPointFromDisplay() {
        let display = CGPoint(x: 10, y: 5)
        let raw = GeometryHelpers.rawPoint(fromDisplay: display)
        #expect(raw.x == 5)
        #expect(raw.y == 10)
    }
    
    @Test func displaySizeFromRaw() {
        let raw = CGSize(width: 24, height: 18)
        let display = GeometryHelpers.displaySize(fromRaw: raw)
        #expect(display.width == 18)
        #expect(display.height == 24)
    }
    
    @Test func roundTripCoordinateTransform() {
        let original = CGPoint(x: 7, y: 13)
        let display = GeometryHelpers.displayPoint(fromRaw: original)
        let backToRaw = GeometryHelpers.rawPoint(fromDisplay: display)
        #expect(backToRaw.x == original.x)
        #expect(backToRaw.y == original.y)
    }
}

// MARK: - Outward Normal Tests

struct GeometryHelpersNormalTests {
    
    @Test func outwardNormalHorizontalClockwise() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 10, y: 0)
        let normal = GeometryHelpers.outwardNormal(from: start, to: end, clockwise: true)
        
        // For clockwise polygon, outward normal points down (positive Y)
        #expect(abs(normal.x) < 0.0001)
        #expect(abs(normal.y - 1) < 0.0001)
    }
    
    @Test func outwardNormalHorizontalCounterClockwise() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 10, y: 0)
        let normal = GeometryHelpers.outwardNormal(from: start, to: end, clockwise: false)
        
        // For counter-clockwise polygon, outward normal points up (negative Y)
        #expect(abs(normal.x) < 0.0001)
        #expect(abs(normal.y + 1) < 0.0001)
    }
}
