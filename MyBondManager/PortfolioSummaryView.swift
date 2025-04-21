//  PortfolioSummaryView.swift
//  MyBondManager
//
//  Created by Olivier on 13/04/2025.
//

import SwiftUI

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
    
    // Compute next coupon date for a given bond (anniversary of maturity date)
    private func nextCoupon(for bond: Bond) -> Date? {
        let calendar = Calendar.current
        let maturity = bond.maturityDate
        // Extract month and day from maturityDate
        let month = calendar.component(.month, from: maturity)
        let day = calendar.component(.day, from: maturity)
        // Construct this year's coupon date
        var components = calendar.dateComponents([.year], from: Date())
        components.month = month
        components.day = day
        guard let thisYearDate = calendar.date(from: components) else { return nil }
        // If that date has passed, schedule next year
        if thisYearDate < Date() {
            components.year! += 1
        }
        return calendar.date(from: components)
    }
    
    // Next maturing bond
    private var nextMaturingBond: Bond? {
        filteredBonds.min { $0.maturityDate < $1.maturityDate }
    }
    
    // Next coupon across all bonds
    private var nextCouponDate: Date? {
        filteredBonds.compactMap { nextCoupon(for: $0) }.min()
    }
    private var nextCouponBonds: [Bond] {
        guard let date = nextCouponDate else { return [] }
        return filteredBonds.filter { nextCoupon(for: $0) == date }
    }
    
    // Formatters
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
    
    // Coupon total for next payment (couponRate is percent)
    private var nextCouponTotal: String {
        let totalAmount = nextCouponBonds.reduce(0) { sum, bond in
            // couponRate is in percent, so divide by 100
            sum + (bond.parValue * (bond.couponRate / 100))
        }
        return formatCurrency(totalAmount)
    }
    private var nextCouponInfo: String {
        guard let date = nextCouponDate else { return "–" }
        return "Date: \(formatDate(date))\nTotal: \(nextCouponTotal)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with bank filter
            HStack {
                Text("Portfolio Summary")
                    .font(.title2)
                    .bold()
                Spacer()
                Picker("Depot Bank", selection: $selectedDepotBank) {
                    ForEach(depotBanks, id: \.self) { bank in Text(bank).tag(bank) }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 150)
            }
            .padding(.bottom, 8)
            
            // Core metrics grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricView(icon: "doc.plaintext", title: "Bonds", value: "\(numberOfBonds)")
                MetricView(icon: "dollarsign.circle", title: "Acquisition", value: formatCurrency(totalAcquisitionCost))
                MetricView(icon: "banknote", title: "Principal", value: formatCurrency(totalPrincipal))
                MetricView(icon: "clock.arrow.circlepath", title: "Maturity (yrs)", value: String(format: "%.1f", averageMaturityYears))
            }
            
            // Next maturity (full width)
            MetricView(
                icon: "flag.checkered",
                title: "Next Maturity",
                value: nextMaturingBond.map { bond in
                    "\(bond.name)\nDate: \(formatDate(bond.maturityDate))\nNominal: \(formatCurrency(bond.parValue))"
                } ?? "–"
            )
            .frame(maxWidth: .infinity)
            
            // Next coupon (full width)
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

// Reusable metric card
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
            AppTheme.tileBackground
        )
        .cornerRadius(8)
    }
}
