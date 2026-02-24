import Foundation
import SwiftData

@Model
final class CornerRadius {
    var id: UUID
    var cornerIndex: Int
    var radius: Double
    var isInside: Bool
    var piece: Piece?

    init(cornerIndex: Int = 0, radius: Double = 1, isInside: Bool = false) {
        self.id = UUID()
        self.cornerIndex = cornerIndex
        self.radius = radius
        self.isInside = isInside
    }
}
