
//  MyBondManagerApp.swift
//  MyBondManager
//
//  Created by Olivier on 11/04/2025.
//

import SwiftUI

@main
struct BondPortfolioManagerApp: App {
    @State private var newlyMatured: [Bond] = []
    @State private var showMaturedAlert: Bool = false

    init() {
        // 1) Perform the one‑time migration & capture only the bonds that *just* matured
        let justMatured = BondPersistence.shared.migrateAndReturnNewlyMatured()
        if !justMatured.isEmpty {
            _newlyMatured = State(initialValue: justMatured)
            _showMaturedAlert = State(initialValue: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Black background for the whole window
                Color.black
                    .ignoresSafeArea()

                MainTabView()
                    // Force dark mode so system text is white-on-black
                    .preferredColorScheme(.dark)
                    // Make buttons, toggles, etc. use white accent
                    .accentColor(.white)
            }
            // Show alert on any newly matured bonds
            .alert("Bonds Matured!", isPresented: $showMaturedAlert) {
                Button("OK") {
                    newlyMatured.removeAll()
                }
            } message: {
                Text(
                    newlyMatured
                        .map { "\($0.name) matured on \(dateFormatter.string(from: $0.maturityDate))" }
                        .joined(separator: "\n")
                )
                .foregroundColor(.white) // ensure alert text is visible
            }
        }
    }
}

// A shared DateFormatter for the alert message
private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()
