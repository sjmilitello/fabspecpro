import SwiftData

// Schema versions to support migrations between model changes.
enum FabSpecProSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 2, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            AngleCut.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 3, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            AngleCut.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 4, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            AngleCut.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FabSpecProSchemaV1.self, FabSpecProSchemaV2.self, FabSpecProSchemaV3.self, FabSpecProSchemaV4.self, FabSpecProSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: FabSpecProSchemaV1.self, toVersion: FabSpecProSchemaV2.self),
            .lightweight(fromVersion: FabSpecProSchemaV2.self, toVersion: FabSpecProSchemaV3.self),
            .lightweight(fromVersion: FabSpecProSchemaV3.self, toVersion: FabSpecProSchemaV4.self),
            .lightweight(fromVersion: FabSpecProSchemaV4.self, toVersion: FabSpecProSchemaV5.self)
        ]
    }
}
