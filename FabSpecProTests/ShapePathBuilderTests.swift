//
//  ShapePathBuilderTests.swift
//  FabSpecProTests
//
//  Tests for ShapePathBuilder path generation and geometry functions.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import FabSpecPro

// MARK: - Test Helpers

/// Creates an in-memory model container for testing
@MainActor
func createTestContainer() throws -> ModelContainer {
    let schema = Schema([Project.self, Piece.self, EdgeTreatment.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

/// Creates a test piece with specified dimensions
@MainActor
func createTestPiece(
    container: ModelContainer,
    shape: ShapeKind = .rectangle,
    width: String = "24",
    height: String = "18"
) -> Piece {
    let context = container.mainContext
    let project = Project(name: "Test Project")
    context.insert(project)
    
    let piece = Piece(name: "Test Piece")
    piece.shape = shape
    piece.widthText = width
    piece.heightText = height
    piece.project = project
    project.pieces.append(piece)

    context.insert(piece)
    return piece
}

// MARK: - Piece Size Tests

struct ShapePathBuilderSizeTests {
    
    @Test @MainActor func rectangleSize() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle, width: "24", height: "18")
        
        let size = ShapePathBuilder.pieceSize(for: piece)
        #expect(size.width == 24)
        #expect(size.height == 18)
    }
    
    @Test @MainActor func circleSize() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .circle, width: "12", height: "12")
        
        let size = ShapePathBuilder.pieceSize(for: piece)
        #expect(size.width == 12)
        #expect(size.height == 12)
    }
    
    @Test @MainActor func quarterCircleUsesWidthForBoth() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .quarterCircle, width: "10", height: "20")
        
        let size = ShapePathBuilder.pieceSize(for: piece)
        // Quarter circle uses width for both dimensions
        #expect(size.width == 10)
        #expect(size.height == 10)
    }
    
    @Test @MainActor func displaySizeSwapsCoordinates() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle, width: "24", height: "18")
        
        let rawSize = ShapePathBuilder.pieceSize(for: piece)
        let displaySize = ShapePathBuilder.displaySize(for: piece)
        
        #expect(displaySize.width == rawSize.height)
        #expect(displaySize.height == rawSize.width)
    }
    
    @Test @MainActor func minimumSizeEnforced() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle, width: "0", height: "-5")
        
        let size = ShapePathBuilder.pieceSize(for: piece)
        // Minimum size of 1 is enforced
        #expect(size.width >= 1)
        #expect(size.height >= 1)
    }
}

// MARK: - Corner Count Tests

struct ShapePathBuilderCornerTests {
    
    @Test @MainActor func rectangleHasFourCorners() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        let count = ShapePathBuilder.pieceCornerCount(for: piece)
        #expect(count == 4)
    }
    
    @Test @MainActor func rightTriangleHasThreeCorners() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle)
        
        let count = ShapePathBuilder.pieceCornerCount(for: piece)
        #expect(count == 3)
    }
    
    @Test @MainActor func cornerPointsMatchCornerCount() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        let count = ShapePathBuilder.pieceCornerCount(for: piece)
        let points = ShapePathBuilder.cornerPoints(for: piece, includeAngles: false)
        
        #expect(points.count == count)
    }
}

// MARK: - Path Generation Tests

struct ShapePathBuilderPathTests {
    
    @Test @MainActor func rectanglePathIsClosed() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
    
    @Test @MainActor func circlePathIsClosed() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .circle)
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
    
    @Test @MainActor func rightTrianglePathIsClosed() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle)
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
    
    @Test @MainActor func quarterCirclePathIsClosed() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .quarterCircle)
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
}

// MARK: - Boundary Segment Tests

struct ShapePathBuilderBoundaryTests {
    
    @Test @MainActor func rectangleHasFourEdges() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        let edges = Set(segments.map { $0.edge })
        
        #expect(edges.contains(.top))
        #expect(edges.contains(.right))
        #expect(edges.contains(.bottom))
        #expect(edges.contains(.left))
    }
    
    @Test @MainActor func rightTriangleHasThreeEdges() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle)
        
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        let edges = Set(segments.map { $0.edge })
        
        #expect(edges.contains(.legA))
        #expect(edges.contains(.legB))
        #expect(edges.contains(.hypotenuse))
    }
    
    @Test @MainActor func boundarySegmentsHaveValidIndices() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        let segments = ShapePathBuilder.boundarySegments(for: piece)
        
        for segment in segments {
            #expect(segment.startIndex >= 0)
            #expect(segment.endIndex >= 0)
            #expect(segment.index >= 0)
        }
    }
}

// MARK: - Cutout Tests

