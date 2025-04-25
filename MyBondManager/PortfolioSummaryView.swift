// PortfolioSummary
// Using CoreData


import SwiftUI
import CoreData

struct PortfolioSummaryView: View {
    // MARK: – Core Data Fetch
    @Environment(\.managedObjectContext) private var moc
    @FetchRequest(
        // adjust sort descriptors to your preference
        sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.acquisitionDate, ascending: false)],
        animation: .default
    )
    private var bondEntities: FetchedResults<BondEntity>

    // MARK: – UI State
    @State private var selectedDepotBank: String = "All"
    @State private var potentialPrice: String = ""
    @State private var potentialCouponRate: String = ""
    @State private var potentialMaturityDate: Date = Date()
    @State private var calculatedYTM: Double? = nil

    // MARK: – Helpers

    /// Unique depot banks in your store, prefixed with “All”
    private var depotBanks: [String] {
        let banks = Set(bondEntities.map { $0.depotBank })
        return ["All"] + banks.sorted()
    }

    /// Apply the “All” filter
    private var filteredBonds: [BondEntity] {
        guard selectedDepotBank != "All" else { return Array(bondEntities) }
        return bondEntities.filter { $0.depotBank == selectedDepotBank }
    }

    // MARK: – Summary Metrics

    private var numberOfBonds: Int { filteredBonds.count }

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

    // MARK: – Next Maturity

    private var nextMaturingBond: BondEntity? {
        filteredBonds.min { $0.maturityDate < $1.maturityDate }
    }

    // MARK: – Next Coupon Date

    private func nextCouponDate(for bond: BondEntity) -> Date? {
        let calendar = Calendar.current
        let md = bond.maturityDate
        let mdComponents = calendar.dateComponents([.month, .day], from: md)
        var next = calendar.dateComponents([.year], from: Date())
        next.month = mdComponents.month
        next.day   = mdComponents.day

        guard let thisYear = calendar.date(from: next) else { return nil }
        if thisYear < Date() {
            next.year! += 1
        }
        return calendar.date(from: next)
    }

    private var nextCouponDateOverall: Date? {
        filteredBonds
            .compactMap(nextCouponDate(for:))
            .min()
    }

    private var bondsWithNextCoupon: [BondEntity] {
        guard let date = nextCouponDateOverall else { return [] }
        return filteredBonds.filter { nextCouponDate(for: $0) == date }
    }

    private var nextCouponPayer: String {
        switch bondsWithNextCoupon.count {
        case 0:    return "–"
        case 1:    return bondsWithNextCoupon.first!.name
        default:   return "Multiple"
        }
    }

    private var nextCouponTotal: String {
        let total = bondsWithNextCoupon.reduce(0) { sum, bond in
            sum + bond.parValue * (bond.couponRate / 100)
        }
        return Formatters.currency.string(from: NSNumber(value: total)) ?? "–"
    }

    private var nextCouponInfo: String {
        guard let date = nextCouponDateOverall else { return "–" }
        return """
        Payer: \(nextCouponPayer)
        Date:  \(Formatters.mediumDate.string(from: date))
        Total: \(nextCouponTotal)
        """
    }

    // MARK: – YTM Estimate

    private func calculateYTM() {
        let parValue = 100.0
        guard let price = Double(potentialPrice),
              let couponRate = Double(potentialCouponRate) else {
            calculatedYTM = nil
            return
        }
        let coupon = parValue * couponRate / 100.0
        let interval = potentialMaturityDate.timeIntervalSince(Date())
        let years = interval / (365 * 24 * 3600)
        guard years > 0 else {
            calculatedYTM = nil
            return
        }
        let numerator   = coupon + (parValue - price) / years
        let denominator = (parValue + price) / 2
        calculatedYTM = (numerator / denominator) * 100.0
    }

    // MARK: – View Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header + Filter
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
                    MetricView(icon: "doc.plaintext",     title: "Bonds",        value: "\(numberOfBonds)")
                    MetricView(icon: "dollarsign.circle", title: "Acquisition",  value: Formatters.currency.string(from: NSNumber(value: totalAcquisitionCost)) ?? "–")
                    MetricView(icon: "banknote",          title: "Principal",    value: Formatters.currency.string(from: NSNumber(value: totalPrincipal)) ?? "–")
                    MetricView(icon: "clock.arrow.circlepath", title: "Maturity (yrs)", value: String(format: "%.1f", averageMaturityYears))
                }

                // Next Maturity Tile
                MetricView(
                    icon:  "flag.checkered",
                    title: "Next Maturity",
                    value: nextMaturingBond.map {
                        "\($0.name)\nDate: \(Formatters.mediumDate.string(from: $0.maturityDate))\nNominal: \(Formatters.currency.string(from: NSNumber(value: $0.parValue)) ?? "–")"
                    } ?? "–"
                )
                .frame(maxWidth: .infinity)

                // Next Coupon Tile
                MetricView(
                    icon:  "calendar.badge.clock",
                    title: "Next Coupon",
                    value: nextCouponInfo
                )
                .frame(maxWidth: .infinity)

                // YTM Estimate Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Estimate Bond YTM")
                        .font(.headline)

                    HStack(spacing: 12) {
                        TextField("Price", text: $potentialPrice)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Coupon Rate (%)", text: $potentialCouponRate)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    DatePicker("Maturity Date", selection: $potentialMaturityDate, displayedComponents: .date)
                        .datePickerStyle(.compact)

                    Button("Calculate YTM", action: calculateYTM)
                        .buttonStyle(.borderedProminent)

                    if let ytm = calculatedYTM {
                        Text("Yield to Maturity: \(String(format: "%.2f", ytm))%")
                            .font(.subheadline).bold()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.primary.opacity(0.1), radius: 4, x: 0, y: 2)
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom)
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
