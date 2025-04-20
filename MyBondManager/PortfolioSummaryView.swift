//
//  PortfolioSummaryView.swift
//  MyBondManager
//
//  Created by Olivier on 13/04/2025.
//


import SwiftUI

struct PortfolioSummaryView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel
    
    // Selected depot bank filter
    @State private var selectedDepotBank: String = "All"
    
    // Computed list of unique depot banks, with "All" at the front
    private var depotBanks: [String] {
        let banks = Set(viewModel.bonds.map { $0.depotBank })
        return ["All"] + banks.sorted()
    }
    
    // Filtered bonds according to selected depot bank
    private var filteredBonds: [Bond] {
        if selectedDepotBank == "All" {
            return viewModel.bonds
        } else {
            return viewModel.bonds.filter { $0.depotBank == selectedDepotBank }
        }
    }
    
    // Computed properties to calculate the summary values based on filtered bonds.
    private var numberOfBonds: Int {
        filteredBonds.count
    }
    
    private var totalAcquisitionCost: Double {
        filteredBonds.reduce(0) { $0 + $1.initialPrice }
    }
    
    private var totalPrincipal: Double {
        filteredBonds.reduce(0) { $0 + $1.parValue }
    }
    
    private var averageMaturityYears: Double {
        guard !filteredBonds.isEmpty else { return 0 }
        let totalYears = filteredBonds.reduce(0) { sum, bond in
            let interval = bond.maturityDate.timeIntervalSince(Date())
            return sum + (interval / (365 * 24 * 3600))
        }
        return totalYears / Double(filteredBonds.count)
    }
    
    // A helper function to format numbers as currency.
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0  // Do not show any decimal digits.
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    // A helper to format the average maturity in years
    private func formatYears(_ years: Double) -> String {
        String(format: "%.1f", years)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Portfolio Summary")
                .font(.title2)
                .bold()
                .padding(.bottom, 5)
            
            // Depot Bank picker
            Picker("Depot Bank", selection: $selectedDepotBank) {
                ForEach(depotBanks, id: \.self) { bank in
                    Text(bank).tag(bank)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding(.vertical, 5)
            
            Text("Number of Bonds: \(numberOfBonds)")
                .font(.body)
            
            Text("Total Acquisition Cost: \(formatCurrency(totalAcquisitionCost))")
                .font(.body)
            
            Text("Total Principal: \(formatCurrency(totalPrincipal))")
                .font(.body)
            
            Text("Average Maturity: \(formatYears(averageMaturityYears)) years")
                .font(.body)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
        .padding()
    }
}
