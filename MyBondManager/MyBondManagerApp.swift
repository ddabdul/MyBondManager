//
//  MyBondManagerApp.swift
//  MyBondManager
//
//  Created by Olivier on 19/04/2025.
//

import SwiftUI

@main
struct MyBondManagerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