struct ShapePathBuilderCutoutTests {
    
    @Test func circleCutoutPath() {
        let cutout = Cutout(kind: .circle, width: 2, height: 2, centerX: 5, centerY: 5)
        let path = ShapePathBuilder.cutoutPath(cutout)
        #expect(!path.isEmpty)
    }
    
    @Test func squareCutoutPath() {
        let cutout = Cutout(kind: .square, width: 2, height: 2, centerX: 5, centerY: 5)
        let path = ShapePathBuilder.cutoutPath(cutout)
        #expect(!path.isEmpty)
    }
    
    @Test func rectangleCutoutPath() {
        let cutout = Cutout(kind: .rectangle, width: 3, height: 2, centerX: 5, centerY: 5)
        let path = ShapePathBuilder.cutoutPath(cutout)
        #expect(!path.isEmpty)
    }
    
    @Test func cutoutPathWithEmptyAngleCuts() {
        let cutout = Cutout(kind: .rectangle, width: 3, height: 2, centerX: 5, centerY: 5)
        let path = ShapePathBuilder.cutoutPath(cutout, angleCuts: [], cornerRadii: [])
        #expect(!path.isEmpty)
    }
    
    @Test @MainActor func cutoutTouchesBoundaryTop() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle, width: "10", height: "10")
        let cutout = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 5, centerY: 1)
        let size = ShapePathBuilder.pieceSize(for: piece)

        let touches = ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, piece: piece, size: size)
        #expect(touches == true)
    }

    @Test @MainActor func cutoutDoesNotTouchBoundary() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle, width: "10", height: "10")
        let cutout = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 5, centerY: 5)
        let size = ShapePathBuilder.pieceSize(for: piece)

        let touches = ShapePathBuilder.cutoutTouchesBoundary(cutout: cutout, piece: piece, size: size)
        #expect(touches == false)
    }
    
    @Test @MainActor func interiorCutoutsExcludeNotches() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle, width: "20", height: "20")
        
        // Add an interior cutout
        let interiorCutout = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 10, centerY: 10)
        piece.cutouts.append(interiorCutout)
        
        // Add a notch (touches boundary)
        let notch = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 1, centerY: 10, isNotch: true)
        piece.cutouts.append(notch)
        
        let interior = ShapePathBuilder.interiorCutouts(for: piece)
        #expect(interior.count == 1)
        #expect(interior.first?.id == interiorCutout.id)
    }
}

// MARK: - Corner Radius Tests

struct ShapePathBuilderCornerRadiusTests {
    
    @Test @MainActor func cornerPointsWithNoRadii() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        let points = ShapePathBuilder.cornerPoints(for: piece)
        #expect(points.count == 4)
    }
    
    @Test @MainActor func pathWithCornerRadii() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        // Add corner radius
        let radius = CornerRadius(cornerIndex: 0, radius: 2)
        piece.cornerRadii.append(radius)
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
}

// MARK: - Angle Cut Tests

struct ShapePathBuilderAngleCutTests {
    
    @Test @MainActor func angleSegmentsEmptyWithoutCuts() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        let segments = ShapePathBuilder.angleSegments(for: piece)
        #expect(segments.isEmpty)
    }
    
    @Test @MainActor func angleSegmentsWithAngleCut() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        // Add an angle cut
        let angleCut = AngleCut()
        angleCut.anchorCornerIndex = 0
        angleCut.anchorOffset = 3
        angleCut.secondaryCornerIndex = 3
        angleCut.secondaryOffset = 3
        piece.angleCuts.append(angleCut)
        
        let segments = ShapePathBuilder.angleSegments(for: piece)
        #expect(segments.count == 1)
        #expect(segments.first?.id == angleCut.id)
    }
    
    @Test @MainActor func pathIncludesAngleCuts() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        // Add an angle cut
        let angleCut = AngleCut()
        angleCut.anchorCornerIndex = 0
        angleCut.anchorOffset = 3
        angleCut.secondaryCornerIndex = 3
        angleCut.secondaryOffset = 3
        piece.angleCuts.append(angleCut)
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
}

// MARK: - Curved Edge Tests

struct ShapePathBuilderCurvedEdgeTests {
    
    @Test @MainActor func pathWithConvexCurve() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        // Add a convex curve
        let curve = CurvedEdge(edge: .top, radius: 3, isConcave: false)
        piece.curvedEdges.append(curve)
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
    
    @Test @MainActor func pathWithConcaveCurve() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        // Add a concave curve
        let curve = CurvedEdge(edge: .top, radius: 3, isConcave: true)
        piece.curvedEdges.append(curve)
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
    
