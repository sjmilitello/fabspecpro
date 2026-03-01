//
//  ValidationTests.swift
//  FabSpecProTests
//
//  Tests for ShapePathBuilder validation methods.
//

import Foundation
import SwiftData
import Testing
@testable import FabSpecPro

// MARK: - Validation Issue Tests

struct ValidationIssueTests {
    
    @Test func errorSeverityForCutoutOutsideBounds() {
        let issue = ShapePathBuilder.ValidationIssue.cutoutOutsideBounds(cutoutId: UUID())
        #expect(issue.severity == .error)
    }
    
    @Test func errorSeverityForCutoutsOverlap() {
        let issue = ShapePathBuilder.ValidationIssue.cutoutsOverlap(cutoutId1: UUID(), cutoutId2: UUID())
        #expect(issue.severity == .error)
    }
    
    @Test func errorSeverityForCornerRadiusConflictsWithAngle() {
        let issue = ShapePathBuilder.ValidationIssue.cornerRadiusConflictsWithAngle(
            cornerRadiusId: UUID(),
            angleId: UUID(),
            cornerIndex: 0
        )
        #expect(issue.severity == .error)
    }
    
    @Test func warningSeverityForCutoutOnCurvedEdge() {
        let issue = ShapePathBuilder.ValidationIssue.cutoutOnCurvedEdge(cutoutId: UUID(), edge: .top)
        #expect(issue.severity == .warning)
    }
    
    @Test func warningSeverityForCornerRadiusTooLarge() {
        let issue = ShapePathBuilder.ValidationIssue.cornerRadiusTooLarge(
            cornerRadiusId: UUID(),
            cornerIndex: 0,
            maxRadius: 5.0
        )
        #expect(issue.severity == .warning)
    }
    
    @Test func issueDescriptionsAreNotEmpty() {
        let issues: [ShapePathBuilder.ValidationIssue] = [
            .cutoutOnCurvedEdge(cutoutId: UUID(), edge: .top),
            .cutoutOverlapsCornerRadius(cutoutId: UUID(), cornerIndex: 0),
            .cutoutOverlapsAngleCut(cutoutId: UUID(), cornerIndex: 0),
            .cutoutsOverlap(cutoutId1: UUID(), cutoutId2: UUID()),
            .cutoutOutsideBounds(cutoutId: UUID()),
            .curveOnNotchedEdge(curveId: UUID(), edge: .top),
            .cornerRadiusOnCurvedEdge(cornerRadiusId: UUID(), cornerIndex: 0),
            .cornerRadiusTooLarge(cornerRadiusId: UUID(), cornerIndex: 0, maxRadius: 5.0),
            .cornerRadiusConflictsWithAngle(cornerRadiusId: UUID(), angleId: UUID(), cornerIndex: 0),
            .curveConflictsWithCornerRadius(curveId: UUID(), cornerRadiusId: UUID(), cornerIndex: 0)
        ]
        
        for issue in issues {
            #expect(!issue.description.isEmpty)
        }
    }
    
    @Test func issueEquality() {
        let id1 = UUID()
        let id2 = UUID()
        
        let issue1 = ShapePathBuilder.ValidationIssue.cutoutOutsideBounds(cutoutId: id1)
        let issue2 = ShapePathBuilder.ValidationIssue.cutoutOutsideBounds(cutoutId: id1)
        let issue3 = ShapePathBuilder.ValidationIssue.cutoutOutsideBounds(cutoutId: id2)
        
        #expect(issue1 == issue2)
        #expect(issue1 != issue3)
    }
}

// MARK: - Cutout Validation Tests

struct CutoutValidationTests {
    
