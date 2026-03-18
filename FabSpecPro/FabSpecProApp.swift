//
//  FabSpecProApp.swift
//  FabSpecPro
//
//  Created by Salvatore Militello on 2/15/26.
//

import SwiftUI
import SwiftData

@main
struct FabSpecProApp: App {
    var sharedModelContainer: ModelContainer = {
        // Use the versioned schema from the migration plan
        let schema = Schema(versionedSchema: FabSpecProSchemaV14.self)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: FabSpecProMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            // If the store is incompatible or corrupted, delete and recreate.
            let storeURL = modelConfiguration.url
            if FileManager.default.fileExists(atPath: storeURL.path) {
                try? FileManager.default.removeItem(at: storeURL)
            }
            do {
                return try ModelContainer(
                    for: schema,
                    migrationPlan: FabSpecProMigrationPlan.self,
                    configurations: [modelConfiguration]
                )
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()

    @State private var showLaunchScreen = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .preferredColorScheme(.dark)
                
                if showLaunchScreen {
                    LaunchScreenView(isActive: $showLaunchScreen)
                        .zIndex(1)
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
