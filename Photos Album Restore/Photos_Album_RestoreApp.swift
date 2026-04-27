//
//  Photos_Album_RestoreApp.swift
//  Photos Album Restore
//
//  Created by Robert Horrion on 4/27/26.
//

import SwiftUI
import CoreData

@main
struct Photos_Album_RestoreApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
