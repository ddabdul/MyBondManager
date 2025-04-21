//  PortfolioSummaryView.swift
//  MyBondManager
//
//  Created by Olivier on 13/04/2025.
//

import SwiftUI

// Define a shared gradient (assumes assets or system colors exist)
extension LinearGradient {
    static let tileBackground = LinearGradient(
        gradient: Gradient(colors: [Color("GradientStart"), Color("GradientEnd")]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PortfolioSummaryView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel
    @State private var selectedDepotBank: String = "All"
    
    private var depotBanks: [String] {
        let banks = Set(viewModel.bonds.map { $0.depotBank })
        return ["All"] + banks.sorted()
    }
    
    private var filteredBonds: [Bond] {
        selectedDepotBank == "All" ? viewModel.bonds : viewModel.bonds.filter { $0.depotBank == selectedDepotBank }
    }
    
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
    
    private var nextMaturingBond: Bond? {
        filteredBonds.min { $0.maturityDate < $1.maturityDate }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "–"
    }
    
    private var nextNominal: String {
        guard let bond = nextMaturingBond else { return "–" }
        return formatCurrency(bond.parValue)
    }
    
    private var nextInterestExpected: String {
        guard let bond = nextMaturingBond else { return "–" }
        let years = bond.maturityDate.timeIntervalSince(Date()) / (365 * 24 * 3600)
        let interest = bond.parValue * bond.couponRate * years
        return formatCurrency(interest)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
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
            
            // Four key metrics in grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricView(icon: "doc.plaintext", title: "Bonds", value: "\(numberOfBonds)")
                MetricView(icon: "eurosign.circle", title: "Acquisition", value: formatCurrency(totalAcquisitionCost))
                MetricView(icon: "banknote", title: "Principal", value: formatCurrency(totalPrincipal))
                MetricView(icon: "clock.arrow.circlepath", title: "Maturity (yrs)", value: String(format: "%.1f", averageMaturityYears))
            }
            
            // Next maturity as full-width card
            MetricView(
                icon: "flag.checkered",
                title: "Next Maturity",
                value: "\(nextMaturingBond?.name ?? "–")\nDate: \(nextMaturingBond.map { formatDate($0.maturityDate) } ?? "–")\nNominal: \(nextNominal)\nInterest: \(nextInterestExpected)"
            )
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.primary.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .padding([.horizontal, .top])
    }
}

struct MetricView: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                Text(value)
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
                    .lineLimit(nil)
            }
            Spacer()
        }
        .padding(12)
        .background(
            LinearGradient.tileBackground
        )
        .cornerRadius(8)
    }
}
