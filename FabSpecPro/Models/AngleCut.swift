import Foundation
import SwiftData

@Model
final class AngleCut {
    var id: UUID
    var anchorCornerIndex: Int
    var anchorOffset: Double
    var secondaryCornerIndex: Int
    var secondaryOffset: Double
    var usesSecondPoint: Bool
    var angleDegrees: Double
    var createdAt: Date = Date()
    var piece: Piece?

    init(anchorCornerIndex: Int = 0,
         anchorOffset: Double = 2,
         secondaryCornerIndex: Int = 0,
         secondaryOffset: Double = 2,
         usesSecondPoint: Bool = true,
         angleDegrees: Double = 45,
         createdAt: Date = Date()) {
        self.id = UUID()
        self.anchorCornerIndex = anchorCornerIndex
        self.anchorOffset = anchorOffset
        self.secondaryCornerIndex = secondaryCornerIndex
        self.secondaryOffset = secondaryOffset
        self.usesSecondPoint = usesSecondPoint
        self.angleDegrees = angleDegrees
        self.createdAt = createdAt
    }
}