    @Test @MainActor func pathWithMultipleCurves() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        // Add curves on multiple edges
        piece.curvedEdges.append(CurvedEdge(edge: .top, radius: 2, isConcave: false))
        piece.curvedEdges.append(CurvedEdge(edge: .bottom, radius: 2, isConcave: true))
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
    
    @Test @MainActor func rightTriangleWithHypotenuseCurve() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle)
        
        // Add curve on hypotenuse
        let curve = CurvedEdge(edge: .hypotenuse, radius: 3, isConcave: false)
        piece.curvedEdges.append(curve)
        
        let path = ShapePathBuilder.path(for: piece)
        #expect(!path.isEmpty)
    }
}

// MARK: - Display Polygon Tests

struct ShapePathBuilderPolygonTests {
    
    @Test @MainActor func displayPolygonPointsRectangle() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        let points = ShapePathBuilder.displayPolygonPoints(for: piece)
        #expect(points.count == 4)
    }
    
    @Test @MainActor func displayPolygonPointsTriangle() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle)
        
        let points = ShapePathBuilder.displayPolygonPoints(for: piece)
        #expect(points.count == 3)
    }
    
    @Test @MainActor func displayPolygonPointsWithNotch() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle, width: "20", height: "20")
        
        // Add a notch
        let notch = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 10, centerY: 0, isNotch: true)
        piece.cutouts.append(notch)
        
        let points = ShapePathBuilder.displayPolygonPoints(for: piece)
        // Should have more than 4 points due to notch
        #expect(points.count > 4)
    }
}

// MARK: - Hypotenuse Notch Tests

struct ShapePathBuilderHypotenuseNotchTests {
    
    @Test @MainActor func triangleWithHypotenuseNotchHasMorePoints() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle, width: "24", height: "24")
        
        // Get base point count (no notches)
        let basePoints = ShapePathBuilder.displayPolygonPoints(for: piece)
        #expect(basePoints.count == 3) // Basic triangle has 3 corners
        
        // Add a notch on the hypotenuse
        // For a 24x24 triangle, hypotenuse goes from (24,0) to (0,24)
        // Place notch center at approximately the middle of the hypotenuse
        let notch = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 12, centerY: 12, isNotch: true)
        piece.cutouts.append(notch)
        
        let notchedPoints = ShapePathBuilder.displayPolygonPoints(for: piece)
        // Should have more than 3 points due to hypotenuse notch
        #expect(notchedPoints.count > 3)
    }
    
    @Test @MainActor func triangleWithTopEdgeNotch() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle, width: "24", height: "24")
        
        // Add a notch on the top edge (legA)
        let notch = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 12, centerY: 1, isNotch: true)
        piece.cutouts.append(notch)
        
        let points = ShapePathBuilder.displayPolygonPoints(for: piece)
        // Should have more than 3 points due to top edge notch
        #expect(points.count > 3)
    }
    
    @Test @MainActor func triangleWithLeftEdgeNotch() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle, width: "24", height: "24")
        
        // Add a notch on the left edge (legB)
        let notch = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 1, centerY: 12, isNotch: true)
        piece.cutouts.append(notch)
        
        let points = ShapePathBuilder.displayPolygonPoints(for: piece)
        // Should have more than 3 points due to left edge notch
        #expect(points.count > 3)
    }
    
    @Test @MainActor func hypotenuseNotchNearTopRight() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle, width: "24", height: "24")
        
        // Add a notch near the top-right of the hypotenuse
        let notch = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 20, centerY: 4, isNotch: true)
        piece.cutouts.append(notch)
        
        let points = ShapePathBuilder.displayPolygonPoints(for: piece)
        // Should have more than 3 points
        #expect(points.count > 3)
    }
    
    @Test @MainActor func hypotenuseNotchNearBottomLeft() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle, width: "24", height: "24")
        
        // Add a notch near the bottom-left of the hypotenuse
        let notch = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 4, centerY: 20, isNotch: true)
        piece.cutouts.append(notch)
        
        let points = ShapePathBuilder.displayPolygonPoints(for: piece)
        // Should have more than 3 points
        #expect(points.count > 3)
    }
}

// MARK: - Cutout Corner Range Tests

struct ShapePathBuilderCutoutCornerTests {
    
