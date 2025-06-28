//
//  TransactionsBarChart.swift
//  MyBondManager
//
//  Created by Olivier on 22/06/2025.
//  Updated to use index-based X values and display correct bucket dates on the axis.
//

import SwiftUI
import DGCharts        // the Charts Swift package
import CoreData
import AppKit

/// Granularity choices for grouping & axis formatting
enum ChartGranularity: String, CaseIterable, Identifiable {
    case yearly   = "Yearly"
    case monthly  = "Monthly"
    var id: Self { self }
}

/// Formats raw euro amounts as “123 k€”
private class KEuroValueFormatter: NSObject, ValueFormatter {
    func stringForValue(
        _ value: Double,
        entry: ChartDataEntry,
        dataSetIndex: Int,
        viewPortHandler: ViewPortHandler?
    ) -> String {
        // ← this line prevents “0” from ever being drawn
        guard value != 0 else { return "" }
        // value is in full euros; convert to thousands
        let k = value / 1_000.0
        // show one decimal if <10k, otherwise no decimals
        if abs(k) < 10 {
            return String(format: "%.1f k€", k)
        } else {
            return String(format: "%.0f k€", k)
        }
    }
}

/// A SwiftUI wrapper around Daniel Gindi’s BarChartView,
/// showing separate green (inflow) and red (outflow) bars,
/// with each bar labeled (positive above, negative below) in k.EUR.
@available(macOS 13.0, *)
struct TransactionsBarChart: NSViewRepresentable {
    @FetchRequest(
      sortDescriptors: [NSSortDescriptor(keyPath: \CapitalTransaction.date, ascending: true)],
      animation: .default)
    private var transactions: FetchedResults<CapitalTransaction>

    let granularity: ChartGranularity

    func makeNSView(context: Context) -> BarChartView {
        let chart = BarChartView()
        chart.pinchZoomEnabled       = true
        chart.dragEnabled            = true
        chart.doubleTapToZoomEnabled = false
        chart.legend.enabled         = false

        // X-axis
        let xAxis = chart.xAxis
        xAxis.labelPosition        = .bottom
        xAxis.drawGridLinesEnabled = false
        xAxis.valueFormatter       = context.coordinator
        xAxis.granularityEnabled   = true

        // Y-axis
        chart.leftAxis.enabled  = true
        chart.rightAxis.enabled = false

        chart.delegate = context.coordinator
        return chart
    }

    func updateNSView(_ chart: BarChartView, context: Context) {
        context.coordinator.granularity = granularity
        chart.xAxis.valueFormatter = context.coordinator

        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 1) filter out future txns
        let pastTxns = transactions.filter { cal.startOfDay(for: $0.date) <= today }

        // 2) bucket inflow/outflow by date
        var inflows  = [Date: Double]()
        var outflows = [Date: Double]()

        pastTxns.forEach { txn in
            let bucketDate: Date
            switch granularity {
            case .yearly:
                let y = cal.component(.year, from: txn.date)
                bucketDate = cal.date(from: DateComponents(year: y, month: 1, day: 1))!
            case .monthly:
                let comps = cal.dateComponents([.year, .month], from: txn.date)
                bucketDate = cal.date(from: comps)!
            }

            if txn.amount >= 0 {
                inflows[bucketDate, default: 0] += txn.amount
            } else {
                outflows[bucketDate, default: 0] += txn.amount
            }
        }

        // 3) sort and index buckets
        let allDates = Array(Set(inflows.keys).union(outflows.keys)).sorted()
        context.coordinator.bucketDates = allDates

        let inflowEntries: [BarChartDataEntry] = allDates.enumerated().map { (i, date) in
            BarChartDataEntry(x: Double(i), y: inflows[date] ?? 0)
        }
        let outflowEntries: [BarChartDataEntry] = allDates.enumerated().map { (i, date) in
            BarChartDataEntry(x: Double(i), y: outflows[date] ?? 0)
        }

        // 4) create datasets
        let inflowSet  = BarChartDataSet(entries: inflowEntries,  label: "Inflow")
        let outflowSet = BarChartDataSet(entries: outflowEntries, label: "Outflow")

        inflowSet.colors  = [NSColor.systemGreen]
        outflowSet.colors = [NSColor.systemRed]

        inflowSet.drawValuesEnabled  = true
        outflowSet.drawValuesEnabled = true

        let valueFormatter = KEuroValueFormatter()
        inflowSet.valueFormatter  = valueFormatter
        outflowSet.valueFormatter = valueFormatter

        inflowSet.valueTextColor  = .labelColor
        outflowSet.valueTextColor = .labelColor

        let data = BarChartData(dataSets: [inflowSet, outflowSet])

        // 5) bar width & grouping
        let span = 1.0  // since X is index-based, each bucket is 1 unit apart
        data.barWidth = span * 0.4

        if !allDates.isEmpty {
            let startX = -0.5
            let endX   = Double(allDates.count) - 0.5
            chart.xAxis.axisMinimum = startX
            chart.xAxis.axisMaximum = endX

            data.groupBars(fromX: startX, groupSpace: span*0.2, barSpace: 0)
            chart.xAxis.granularity = span
            chart.xAxis.labelCount = allDates.count
        }

        chart.data = data
        chart.notifyDataSetChanged()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(granularity: granularity)
    }

    class Coordinator: NSObject, ChartViewDelegate, AxisValueFormatter {
        var granularity: ChartGranularity
        var bucketDates: [Date] = []     // stores the real dates for each index

        private let yearFmt  = DateFormatter()
        private let monthFmt = DateFormatter()

        init(granularity: ChartGranularity) {
            self.granularity = granularity
            super.init()
            yearFmt.dateFormat  = "yyyy"
            monthFmt.dateFormat = "MM/yy"
        }

        func stringForValue(_ value: Double, axis: AxisBase?) -> String {
            let idx = Int(round(value))
            guard idx >= 0, idx < bucketDates.count else { return "" }
            let date = bucketDates[idx]
            switch granularity {
            case .yearly:
                return yearFmt.string(from: date)
            case .monthly:
                return monthFmt.string(from: date)
            }
        }
    }
}


@available(macOS 13.0, *)
struct PortfolioChartView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var granularity: ChartGranularity = .yearly

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(6)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Invested Capital Over Time")
                    .font(.title2).bold()
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .background(AppTheme.panelBackground)
            .padding(.bottom, 4)

            Divider()

            // Granularity picker
            Picker("Granularity", selection: $granularity) {
                ForEach(ChartGranularity.allCases) { g in
                    Text(g.rawValue).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Chart
            TransactionsBarChart(granularity: granularity)
                .frame(minWidth: 700, minHeight: 400)
                .padding()
        }
    }
}
