import Foundation
import SwiftData

@Model
final class EdgeTreatment {
    var id: UUID
    var name: String
    var abbreviation: String

    init(name: String, abbreviation: String) {
        self.id = UUID()
        self.name = name
        self.abbreviation = abbreviation
    }
}

@Model
final class EdgeAssignment {
    var id: UUID
    var edgeRaw: String
    @Relationship(deleteRule: .nullify) var treatment: EdgeTreatment?
    var treatmentAbbreviation: String
    var treatmentName: String
    var piece: Piece?

    init(edge: EdgePosition, treatment: EdgeTreatment?) {
        self.id = UUID()
        self.edgeRaw = edge.rawValue
        self.treatment = treatment
        self.treatmentAbbreviation = treatment?.abbreviation ?? ""
        self.treatmentName = treatment?.name ?? ""
    }

    var edge: EdgePosition {
        get { EdgePosition(rawValue: edgeRaw) ?? .top }
        set { edgeRaw = newValue.rawValue }
    }
}

extension EdgeAssignment {
    static func cutoutEdgeRaw(cutoutId: UUID, edge: EdgePosition) -> String {
        "cutout:\(cutoutId.uuidString):\(edge.rawValue)"
    }

    static func angleEdgeRaw(angleId: UUID) -> String {
        "angle:\(angleId.uuidString)"
    }

    var cutoutEdge: (id: UUID, edge: EdgePosition)? {
        let parts = edgeRaw.split(separator: ":")
        guard parts.count == 3, parts[0] == "cutout" else { return nil }
        guard let id = UUID(uuidString: String(parts[1])) else { return nil }
        guard let edge = EdgePosition(rawValue: String(parts[2])) else { return nil }
        return (id: id, edge: edge)
    }

    var angleEdgeId: UUID? {
        let parts = edgeRaw.split(separator: ":")
        guard parts.count == 2, parts[0] == "angle" else { return nil }
        return UUID(uuidString: String(parts[1]))
    }
}