    @Test @MainActor func noCutoutsReturnsNoIssues() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container)
        
        let issues = ShapePathBuilder.validatePiece(piece)
        #expect(issues.isEmpty)
    }
    
    @Test @MainActor func cutoutOnCurvedEdgeReturnsWarning() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add a curve on top edge
        piece.curvedEdges.append(CurvedEdge(edge: .top, radius: 3, isConcave: false))
        
        // Add a cutout touching the top edge
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 10, centerY: 2, isNotch: true)
        piece.cutouts.append(cutout)
        
        let issues = ShapePathBuilder.validatePiece(piece)
        let curvedEdgeIssues = issues.filter {
            if case .cutoutOnCurvedEdge = $0 { return true }
            return false
        }
        
        #expect(!curvedEdgeIssues.isEmpty)
    }
    
    @Test func cutoutsOverlapDetection() {
        let cutout1 = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 5, centerY: 5)
        let cutout2 = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 7, centerY: 5) // Overlaps
        
        let overlaps = ShapePathBuilder.cutoutsOverlap(cutout1, cutout2)
        #expect(overlaps == true)
    }
    
    @Test func cutoutsDoNotOverlap() {
        let cutout1 = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 5, centerY: 5)
        let cutout2 = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 15, centerY: 5) // Far apart
        
        let overlaps = ShapePathBuilder.cutoutsOverlap(cutout1, cutout2)
        #expect(overlaps == false)
    }
    
    @Test func circlesCutoutsOverlap() {
        let cutout1 = Cutout(kind: .circle, width: 4, height: 4, centerX: 5, centerY: 5)
        let cutout2 = Cutout(kind: .circle, width: 4, height: 4, centerX: 7, centerY: 5) // Centers 2 apart, radius 2 each
        
        let overlaps = ShapePathBuilder.cutoutsOverlap(cutout1, cutout2)
        #expect(overlaps == true)
    }
    
    @Test func circlesCutoutsDoNotOverlap() {
        let cutout1 = Cutout(kind: .circle, width: 4, height: 4, centerX: 5, centerY: 5)
        let cutout2 = Cutout(kind: .circle, width: 4, height: 4, centerX: 15, centerY: 5) // Centers 10 apart, radius 2 each
        
        let overlaps = ShapePathBuilder.cutoutsOverlap(cutout1, cutout2)
        #expect(overlaps == false)
    }
    
    @Test func cutoutWithinBoundsRectangle() {
        let cutout = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 5, centerY: 5)
        let size = CGSize(width: 10, height: 10)
        
        let within = ShapePathBuilder.cutoutIsWithinBounds(cutout, size: size, shape: .rectangle)
        #expect(within == true)
    }
    
    @Test func cutoutOutsideBoundsRectangle() {
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 1, centerY: 1) // Extends past 0,0
        let size = CGSize(width: 10, height: 10)
        
        let within = ShapePathBuilder.cutoutIsWithinBounds(cutout, size: size, shape: .rectangle)
        #expect(within == false)
    }
    
    @Test func notchAllowedToBeTouchBoundary() {
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 0, centerY: 5, isNotch: true)
        let size = CGSize(width: 10, height: 10)
        
        let within = ShapePathBuilder.cutoutIsWithinBounds(cutout, size: size, shape: .rectangle)
        #expect(within == true)
    }
}

// MARK: - Curve Validation Tests

struct CurveValidationTests {
    
    @Test @MainActor func curveOnNotchedEdgeReturnsWarning() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add a notch on top edge
        let notch = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 10, centerY: 0, isNotch: true)
        piece.cutouts.append(notch)
        
        // Add a curve on top edge
        piece.curvedEdges.append(CurvedEdge(edge: .top, radius: 3, isConcave: false))
        
        let issues = ShapePathBuilder.validatePiece(piece)
        let notchedEdgeIssues = issues.filter {
            if case .curveOnNotchedEdge = $0 { return true }
            return false
        }
        
        #expect(!notchedEdgeIssues.isEmpty)
    }
    
    @Test @MainActor func curveConflictsWithNotchDetection() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add a notch on top edge
        let notch = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 10, centerY: 0, isNotch: true)
        piece.cutouts.append(notch)
        
        let curve = CurvedEdge(edge: .top, radius: 3, isConcave: false)
        
        let conflicts = ShapePathBuilder.curveConflictsWithNotch(
            curve: curve,
            piece: piece,
            size: ShapePathBuilder.pieceSize(for: piece)
        )
        
        #expect(conflicts == true)
    }
    
    @Test @MainActor func curveDoesNotConflictWhenNoNotches() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        let curve = CurvedEdge(edge: .top, radius: 3, isConcave: false)
        
        let conflicts = ShapePathBuilder.curveConflictsWithNotch(
            curve: curve,
            piece: piece,
            size: ShapePathBuilder.pieceSize(for: piece)
        )
        
        #expect(conflicts == false)
    }
}

// MARK: - Corner Radius Validation Tests

