import SwiftUI

struct DrawingMetrics {
    let size: CGSize
    let pieceSize: CGSize
    let scale: CGFloat
    let origin: CGPoint

    init(piece: Piece, in size: CGSize, padding: CGFloat = 72) {
        self.size = size
        self.pieceSize = ShapePathBuilder.displaySize(for: piece)

        let basePadding = max(min(size.width, size.height) * 0.22, padding)
        let adaptivePadding = min(basePadding, 140)

        let usableWidth = max(size.width - adaptivePadding * 2, 10)
        let usableHeight = max(size.height - adaptivePadding * 2, 10)
        let scaleX = usableWidth / pieceSize.width
        let scaleY = usableHeight / pieceSize.height
        self.scale = min(scaleX, scaleY)

        let drawingWidth = pieceSize.width * scale
        let drawingHeight = pieceSize.height * scale
        self.origin = CGPoint(
            x: (size.width - drawingWidth) / 2,
            y: (size.height - drawingHeight) / 2
        )
    }

    func toCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }

    func toPiece(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
}