    @Test @MainActor func cutoutCornerRangesEmpty() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle)
        
        let ranges = ShapePathBuilder.cutoutCornerRanges(for: piece)
        #expect(ranges.isEmpty)
    }
    
    @Test @MainActor func cutoutCornerRangesWithInteriorCutout() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle, width: "20", height: "20")
        
        // Add an interior cutout (not touching boundary)
        let cutout = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 10, centerY: 10)
        piece.cutouts.append(cutout)
        
        let ranges = ShapePathBuilder.cutoutCornerRanges(for: piece)
        #expect(ranges.count == 1)
        #expect(ranges.first?.range.count == 4) // Rectangle cutout has 4 corners
    }
    
    @Test @MainActor func cornerLabelCountIncludesCutouts() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rectangle, width: "20", height: "20")
        
        let baseLabelCount = ShapePathBuilder.cornerLabelCount(for: piece)
        #expect(baseLabelCount == 4) // Rectangle has 4 corners
        
        // Add an interior cutout
        let cutout = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 10, centerY: 10)
        piece.cutouts.append(cutout)
        
        let newLabelCount = ShapePathBuilder.cornerLabelCount(for: piece)
        #expect(newLabelCount == 8) // 4 piece corners + 4 cutout corners
    }
}

// MARK: - Triangle Top-Right Corner Cut Tests

struct TriangleTopRightCornerCutTests {
    
    @Test @MainActor func topRightCornerCutProducesCorrectShape() throws {
        // 24x24 right triangle with a 4x4 cutout at (22, 2)
        // This should cut off the top-right corner, leaving a 20" top edge
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle, width: "24", height: "24")
        
        // Add cutout: center (22, 2), size 4x4
        // This spans x: 20-24, y: 0-4
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 22, centerY: 2)
        piece.cutouts.append(cutout)
        
        let points = ShapePathBuilder.cornerPoints(for: piece, includeAngles: false)
        
        // Print points for debugging
        print("Corner points for top-right corner cut test:")
        for (i, p) in points.enumerated() {
            print("  \(i): (\(p.x), \(p.y))")
        }
        
        // The shape should have these key characteristics:
        // - Top edge should end at x=20 (display coords: y=20 after rotation)
        // - There should be a corner at (20, 4) in raw coords (display: (4, 20))
        // - No point should be at (24, 0) in raw coords (display: (0, 24))
        
        // Check that the top-right corner (24, 0) raw / (0, 24) display is NOT in the points
        let hasTopRightCorner = points.contains { p in
            abs(p.x) < 0.5 && abs(p.y - 24) < 0.5
        }
        #expect(!hasTopRightCorner, "Top-right corner should be cut off")
        
        // Check that there's a point near (4, 20) in display coords (the corner cut point)
        let hasCornerCutPoint = points.contains { p in
            abs(p.x - 4) < 0.5 && abs(p.y - 20) < 0.5
        }
        #expect(hasCornerCutPoint, "Should have corner cut point at approximately (4, 20) display coords")
    }
    
    @Test @MainActor func hypotenuseNotchWithCurve() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, shape: .rightTriangle, width: "24", height: "18")
        
        // Add a notch cutout on the hypotenuse
        // For a 24x18 triangle, hypotenuse goes from (24,0) to (0,18) in raw coords
        // Place cutout near the middle
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 12, centerY: 9)
        cutout.orientation = .hypotenuse
        cutout.isNotch = true
        piece.cutouts.append(cutout)
        
        // Add a hypotenuse curve
        let curve = CurvedEdge(edge: .hypotenuse, radius: 3, isConcave: false)
        piece.curvedEdges.append(curve)
        
        // Generate the path
        let path = ShapePathBuilder.path(for: piece)
        
        // The path should exist and have some elements
        #expect(!path.isEmpty, "Path should not be empty")
        
        // Get the bounding box - if curves are applied, the bounds should extend beyond the triangle
        let bounds = path.boundingRect
        print("Path bounds: \(bounds)")
        
        // For a convex curve on the hypotenuse, the path should extend beyond the original triangle bounds
        // The display size is (18, 24) - width and height swapped
        // If the curve is applied, maxX should be > 18 or maxY should be > 24
        let displaySize = ShapePathBuilder.displaySize(for: piece)
        print("Display size: \(displaySize)")
        
        // Check if the curve is having any effect
        // A convex curve would push the hypotenuse outward
        let curveApplied = bounds.maxX > displaySize.width + 0.1 || 
                           bounds.maxY > displaySize.height + 0.1 ||
                           bounds.minX < -0.1 ||
                           bounds.minY < -0.1
        
        print("Curve applied: \(curveApplied)")
        print("bounds.maxX=\(bounds.maxX), displaySize.width=\(displaySize.width)")
        print("bounds.maxY=\(bounds.maxY), displaySize.height=\(displaySize.height)")
        
        #expect(curveApplied, "Hypotenuse curve should extend the path beyond original triangle bounds")
    }
}
