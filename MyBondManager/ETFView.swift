//
//  ETFView.swift
//  MyBondManager
//
//  Created by Olivier on 30/04/2025.
//


import SwiftUI

// ──────────────────────────────────────────
// 1) Master tab for ETFs
// ──────────────────────────────────────────
struct ETFView: View {
    var body: some View {
        VStack {
            Text("👋 Hello, ETF View!")
                .font(.largeTitle)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ETFView_Previews: PreviewProvider {
    static var previews: some View {
        ETFView()
            .frame(width: 300, height: 200)
    }
}


// ──────────────────────────────────────────
// 2) Detail pane for ETFs
// ──────────────────────────────────────────
struct ETFDetailView: View {
    var body: some View {
        VStack {
            Text("🔍 ETF Detail View")
                .font(.title)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ETFDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ETFDetailView()
            .frame(width: 300, height: 200)
    }
}
