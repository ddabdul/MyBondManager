//  PortfolioSummaryView.swift
//  MyBondManager
//
//  Created by Olivier on 13/04/2025.
//

import SwiftUI

struct PortfolioSummaryView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel
    @State private var selectedDepotBank: String = "All"
    
    // Unique depot banks with "All"
    private var depotBanks: [String] {
        let banks = Set(viewModel.bonds.map { $0.depotBank })
        return ["All"] + banks.sorted()
    }
    
    // Filtered bonds
    private var filteredBonds: [Bond] {
        selectedDepotBank == "All" ? viewModel.bonds : viewModel.bonds.filter { $0.depotBank == selectedDepotBank }
    }
    
    // MARK: - Summary Metrics
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
    
    // MARK: - Next Maturity
    private var nextMaturingBond: Bond? {
        filteredBonds.min { $0.maturityDate < $1.maturityDate }
    }
    
    // MARK: - Next Coupon Calculation
    private func nextCouponDate(for bond: Bond) -> Date? {
        let calendar = Calendar.current
        let md = bond.maturityDate
        let components = calendar.dateComponents([.month, .day], from: md)
        var nextYearComponents = calendar.dateComponents([.year], from: Date())
        nextYearComponents.month = components.month
        nextYearComponents.day = components.day
        guard let thisYearDate = calendar.date(from: nextYearComponents) else { return nil }
        if thisYearDate < Date() {
            nextYearComponents.year! += 1
        }
        return calendar.date(from: nextYearComponents)
    }
    
    private var nextCouponDateOverall: Date? {
        filteredBonds.compactMap { nextCouponDate(for: $0) }.min()
    }
    
    private var bondsWithNextCoupon: [Bond] {
        guard let date = nextCouponDateOverall else { return [] }
        return filteredBonds.filter { nextCouponDate(for: $0) == date }
    }
    
    // MARK: - Formatting Helpers
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "–"
    }
    
    // MARK: - Next Coupon Summary
    private var nextCouponPayer: String {
        switch bondsWithNextCoupon.count {
        case 0: return "–"
        case 1: return bondsWithNextCoupon.first!.name
        default: return "Multiple"
        }
    }
    
    private var nextCouponTotal: String {
        let total = bondsWithNextCoupon.reduce(0) { sum, bond in
            sum + bond.parValue * (bond.couponRate / 100)
        }
        return formatCurrency(total)
    }
    
    private var nextCouponInfo: String {
        guard let date = nextCouponDateOverall else { return "–" }
        return """
Payer: \(nextCouponPayer)
Date: \(formatDate(date))
Total: \(nextCouponTotal)
"""
    }
    
    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with filter
            HStack {
                Text("Portfolio Summary")
                    .font(.title2).bold()
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
            
            // Metrics Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricView(icon: "doc.plaintext", title: "Bonds", value: "\(numberOfBonds)")
                MetricView(icon: "dollarsign.circle", title: "Acquisition", value: formatCurrency(totalAcquisitionCost))
                MetricView(icon: "banknote", title: "Principal", value: formatCurrency(totalPrincipal))
                MetricView(icon: "clock.arrow.circlepath", title: "Maturity (yrs)", value: String(format: "%.1f", averageMaturityYears))
            }
            
            // Next Maturity Tile
            MetricView(
                icon: "flag.checkered",
                title: "Next Maturity",
                value: nextMaturingBond.map {
                    "\($0.name)\nDate: \(formatDate($0.maturityDate))\nNominal: \(formatCurrency($0.parValue))"
                } ?? "–"
            )
            .frame(maxWidth: .infinity)
            
            // Next Coupon Tile
            MetricView(
                icon: "calendar.badge.clock",
                title: "Next Coupon",
                value: nextCouponInfo
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
                    .font(.headline).bold()
                    .foregroundColor(.white)
                    .lineLimit(nil)
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.tileBackground)
        .cornerRadius(8)
    }
}