struct CornerRadiusValidationTests {
    
    @Test @MainActor func cornerRadiusConflictsWithAngleCut() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add corner radius at corner 0
        let radius = CornerRadius(cornerIndex: 0, radius: 3)
        piece.cornerRadii.append(radius)
        
        // Add angle cut at same corner
        let angleCut = AngleCut()
        angleCut.anchorCornerIndex = 0
        angleCut.anchorOffset = 3
        angleCut.secondaryCornerIndex = 3
        angleCut.secondaryOffset = 3
        piece.angleCuts.append(angleCut)
        
        let issues = ShapePathBuilder.validatePiece(piece)
        let conflictIssues = issues.filter {
            if case .cornerRadiusConflictsWithAngle = $0 { return true }
            return false
        }
        
        #expect(!conflictIssues.isEmpty)
    }
    
    @Test @MainActor func cornerRadiusOnCurvedEdgeReturnsWarning() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add curve on top edge
        piece.curvedEdges.append(CurvedEdge(edge: .top, radius: 3, isConcave: false))
        
        // Add corner radius at corner 0 (top-left, adjacent to top edge)
        let radius = CornerRadius(cornerIndex: 0, radius: 3)
        piece.cornerRadii.append(radius)
        
        let issues = ShapePathBuilder.validatePiece(piece)
        let curvedEdgeIssues = issues.filter {
            if case .cornerRadiusOnCurvedEdge = $0 { return true }
            return false
        }
        
        #expect(!curvedEdgeIssues.isEmpty)
    }
    
    @Test @MainActor func zeroRadiusDoesNotGenerateIssues() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add zero radius
        let radius = CornerRadius(cornerIndex: 0, radius: 0)
        piece.cornerRadii.append(radius)
        
        // Add angle cut at same corner
        let angleCut = AngleCut()
        angleCut.anchorCornerIndex = 0
        angleCut.anchorOffset = 3
        piece.angleCuts.append(angleCut)
        
        let issues = ShapePathBuilder.validatePiece(piece)
        let conflictIssues = issues.filter {
            if case .cornerRadiusConflictsWithAngle = $0 { return true }
            return false
        }
        
        // Zero radius should not generate conflict
        #expect(conflictIssues.isEmpty)
    }
    
    @Test @MainActor func negativeCornerIndexIgnored() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add radius with negative index (invalid)
        let radius = CornerRadius(cornerIndex: -1, radius: 3)
        piece.cornerRadii.append(radius)
        
        let issues = ShapePathBuilder.validatePiece(piece)
        
        // Invalid corner index should not cause issues
        #expect(issues.isEmpty)
    }
}

// MARK: - Cutout-Corner Radius Overlap Tests

struct CutoutCornerRadiusOverlapTests {
    
    @Test func cutoutOverlapsCornerRadiusAtTopLeft() {
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 2, centerY: 2)
        let cornerRadius = CornerRadius(cornerIndex: 0, radius: 3) // Top-left
        let size = CGSize(width: 20, height: 20)
        
        // Create a minimal piece for testing
        let overlaps = ShapePathBuilder.cutoutOverlapsCornerRadius(
            cutout: cutout,
            cornerRadius: cornerRadius,
            piece: Piece(name: "Test", project: nil),
            size: size
        )
        
        #expect(overlaps == true)
    }
    
    @Test func cutoutDoesNotOverlapDistantCornerRadius() {
        let cutout = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 10, centerY: 10)
        let cornerRadius = CornerRadius(cornerIndex: 0, radius: 2) // Top-left
        let size = CGSize(width: 20, height: 20)
        
        let overlaps = ShapePathBuilder.cutoutOverlapsCornerRadius(
            cutout: cutout,
            cornerRadius: cornerRadius,
            piece: Piece(name: "Test", project: nil),
            size: size
        )
        
        #expect(overlaps == false)
    }
}

// MARK: - Cutout-Angle Cut Overlap Tests

struct CutoutAngleCutOverlapTests {
    
    @Test func cutoutOverlapsAngleCutNearAnchor() {
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 2, centerY: 2)
        let angleCut = AngleCut()
        angleCut.anchorCornerIndex = 0
        angleCut.anchorOffset = 5
        
        let size = CGSize(width: 20, height: 20)
        
