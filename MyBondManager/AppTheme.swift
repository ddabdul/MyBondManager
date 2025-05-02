//  AppTheme.swift
//  MyBondManager
//
//  Created by Olivier on 20/04/2025.
//

import SwiftUI

// MARK: – App theme colors & gradients
enum AppTheme {
    // Using your Asset Catalog names (or fallback to literal values here)
    static let gradientStart = Color("GradientStart")
    static let gradientEnd   = Color("GradientEnd")
    
    /// A tile / header background gradient
    static let tileBackground = LinearGradient(
        gradient: Gradient(colors: [gradientStart, gradientEnd]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// The same dark-grey you’ve been using under your summary cards.
    /// You can point this at an asset (e.g. “PanelBackground”) or use a literal.
    static let panelBackground = Color("PanelBackground")
    static let panelBackgroundLight = Color(red: 0.95, green: 0.95, blue: 0.95)
    // If you’d rather hard-code it here:
    // static let panelBackground = Color(red: 0.14, green: 0.14, blue: 0.16)
}


