//
//  PortfolioSummaryView.swift
//  BondPortfolioV2
//
//  Created by Olivier on 13/04/2025.
//


import SwiftUI

struct PortfolioSummaryView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel
    
    // Computed properties to calculate the summary values.
    var numberOfBonds: Int {
        viewModel.bonds.count
    }
    
    var totalAcquisitionCost: Double {
        viewModel.bonds.reduce(0) { $0 + $1.initialPrice }
    }
    
    var totalPrincipal: Double {
        viewModel.bonds.reduce(0) { $0 + $1.parValue }
    }
    
    // A helper function to format numbers as currency.
    func formatCurrency(_ value: Double) -> String {
           let formatter = NumberFormatter()
           formatter.numberStyle = .currency
           formatter.maximumFractionDigits = 0  // Do not show any decimal digits.
           formatter.minimumFractionDigits = 0
           return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
       }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Portfolio Summary")
                .font(.title2)
                .bold()
                .padding(.bottom, 5)
            
            Text("Number of Bonds: \(numberOfBonds)")
                .font(.body)
            
            Text("Total Acquisition Cost: \(formatCurrency(totalAcquisitionCost))")
                .font(.body)
            
            Text("Total Principal: \(formatCurrency(totalPrincipal))")
                .font(.body)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
        .padding()
    }
}

