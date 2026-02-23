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
    var isNotch: Bool
    var piece: Piece?

    init(kind: CutoutKind, width: Double, height: Double, centerX: Double, centerY: Double, isNotch: Bool = false) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.width = width
        self.height = height
        self.centerX = centerX
        self.centerY = centerY
        self.isNotch = isNotch
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

    init(edge: EdgePosition, radius: Double, isConcave: Bool) {
        self.id = UUID()
        self.edgeRaw = edge.rawValue
        self.radius = radius
        self.isConcave = isConcave
    }

    var edge: EdgePosition {
        get { EdgePosition(rawValue: edgeRaw) ?? .top }
        set { edgeRaw = newValue.rawValue }
    }
}
