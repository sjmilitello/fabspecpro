import Foundation
import SwiftData

@Model
final class Piece {
    var id: UUID
    var name: String
    var materialName: String
    var thicknessRaw: String
    var shapeRaw: String
    var widthText: String
    var heightText: String
    var quantity: Int
    var notes: String
    var project: Project?
    @Relationship(deleteRule: .cascade) var edgeAssignments: [EdgeAssignment]
    @Relationship(deleteRule: .cascade) var cutouts: [Cutout]
    @Relationship(deleteRule: .cascade) var curvedEdges: [CurvedEdge]
    @Relationship(deleteRule: .cascade) var angleCuts: [AngleCut]
    @Relationship(deleteRule: .cascade) var cornerRadii: [CornerRadius]

    init(name: String = "Piece") {
        self.id = UUID()
        self.name = name
        self.materialName = ""
        self.thicknessRaw = MaterialThickness.threeCentimeter.rawValue
        self.shapeRaw = ShapeKind.rectangle.rawValue
        self.widthText = "24"
        self.heightText = "18"
        self.quantity = 1
        self.notes = ""
        self.edgeAssignments = []
        self.cutouts = []
        self.curvedEdges = []
        self.angleCuts = []
        self.cornerRadii = []
    }

    var thickness: MaterialThickness {
        get { MaterialThickness(rawValue: thicknessRaw) ?? .threeCentimeter }
        set { thicknessRaw = newValue.rawValue }
    }

    var shape: ShapeKind {
        get { ShapeKind(rawValue: shapeRaw) ?? .rectangle }
        set { shapeRaw = newValue.rawValue }
    }
}

extension Piece {
    func treatment(for edge: EdgePosition) -> EdgeTreatment? {
        edgeAssignments.first(where: { $0.edgeRaw == edge.rawValue })?.treatment
    }

    func setTreatment(_ treatment: EdgeTreatment?, for edge: EdgePosition, context: ModelContext) {
        let matchingIndices = edgeAssignments.indices.filter { edgeAssignments[$0].edgeRaw == edge.rawValue }
        if matchingIndices.isEmpty {
            let assignment = EdgeAssignment(edge: edge, treatment: treatment)
            assignment.piece = self
            context.insert(assignment)
            edgeAssignments.append(assignment)
        } else {
            for index in matchingIndices {
                edgeAssignments[index].treatment = treatment
                edgeAssignments[index].treatmentAbbreviation = treatment?.abbreviation ?? ""
                edgeAssignments[index].treatmentName = treatment?.name ?? ""
            }
        }
    }

    func clearTreatment(for edge: EdgePosition) {
        for index in edgeAssignments.indices where edgeAssignments[index].edgeRaw == edge.rawValue {
            edgeAssignments[index].treatment = nil
            edgeAssignments[index].treatmentAbbreviation = ""
            edgeAssignments[index].treatmentName = ""
        }
    }

    func cutoutTreatment(for cutoutId: UUID, edge: EdgePosition) -> EdgeTreatment? {
        let raw = EdgeAssignment.cutoutEdgeRaw(cutoutId: cutoutId, edge: edge)
        return edgeAssignments.first(where: { $0.edgeRaw == raw })?.treatment
    }

    func setCutoutTreatment(_ treatment: EdgeTreatment?, for cutoutId: UUID, edge: EdgePosition, context: ModelContext) {
        let raw = EdgeAssignment.cutoutEdgeRaw(cutoutId: cutoutId, edge: edge)
        if let index = edgeAssignments.firstIndex(where: { $0.edgeRaw == raw }) {
            edgeAssignments[index].treatment = treatment
            edgeAssignments[index].treatmentAbbreviation = treatment?.abbreviation ?? ""
            edgeAssignments[index].treatmentName = treatment?.name ?? ""
        } else {
            let assignment = EdgeAssignment(edge: .top, treatment: treatment)
            assignment.edgeRaw = raw
            assignment.piece = self
            context.insert(assignment)
            edgeAssignments.append(assignment)
        }
    }

    func clearCutoutTreatment(for cutoutId: UUID, edge: EdgePosition) {
        let raw = EdgeAssignment.cutoutEdgeRaw(cutoutId: cutoutId, edge: edge)
        if let index = edgeAssignments.firstIndex(where: { $0.edgeRaw == raw }) {
            edgeAssignments[index].treatment = nil
            edgeAssignments[index].treatmentAbbreviation = ""
            edgeAssignments[index].treatmentName = ""
        }
    }

    func curve(for edge: EdgePosition) -> CurvedEdge? {
        curvedEdges.first(where: { $0.edge == edge })
    }

    func cornerRadius(for cornerIndex: Int) -> CornerRadius? {
        cornerRadii.first(where: { $0.cornerIndex == cornerIndex })
    }

    func angleTreatment(for angleId: UUID) -> EdgeTreatment? {
        let raw = EdgeAssignment.angleEdgeRaw(angleId: angleId)
        return edgeAssignments.first(where: { $0.edgeRaw == raw })?.treatment
    }

    func setAngleTreatment(_ treatment: EdgeTreatment?, for angleId: UUID, context: ModelContext) {
        let raw = EdgeAssignment.angleEdgeRaw(angleId: angleId)
        if let index = edgeAssignments.firstIndex(where: { $0.edgeRaw == raw }) {
            edgeAssignments[index].treatment = treatment
            edgeAssignments[index].treatmentAbbreviation = treatment?.abbreviation ?? ""
            edgeAssignments[index].treatmentName = treatment?.name ?? ""
        } else {
            let assignment = EdgeAssignment(edge: .top, treatment: treatment)
            assignment.edgeRaw = raw
            assignment.piece = self
            context.insert(assignment)
            edgeAssignments.append(assignment)
        }
    }

    func clearAngleTreatment(for angleId: UUID) {
        let raw = EdgeAssignment.angleEdgeRaw(angleId: angleId)
        if let index = edgeAssignments.firstIndex(where: { $0.edgeRaw == raw }) {
            edgeAssignments[index].treatment = nil
            edgeAssignments[index].treatmentAbbreviation = ""
            edgeAssignments[index].treatmentName = ""
        }
    }
}
