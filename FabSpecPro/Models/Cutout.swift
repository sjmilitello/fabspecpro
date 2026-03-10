import Foundation
import SwiftData

enum CutoutOrientation: String, CaseIterable {
    case legs = "legs"           // Aligned with legA/legB (default for triangles)
    case hypotenuse = "hypotenuse"  // Rotated to align with hypotenuse
}

@Model
final class Cutout {
    var id: UUID
    var kindRaw: String
    var width: Double
    var height: Double
    var centerX: Double
    var centerY: Double
    var cornerIndex: Int
    var cornerAnchorX: Double
    var cornerAnchorY: Double
    var isNotch: Bool
    var isApplied: Bool = true
    var createdAt: Date
    var piece: Piece?
    var orientationRaw: String = "legs"

    init(kind: CutoutKind, width: Double, height: Double, centerX: Double, centerY: Double, isNotch: Bool = false, isApplied: Bool = true, cornerIndex: Int = -1, cornerAnchorX: Double = -1, cornerAnchorY: Double = -1, createdAt: Date = Date(), orientation: CutoutOrientation = .legs) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.width = width
        self.height = height
        self.centerX = centerX
        self.centerY = centerY
        self.cornerIndex = cornerIndex
        self.cornerAnchorX = cornerAnchorX
        self.cornerAnchorY = cornerAnchorY
        self.isNotch = isNotch
        self.isApplied = isApplied
        self.createdAt = createdAt
        self.orientationRaw = orientation.rawValue
    }

    var orientation: CutoutOrientation {
        get { CutoutOrientation(rawValue: orientationRaw) ?? .legs }
        set { orientationRaw = newValue.rawValue }
    }

    var kind: CutoutKind {
        get { CutoutKind(rawValue: kindRaw) ?? .circle }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class CurvedEdge {
    var id: UUID
    var edgeRaw: String
    var radius: Double
    var isConcave: Bool
    var piece: Piece?
    
    /// Start corner index for corner-based curve selection (-1 means use legacy edge-based)
    var startCornerIndex: Int = -1
    /// End corner index for corner-based curve selection (-1 means use legacy edge-based)
    var endCornerIndex: Int = -1

    /// Stable boundary segment index for the start point (-1 means unset)
    var startBoundarySegmentIndex: Int = -1
    /// True if the start point is the end of the boundary segment
    var startBoundaryIsEnd: Bool = false
    /// Stable boundary segment index for the end point (-1 means unset)
    var endBoundarySegmentIndex: Int = -1
    /// True if the end point is the end of the boundary segment
    var endBoundaryIsEnd: Bool = false
    /// Normalized progress along the edge for the start point (-1 means unset)
    var startEdgeProgress: Double = -1
    /// Normalized progress along the edge for the end point (-1 means unset)
    var endEdgeProgress: Double = -1

    /// Legacy initializer for edge-based curves (backward compatibility)
    init(edge: EdgePosition, radius: Double, isConcave: Bool) {
        self.id = UUID()
        self.edgeRaw = edge.rawValue
        self.radius = radius
        self.isConcave = isConcave
        self.startCornerIndex = -1
        self.endCornerIndex = -1
        self.startBoundarySegmentIndex = -1
        self.startBoundaryIsEnd = false
        self.endBoundarySegmentIndex = -1
        self.endBoundaryIsEnd = false
        self.startEdgeProgress = -1
        self.endEdgeProgress = -1
    }
    
    /// New initializer for corner-based curves
    init(startCornerIndex: Int, endCornerIndex: Int, radius: Double, isConcave: Bool, edge: EdgePosition) {
        self.id = UUID()
        self.startCornerIndex = startCornerIndex
        self.endCornerIndex = endCornerIndex
        self.startBoundarySegmentIndex = -1
        self.startBoundaryIsEnd = false
        self.endBoundarySegmentIndex = -1
        self.endBoundaryIsEnd = false
        self.startEdgeProgress = -1
        self.endEdgeProgress = -1
        self.radius = radius
        self.isConcave = isConcave
        self.edgeRaw = edge.rawValue
    }

    var edge: EdgePosition {
        get { EdgePosition(rawValue: edgeRaw) ?? .top }
        set { edgeRaw = newValue.rawValue }
    }
    
    /// Returns true if this curve uses the legacy corner-based selection
    var usesCornerIndices: Bool {
        startCornerIndex >= 0 && endCornerIndex >= 0
    }

    /// Returns true if this curve uses stable boundary endpoints
    var usesBoundaryEndpoints: Bool {
        startBoundarySegmentIndex >= 0 && endBoundarySegmentIndex >= 0
    }

    /// Returns true if this curve uses stable edge progress values
    var usesEdgeProgress: Bool {
        startEdgeProgress >= 0 && endEdgeProgress >= 0
    }
    
    /// Returns true if this curve has a valid span
    var hasSpan: Bool {
        if usesEdgeProgress {
            return startEdgeProgress != endEdgeProgress
        }
        if usesBoundaryEndpoints {
            return startBoundarySegmentIndex != endBoundarySegmentIndex || startBoundaryIsEnd != endBoundaryIsEnd
        }
        return startCornerIndex >= 0 && endCornerIndex >= 0 && startCornerIndex != endCornerIndex
    }
}
