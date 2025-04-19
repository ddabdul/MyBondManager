//  MaturedBondsView.swift
//  BondPortfolioV2
//
//  Created by Olivier on 17/04/2025.
//



import SwiftUI

struct MaturedBondsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var maturedBonds: [Bond] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // 1) A big header, not a nav title
      Text("Matured Bonds")
        .font(.title)
        .bold()
        .padding()

      Divider()

      // 2) Your list of matured bonds
      List(maturedBonds) { bond in
        BondRowView(bond: bond)
      }
      .listStyle(PlainListStyle())

      Divider()

      // 3) A close button at the bottom
      HStack {
        Spacer()
        Button("Close") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
      }
      .padding()
    }
    .frame(minWidth: 700, minHeight: 400)
    .onAppear {
      maturedBonds = BondPersistence.shared.loadMaturedBonds()
    }
  }
}