        let overlaps = ShapePathBuilder.cutoutOverlapsAngleCut(
            cutout: cutout,
            angleCut: angleCut,
            piece: Piece(name: "Test", project: nil),
            size: size
        )
        
        #expect(overlaps == true)
    }
    
    @Test func cutoutDoesNotOverlapDistantAngleCut() {
        let cutout = Cutout(kind: .rectangle, width: 2, height: 2, centerX: 10, centerY: 10)
        let angleCut = AngleCut()
        angleCut.anchorCornerIndex = 0
        angleCut.anchorOffset = 3
        
        let size = CGSize(width: 20, height: 20)
        
        let overlaps = ShapePathBuilder.cutoutOverlapsAngleCut(
            cutout: cutout,
            angleCut: angleCut,
            piece: Piece(name: "Test", project: nil),
            size: size
        )
        
        #expect(overlaps == false)
    }
}

// MARK: - Cutout on Curved Edge Tests

struct CutoutCurvedEdgeTests {
    
    @Test @MainActor func cutoutOnTopCurvedEdge() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add curve on top edge
        piece.curvedEdges.append(CurvedEdge(edge: .top, radius: 3, isConcave: false))
        
        // Cutout touching top edge
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 10, centerY: 2)
        
        let edge = ShapePathBuilder.cutoutIsOnCurvedEdge(
            cutout: cutout,
            piece: piece,
            size: ShapePathBuilder.pieceSize(for: piece)
        )
        
        #expect(edge == .top)
    }
    
    @Test @MainActor func cutoutNotOnCurvedEdge() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add curve on top edge
        piece.curvedEdges.append(CurvedEdge(edge: .top, radius: 3, isConcave: false))
        
        // Cutout in the middle (not touching any edge)
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 10, centerY: 10)
        
        let edge = ShapePathBuilder.cutoutIsOnCurvedEdge(
            cutout: cutout,
            piece: piece,
            size: ShapePathBuilder.pieceSize(for: piece)
        )
        
        #expect(edge == nil)
    }
    
    @Test @MainActor func cutoutOnBottomCurvedEdge() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add curve on bottom edge
        piece.curvedEdges.append(CurvedEdge(edge: .bottom, radius: 3, isConcave: false))
        
        // Cutout touching bottom edge
        let cutout = Cutout(kind: .rectangle, width: 4, height: 4, centerX: 10, centerY: 18)
        
        let edge = ShapePathBuilder.cutoutIsOnCurvedEdge(
            cutout: cutout,
            piece: piece,
            size: ShapePathBuilder.pieceSize(for: piece)
        )
        
        #expect(edge == .bottom)
    }
}

// MARK: - Multiple Issues Tests

struct MultipleValidationIssuesTests {
    
    @Test @MainActor func multipleIssuesDetected() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add curve on top edge
        piece.curvedEdges.append(CurvedEdge(edge: .top, radius: 3, isConcave: false))
        
        // Add corner radius at corner 0 (conflicts with curve)
        let radius = CornerRadius(cornerIndex: 0, radius: 3)
        piece.cornerRadii.append(radius)
        
        // Add angle cut at corner 0 (conflicts with radius)
        let angleCut = AngleCut()
        angleCut.anchorCornerIndex = 0
        angleCut.anchorOffset = 3
        piece.angleCuts.append(angleCut)
        
        let issues = ShapePathBuilder.validatePiece(piece)
        
        // Should have at least 2 issues
        #expect(issues.count >= 2)
    }
    
    @Test @MainActor func overlappingCutoutsDetectedMultiple() throws {
        let container = try createTestContainer()
        let piece = createTestPiece(container: container, width: "20", height: "20")
        
        // Add three overlapping cutouts
        piece.cutouts.append(Cutout(kind: .rectangle, width: 4, height: 4, centerX: 10, centerY: 10))
        piece.cutouts.append(Cutout(kind: .rectangle, width: 4, height: 4, centerX: 11, centerY: 10))
        piece.cutouts.append(Cutout(kind: .rectangle, width: 4, height: 4, centerX: 12, centerY: 10))
        
        let issues = ShapePathBuilder.validatePiece(piece)
        let overlapIssues = issues.filter {
            if case .cutoutsOverlap = $0 { return true }
            return false
        }
        
        // Should detect multiple overlaps
        #expect(overlapIssues.count >= 2)
    }
}
