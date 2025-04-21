//  CashFlowView.swift
//  MyBondManager
//
//  Updated by ChatGPT on 22/04/2025.
//

import SwiftUI

/// Displays consolidated future coupon payments, monthly or annually,
/// with drill-down on each period including individual payment dates
struct CashFlowView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel
    @State private var isMonthly: Bool = true
    @State private var selectedPeriod: Date? = nil

    // MARK: - Coupon Event Model
    private struct CouponEvent: Identifiable {
        let id = UUID()
        let bondName: String
        let date: Date
        let amount: Double
    }

    // MARK: - Generate Events
    private var couponEvents: [CouponEvent] {
        let calendar = Calendar.current
        let now = Date()
        return viewModel.bonds.flatMap { bond in
            let couponAmt = bond.parValue * (bond.couponRate / 100)
            let md = bond.maturityDate
            let comps = calendar.dateComponents([.month, .day], from: md)
            var year = calendar.component(.year, from: now)
            var events: [CouponEvent] = []
            var nextComp = DateComponents(year: year, month: comps.month, day: comps.day)
            if let candidate = calendar.date(from: nextComp), candidate < now {
                nextComp.year! += 1
            }
            while let eventDate = calendar.date(from: nextComp), eventDate <= md {
                events.append(CouponEvent(bondName: bond.name, date: eventDate, amount: couponAmt))
                nextComp.year! += 1
            }
            return events
        }
    }

    // MARK: - Grouped Totals
    private var groupedTotals: [(periodStart: Date, label: String, amount: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: couponEvents) { event -> Date in
            let comps = calendar.dateComponents(isMonthly ? [.year, .month] : [.year], from: event.date)
            var normalized = comps
            normalized.day = 1
            if !isMonthly { normalized.month = 1 }
            return calendar.date(from: normalized)!
        }
        return grouped.map { key, events in
            let label: String
            if isMonthly {
                label = Formatters.monthYear.string(from: key)
            } else {
                label = String(calendar.component(.year, from: key))
            }
            let total = events.reduce(0) { $0 + $1.amount }
            return (periodStart: key, label: label, amount: total)
        }
        .sorted { $0.periodStart < $1.periodStart }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Consolidated Coupons")
                    .font(.headline)
                Spacer()
                Picker("Frequency", selection: $isMonthly) {
                    Text("Monthly").tag(true)
                    Text("Annually").tag(false)
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: isMonthly) { _ in selectedPeriod = nil }
                .frame(width: 200)
            }

            // Period Tiles
            if groupedTotals.isEmpty {
                Text("No upcoming coupons")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(groupedTotals, id: \.periodStart) { entry in
                            HStack {
                                Text(entry.label)
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text(Formatters.currency.string(from: NSNumber(value: entry.amount)) ?? "–")
                                    .bold()
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(AppTheme.tileBackground)
                            .cornerRadius(8)
                            .onTapGesture {
                                selectedPeriod = entry.periodStart
                            }
                        }
                    }
                }
            }

            // Detailed List
            if let period = selectedPeriod {
                Divider()
                Text("Details for \(isMonthly ? Formatters.monthYear.string(from: period) : String(Calendar.current.component(.year, from: period)))")
                    .font(.subheadline).bold()
                let periodEvents = couponEvents
                    .filter { event in
                        let comps = Calendar.current.dateComponents(isMonthly ? [.year, .month] : [.year], from: event.date)
                        var normalized = comps
                        normalized.day = 1
                        if !isMonthly { normalized.month = 1 }
                        return Calendar.current.date(from: normalized) == period
                    }
                    .sorted { $0.date < $1.date }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(periodEvents) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.bondName)
                                        .foregroundColor(.white.opacity(0.8))
                                    Text(Formatters.mediumDate.string(from: event.date))
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                Text(Formatters.currency.string(from: NSNumber(value: event.amount)) ?? "–")
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(AppTheme.tileBackground)
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding()
    }
}


