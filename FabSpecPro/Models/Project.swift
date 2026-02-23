import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var address: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var pieces: [Piece]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.address = ""
        self.notes = ""
        self.createdAt = Date()
        self.updatedAt = Date()
        self.pieces = []
    }
}
