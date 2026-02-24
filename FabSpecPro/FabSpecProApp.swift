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
        let schema = Schema([
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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
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
                    configurations: [modelConfiguration]
                )
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
