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

/// Schema V10: Adds startCornerIndex and endCornerIndex to CurvedEdge for corner-based curve selection
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

/// Schema V11: Adds stable boundary endpoint fields to CurvedEdge
enum FabSpecProSchemaV11: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 10, 0) }
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

/// Schema V12: Adds edge progress fields to CurvedEdge for stable span tracking
enum FabSpecProSchemaV12: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 11, 0) }
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

/// Schema V13: Adds customAngleDegrees to Cutout for custom angle rotation
enum FabSpecProSchemaV13: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 12, 0) }
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

/// Schema V14: Adds label indices to CurvedEdge for UI alignment
enum FabSpecProSchemaV14: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 13, 0) }
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

/// Schema V15: Removes logoData from BusinessHeader (logo feature removed from
/// Settings) and adds PieceDefaults to the tracked model list. PieceDefaults
/// was present in the production Schema used by FabSpecProApp but was never
/// declared in any earlier VersionedSchema, so V15 brings the migration plan
/// into sync with what the app actually stores.
enum FabSpecProSchemaV15: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 14, 0) }
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
            MaterialOption.self,
            PieceDefaults.self
        ]
    }
}

enum FabSpecProMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FabSpecProSchemaV1.self, FabSpecProSchemaV2.self, FabSpecProSchemaV3.self, FabSpecProSchemaV4.self, FabSpecProSchemaV5.self, FabSpecProSchemaV6.self, FabSpecProSchemaV7.self, FabSpecProSchemaV8.self, FabSpecProSchemaV9.self, FabSpecProSchemaV10.self, FabSpecProSchemaV11.self, FabSpecProSchemaV12.self, FabSpecProSchemaV13.self, FabSpecProSchemaV14.self, FabSpecProSchemaV15.self]
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
            .lightweight(fromVersion: FabSpecProSchemaV9.self, toVersion: FabSpecProSchemaV10.self),
            .lightweight(fromVersion: FabSpecProSchemaV10.self, toVersion: FabSpecProSchemaV11.self),
            .lightweight(fromVersion: FabSpecProSchemaV11.self, toVersion: FabSpecProSchemaV12.self),
            .lightweight(fromVersion: FabSpecProSchemaV12.self, toVersion: FabSpecProSchemaV13.self),
            .lightweight(fromVersion: FabSpecProSchemaV13.self, toVersion: FabSpecProSchemaV14.self),
            .lightweight(fromVersion: FabSpecProSchemaV14.self, toVersion: FabSpecProSchemaV15.self)
        ]
    }
}
