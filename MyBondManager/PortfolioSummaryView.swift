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
        selectedDepotBank == "All" ? viewModel.bonds : viewModel.bonds.filter { $0.depotBank == selectedDepotBank }
    }
    
    // Summary metrics
    private var numberOfBonds: Int { filteredBonds.count }
    private var totalAcquisitionCost: Double { filteredBonds.reduce(0) { $0 + $1.initialPrice } }
    private var totalPrincipal: Double { filteredBonds.reduce(0) { $0 + $1.parValue } }
    private var averageMaturityYears: Double {
        guard !filteredBonds.isEmpty else { return 0 }
        let totalYears = filteredBonds.reduce(0) { sum, bond in
            let interval = bond.maturityDate.timeIntervalSince(Date())
            return sum + (interval / (365 * 24 * 3600))
        }
        return totalYears / Double(filteredBonds.count)
    }
    
    // Formatters
    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "–"
    }
    private func formatYears(_ years: Double) -> String { String(format: "%.1f", years) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Portfolio Summary")
                    .font(.title2)
                    .bold()
                Spacer()
                Picker("Depot Bank", selection: $selectedDepotBank) {
                    ForEach(depotBanks, id: \.self) { bank in
                        Text(bank).tag(bank)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 150)
            }
            .padding(.bottom, 8)
            
            // Metrics grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricView(icon: "doc.plaintext", title: "Bonds", value: "\(numberOfBonds)")
                MetricView(icon: "dollarsign.circle", title: "Acquisition", value: formatCurrency(totalAcquisitionCost))
                MetricView(icon: "banknote", title: "Principal", value: formatCurrency(totalPrincipal))
                MetricView(icon: "clock.arrow.circlepath", title: "Maturity (yrs)", value: formatYears(averageMaturityYears))
            }
        }
        .padding()
        .background(
            // Use SwiftUI material for a modern, adaptive background
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.primary.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .padding([.horizontal, .top])
    }
}

// Reusable card for each metric
struct MetricView: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
                    .bold()
            }
            Spacer()
        }
        .padding(8)
        .background(
            // Material card for each metric
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
    }
}
