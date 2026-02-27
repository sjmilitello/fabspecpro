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

enum FabSpecProSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 5, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            AngleCut.self,
            CornerRadius.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 6, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            AngleCut.self,
            CornerRadius.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 7, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            AngleCut.self,
            CornerRadius.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProSchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 8, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            AngleCut.self,
            CornerRadius.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProSchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 9, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self,
            Piece.self,
            EdgeTreatment.self,
            EdgeAssignment.self,
            Cutout.self,
            CurvedEdge.self,
            AngleCut.self,
            CornerRadius.self,
            BusinessHeader.self,
            MaterialOption.self
        ]
    }
}

enum FabSpecProMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FabSpecProSchemaV1.self, FabSpecProSchemaV2.self, FabSpecProSchemaV3.self, FabSpecProSchemaV4.self, FabSpecProSchemaV5.self, FabSpecProSchemaV6.self, FabSpecProSchemaV7.self, FabSpecProSchemaV8.self, FabSpecProSchemaV9.self, FabSpecProSchemaV10.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: FabSpecProSchemaV1.self, toVersion: FabSpecProSchemaV2.self),
            .lightweight(fromVersion: FabSpecProSchemaV2.self, toVersion: FabSpecProSchemaV3.self),
            .lightweight(fromVersion: FabSpecProSchemaV3.self, toVersion: FabSpecProSchemaV4.self),
            .lightweight(fromVersion: FabSpecProSchemaV4.self, toVersion: FabSpecProSchemaV5.self),
            .lightweight(fromVersion: FabSpecProSchemaV5.self, toVersion: FabSpecProSchemaV6.self),
            .lightweight(fromVersion: FabSpecProSchemaV6.self, toVersion: FabSpecProSchemaV7.self),
            .lightweight(fromVersion: FabSpecProSchemaV7.self, toVersion: FabSpecProSchemaV8.self),
            .lightweight(fromVersion: FabSpecProSchemaV8.self, toVersion: FabSpecProSchemaV9.self),
            .lightweight(fromVersion: FabSpecProSchemaV9.self, toVersion: FabSpecProSchemaV10.self)
        ]
    }
}
