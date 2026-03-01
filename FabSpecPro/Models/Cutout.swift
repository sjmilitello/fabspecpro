import Foundation
import SwiftData

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

    init(kind: CutoutKind, width: Double, height: Double, centerX: Double, centerY: Double, isNotch: Bool = false, isApplied: Bool = true, cornerIndex: Int = -1, cornerAnchorX: Double = -1, cornerAnchorY: Double = -1, createdAt: Date = Date()) {
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

    /// Legacy initializer for edge-based curves (backward compatibility)
    init(edge: EdgePosition, radius: Double, isConcave: Bool) {
        self.id = UUID()
        self.edgeRaw = edge.rawValue
        self.radius = radius
        self.isConcave = isConcave
        self.startCornerIndex = -1
        self.endCornerIndex = -1
    }
    
    /// New initializer for corner-based curves
    init(startCornerIndex: Int, endCornerIndex: Int, radius: Double, isConcave: Bool, edge: EdgePosition) {
        self.id = UUID()
        self.startCornerIndex = startCornerIndex
        self.endCornerIndex = endCornerIndex
        self.radius = radius
        self.isConcave = isConcave
        self.edgeRaw = edge.rawValue
    }

    var edge: EdgePosition {
        get { EdgePosition(rawValue: edgeRaw) ?? .top }
        set { edgeRaw = newValue.rawValue }
    }
    
    /// Returns true if this curve uses the new corner-based selection
    var usesCornerIndices: Bool {
        startCornerIndex >= 0 && endCornerIndex >= 0
    }
    
    /// Returns true if this curve has a valid span (different start and end corners)
    var hasSpan: Bool {
        startCornerIndex >= 0 && endCornerIndex >= 0 && startCornerIndex != endCornerIndex
    }
}
