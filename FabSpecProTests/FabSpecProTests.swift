//
//  FabSpecProTests.swift
//  FabSpecProTests
//
//  Created by Salvatore Militello on 2/15/26.
//

import Foundation
import SwiftData
import Testing
@testable import FabSpecPro

@MainActor
struct FabSpecProTests {

    @Test func migrationPlanLoadsExistingStore() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storeURL = tempDir.appendingPathComponent("migration.store")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let v1Schema = Schema(versionedSchema: FabSpecProSchemaV1.self)
        let v1Configuration = ModelConfiguration(storeURL.path(), schema: v1Schema, isStoredInMemoryOnly: false)
        let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Configuration])
        let v1Context = v1Container.mainContext
        v1Context.insert(Project(name: "Migration Test"))
        try v1Context.save()

        let currentSchema = Schema(versionedSchema: FabSpecProSchemaV1.self)
        let currentConfiguration = ModelConfiguration(storeURL.path(), schema: currentSchema, isStoredInMemoryOnly: false)
        let currentContainer = try ModelContainer(
            for: currentSchema,
            migrationPlan: FabSpecProMigrationPlan.self,
            configurations: [currentConfiguration]
        )
        let projects = try currentContainer.mainContext.fetch(FetchDescriptor<Project>())
        #expect(projects.count == 1)
    }

}
