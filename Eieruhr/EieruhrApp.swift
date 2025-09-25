//
//  EieruhrApp.swift
//  Eieruhr
//
//  Created by Adrian Gier on 25.09.25.
//

import SwiftUI
import CoreData

@main
struct EieruhrApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
