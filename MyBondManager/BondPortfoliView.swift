//
//  BondPortfolioView.swift
//  BondPortfolioV2
//
//  Created by Olivier on 11/04/2025.
//

import SwiftUI

struct BondPortfolioView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel
    @State private var showingAddBondView = false

    var body: some View {
        VStack {
            // Title bar
            HStack {
                Text("My Bond Portfolio")
                    .font(.largeTitle)
                    .padding(.leading)
                Spacer()
            }

            // (Optional) Sort picker
            // Picker("Sort By", selection: $viewModel.sortOption) { … }
            //     .pickerStyle(SegmentedPickerStyle())
            //     .padding([.horizontal])

            // Bond list
            List {
                Section(header: BondRowHeaderView(sortOption: $viewModel.sortOption)) {
                    ForEach(viewModel.bonds) { bond in
                        BondRowView(bond: bond)
                    }
                    .onDelete(perform: viewModel.removeBond)
                }
            }
            .listStyle(PlainListStyle())
        }
        // Present the add‐bond sheet
        .sheet(isPresented: $showingAddBondView) {
            AddBondView(viewModel: viewModel)
        }
        // Standard macOS toolbar “add” button
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddBondView.toggle()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

struct BondPortfolioView_Previews: PreviewProvider {
    static var previews: some View {
        BondPortfolioView(viewModel: BondPortfolioViewModel())
            .frame(width: 800, height: 600)
    }
}
