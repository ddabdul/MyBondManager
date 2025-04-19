//  BondRowView.swift
//  BondPortfolioV2
//
//  Created by Olivier on 11/04/2025.
//

import SwiftUI

// zero‑decimal currency formatter
extension NumberFormatter {
    static let zeroDecimalCurrency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()
}

// date formatter for acquisition & maturity dates
private let bondDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    return f
}()

// MARK: — Header Row

struct BondRowHeaderView: View {
    @Binding var sortOption: BondSortOption

    // light lilac for selected header
    private let selectedColor = Color(red: 200/255, green: 180/255, blue: 220/255)
    // charcoal background
    private let backgroundColor = Color(red: 30/255, green: 30/255, blue: 30/255)

    /// A reusable header button that shows a chevron when selected.
    private func headerButton(
        _ title: String,
        option: BondSortOption,
        alignment: Alignment
    ) -> some View {
        Button {
            sortOption = option
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortOption == option {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            // color text & chevron based on selection
            .foregroundColor(sortOption == option ? selectedColor : .white)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 16) {
            headerButton("Bond Name",    option: .name,             alignment: .leading)
            headerButton("Issuer",       option: .issuer,           alignment: .leading)
            headerButton("Acq. Date",    option: .acquisitionDate,  alignment: .leading)
            headerButton("Acq. Price",   option: .acquisitionPrice, alignment: .trailing)
            headerButton("Nominal",      option: .nominal,          alignment: .trailing)
            headerButton("Coupon",       option: .coupon,           alignment: .trailing)
            headerButton("Mat. Date",    option: .maturityDate,     alignment: .leading)
            headerButton("Depot Bank",   option: .depotBank,        alignment: .leading)

            // YTM is not sortable
            Text("YTM")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundColor(.white)
        }
        .font(.headline)
        .padding(.vertical, 6)
        .background(backgroundColor)
    }
}

// MARK: — Data Row

struct BondRowView: View {
    let bond: Bond

    var body: some View {
        HStack(spacing: 16) {
            // 1) Name
            Text(bond.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 2) Issuer
            Text(bond.issuer)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 3) Acquisition date
            Text(bond.acquisitionDate, formatter: bondDateFormatter)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 4) Acquisition price
            Text(
                NumberFormatter.zeroDecimalCurrency
                    .string(from: NSNumber(value: bond.initialPrice)) ?? "-"
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            // 5) Par value
            Text(
                NumberFormatter.zeroDecimalCurrency
                    .string(from: NSNumber(value: bond.parValue)) ?? "-"
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            // 6) Coupon
            Text(String(format: "%.2f%%", bond.couponRate))
                .frame(maxWidth: .infinity, alignment: .trailing)

            // 7) Maturity date
            Text(bond.maturityDate, formatter: bondDateFormatter)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 8) Depot bank
            Text(bond.depotBank)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 9) YTM at acquisition
            Text(String(format: "%.2f%%", bond.yieldAtAcquisition * 100))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }
}

// MARK: — Preview

struct BondRowView_Previews: PreviewProvider {
    static var previews: some View {
        let sample = Bond(
            id: UUID(),
            name: "US Treasury",
            issuer: "U.S. Government",
            isin: "US1234567890",
            wkn: "A0B1C2",
            parValue: 100_000,
            couponRate: 2.00,
            initialPrice: 98_500,
            maturityDate: Date().addingTimeInterval(60*60*24*365),
            acquisitionDate: Date().addingTimeInterval(-60*60*24*180),
            depotBank: "Consor",
            // ensure you’ve added this property to your model:
      //      yieldAtAcquisition: 0.025
        )

        VStack(spacing: 0) {
            BondRowHeaderView(sortOption: .constant(.name))
            Divider()
            BondRowView(bond: sample)
        }
        .previewLayout(.fixed(width: 950, height: 70))
        .background(Color.black)  // for contrast
    }
}

