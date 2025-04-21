//
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
}

