//
//  CashFlowMonthlyView.swift
//  BondPortfolioV2
//
//  Created by Olivier on 13/04/2025.
//





import SwiftUI

// MARK: - Static Formatter Extensions

extension DateFormatter {
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/yy"
        return formatter
    }()
}

extension NumberFormatter {
    static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}

// MARK: - Helper Functions

func generateGlobalMonths(for bonds: [Bond]) -> [Date] {
    let calendar = Calendar.current
    guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) else {
        return []
    }
    
    let latestMaturity = bonds.map { $0.maturityDate }.max() ?? start
    let end = calendar.date(from: calendar.dateComponents([.year, .month], from: latestMaturity)) ?? start
    
    var months: [Date] = []
    var current = start
    while current <= end {
        months.append(current)
        if let next = calendar.date(byAdding: .month, value: 1, to: current) {
            current = next
        } else {
            break
        }
    }
    return months
}

func formatMonth(_ date: Date) -> String {
    return DateFormatter.monthFormatter.string(from: date)
}

func formatCurrency(_ value: Double) -> String {    return NumberFormatter.currencyFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

func computeMonthlyCashFlow(for bond: Bond, in month: Date) -> (coupon: Double, principal: Double) {
    let calendar = Calendar.current
    let currentYear = calendar.component(.year, from: month)
    let currentMonth = calendar.component(.month, from: month)
    
    let couponMonth = calendar.component(.month, from: bond.maturityDate)
    let maturityYear = calendar.component(.year, from: bond.maturityDate)
    
    if currentYear > maturityYear {
        return (0, 0)
    }
    if currentMonth == couponMonth && currentYear <= maturityYear {
        let couponPayment = bond.parValue * (bond.couponRate / 100)
        let principalPayment = (currentYear == maturityYear) ? bond.parValue : 0
        return (couponPayment, principalPayment)
    }
    return (0, 0)
}

func computeYearlyCashFlow(for bond: Bond, in year: Int) -> (coupon: Double, principal: Double) {
    let calendar = Calendar.current
    let maturityYear = calendar.component(.year, from: bond.maturityDate)
    if year > maturityYear {
        return (0, 0)
    }
    var components = DateComponents()
    components.year = year
    components.month = calendar.component(.month, from: bond.maturityDate)
    if let dummyDate = calendar.date(from: components) {
        return computeMonthlyCashFlow(for: bond, in: dummyDate)
    }
    return (0, 0)
}

/// Corrected tax function:
/// - Coupon tax is -(tax rate) × coupon.
/// - Principal tax is -(tax rate) × (principal - acquisitionPrice) if principal is non-zero; otherwise 0.
/// The total tax is the minimum of 0 and the sum of these two amounts.
func computeTax(for bond: Bond, flow: (coupon: Double, principal: Double)) -> Double {
    // Always compute coupon tax
    let couponTax = -0.25 * flow.coupon
    
    // Only compute principal tax if principal is repaid
    let principalTax: Double
    if flow.principal != 0 {
        principalTax = -0.25 * (flow.principal - bond.initialPrice)
    } else {
        principalTax = 0
    }
    
    let totalTax = couponTax + principalTax
    
    // Ensure the total tax is never positive; if it's above 0, use 0.
    return min(0, totalTax)
}


// MARK: - Display Option Enum

enum CashFlowDisplayOption: String, CaseIterable, Identifiable {
    case both = "Both"
    case interest = "Interest"
    case principal = "Principal"
    
    var id: Self { self }
}

// MARK: - CashFlowMonthlyView

struct CashFlowMonthlyView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel
    
    // Toggle for Monthly vs. Yearly view.
    @State private var showMonthly: Bool = true
    // Option for which cash flow components to display.
    @State private var displayOption: CashFlowDisplayOption = .both
    
    var body: some View {
        let months = generateGlobalMonths(for: viewModel.bonds)
        let years = Array(Set(months.map { Calendar.current.component(.year, from: $0) })).sorted()
        
        VStack {
            // Combined segmented controls.
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("View Mode", selection: $showMonthly) {
                        Text("Monthly").tag(true)
                        Text("Yearly").tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Display", selection: $displayOption) {
                        ForEach(CashFlowDisplayOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .padding([.leading, .trailing, .top])
            
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 2) {
                    // Header row.
                    HStack {
                        Text("Bond")
                            .frame(width: 120, alignment: .leading)
                            .font(.headline)
                        
                        if showMonthly {
                            ForEach(months, id: \.self) { month in
                                Text(formatMonth(month))
                                    .frame(minWidth: 80)
                                    .font(.headline)
                            }
                        } else {
                            ForEach(years, id: \.self) { year in
                                Text(String(year))
                                    .frame(minWidth: 80)
                                    .font(.headline)
                            }
                        }
                    }
                    Divider()
                    
                    // Data rows.
                    ForEach(viewModel.bonds) { bond in
                        HStack(alignment: .top) {
                            Text(bond.name)
                                .frame(width: 120, alignment: .leading)
                            
                            if showMonthly {
                                ForEach(months, id: \.self) { month in
                                    let flow = computeMonthlyCashFlow(for: bond, in: month)
                                    cellView(flow: flow)
                                }
                            } else {
                                ForEach(years, id: \.self) { year in
                                    let flow = computeYearlyCashFlow(for: bond, in: year)
                                    cellView(flow: flow)
                                }
                            }
                        }
                        Divider()
                    }
                    
                    // Total pre-taxes row.
                    totalRow(title: "Total pre-taxes", months: months, years: years, taxIncluded: false, isPostTax: false)
                    Divider()
                    
                    // Only when displayOption is .both, show Taxes and Total post-taxes rows.
                    if displayOption == .both {
                        totalRow(title: "Taxes", months: months, years: years, taxIncluded: true, isPostTax: false)
                        Divider()
                        
                        totalRow(title: "Total post-taxes", months: months, years: years, taxIncluded: false, isPostTax: true)
                        Divider()
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Cash Flow")
    }
    
    @ViewBuilder
    private func cellView(flow: (coupon: Double, principal: Double)) -> some View {
        VStack {
            switch displayOption {
            case .both:
                let total = flow.coupon + flow.principal
                Text(total != 0 ? formatCurrency(total) : "-")
            case .interest:
                Text(flow.coupon != 0 ? formatCurrency(flow.coupon) : "-")
            case .principal:
                Text(flow.principal != 0 ? formatCurrency(flow.principal) : "-")
            }
        }
        .frame(minWidth: 80)
    }
    
    private func totalRow(title: String, months: [Date], years: [Int], taxIncluded: Bool, isPostTax: Bool) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .frame(width: 120, alignment: .leading)
                .font(.headline)
            
            if showMonthly {
                ForEach(months, id: \.self) { month in
                    let total = calculateTotal(for: month, taxIncluded: taxIncluded, isPostTax: isPostTax)
                    Text(total != 0 ? formatCurrency(total) : "-")
                        .frame(minWidth: 80)
                        .font(.headline)
                }
            } else {
                ForEach(years, id: \.self) { year in
                    let total = calculateTotal(for: year, taxIncluded: taxIncluded, isPostTax: isPostTax)
                    Text(total != 0 ? formatCurrency(total) : "-")
                        .frame(minWidth: 80)
                        .font(.headline)
                }
            }
        }
    }
    
    private func calculateTotal(for period: CustomStringConvertible, taxIncluded: Bool, isPostTax: Bool) -> Double {
        let flowFunction: (Bond, CustomStringConvertible) -> (coupon: Double, principal: Double) = { bond, periodVal in
            if showMonthly {
                return computeMonthlyCashFlow(for: bond, in: periodVal as! Date)
            } else {
                if let year = Int(String(describing: periodVal)) {
                    return computeYearlyCashFlow(for: bond, in: year)
                }
                return (0, 0)
            }
        }
        
        let preTaxTotal = viewModel.bonds.reduce(0.0) { acc, bond in
            let flow = flowFunction(bond, period)
            switch displayOption {
            case .both:
                return acc + (flow.coupon + flow.principal)
            case .interest:
                return acc + flow.coupon
            case .principal:
                return acc + flow.principal
            }
        }
        
        if taxIncluded {
            let taxTotal = viewModel.bonds.reduce(0.0) { acc, bond in
                let flow = flowFunction(bond, period)
                return acc + computeTax(for: bond, flow: flow)
            }
            return taxTotal
        }
        
        if isPostTax {
            let taxTotal = viewModel.bonds.reduce(0.0) { acc, bond in
                let flow = flowFunction(bond, period)
                return acc + computeTax(for: bond, flow: flow)
            }
            return preTaxTotal + taxTotal
        }
        
        return preTaxTotal
    }
}

// MARK: - Preview

struct CashFlowMonthlyView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleViewModel = BondPortfolioViewModel()
        return CashFlowMonthlyView(viewModel: sampleViewModel)
    }
}
