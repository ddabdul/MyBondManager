
//  MyBondManagerApp.swift
//  MyBondManager
//  Adjusted to CoreData
//  Created by Olivier on 11/04/2025.
//

import SwiftUI

@main
struct BondPortfolioManagerApp: App {
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
        }
    }
}
