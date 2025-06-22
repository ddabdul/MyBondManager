//
//  TransactionsBarChart.swift
//  MyBondManager
//
//  Created by Olivier on 22/06/2025.
//  Updated to show totals on each bar (formatted in k.EUR) and remove tooltip.
//

import SwiftUI
import DGCharts        // the Charts Swift package
import CoreData
import AppKit

/// Granularity choices for grouping & axis formatting
enum ChartGranularity: String, CaseIterable, Identifiable {
    case yearly   = "Yearly"
    case monthly  = "Monthly"
//    case weekly   = "Weekly"
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
        let s: String
        if abs(k) < 10 {
            s = String(format: "%.1f k€", k)
        } else {
            s = String(format: "%.0f k€", k)
        }
        return s
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
        let past = transactions.filter { cal.startOfDay(for: $0.date) <= today }

        // 2) bucket inflow/outflow
        var inflows = [Date: Double]()
        var outflows = [Date: Double]()

        past.forEach { txn in
            let bucket: Date
            switch granularity {
            case .yearly:
                let y = cal.component(.year, from: txn.date)
                bucket = cal.date(from: .init(year: y, month: 1, day: 1))!
            case .monthly:
                let comps = cal.dateComponents([.year, .month], from: txn.date)
                bucket = cal.date(from: comps)!
//            case .weekly:
//                bucket = cal.dateInterval(of: .weekOfYear, for: txn.date)!.start
            }
            if txn.amount >= 0 {
                inflows[bucket, default: 0] += txn.amount
            } else {
                outflows[bucket, default: 0] += txn.amount
            }
        }

        // 3) build entries
        let allDates = Array(Set(inflows.keys).union(outflows.keys)).sorted()
        let inflowEntries  = allDates.map { d in
            BarChartDataEntry(x: d.timeIntervalSince1970, y: inflows[d] ?? 0)
        }
        let outflowEntries = allDates.map { d in
            BarChartDataEntry(x: d.timeIntervalSince1970, y: outflows[d] ?? 0)
        }

        // 4) two data sets
        let inflowSet  = BarChartDataSet(entries: inflowEntries,  label: "Inflow")
        let outflowSet = BarChartDataSet(entries: outflowEntries, label: "Outflow")

        inflowSet.colors  = [NSColor.systemGreen]
        outflowSet.colors = [NSColor.systemRed]

        // show values on bars
        inflowSet.drawValuesEnabled  = true
        outflowSet.drawValuesEnabled = true

        // use our k.EUR formatter
        let kiloFmt = KEuroValueFormatter()
        inflowSet.valueFormatter  = kiloFmt
        outflowSet.valueFormatter = kiloFmt

        // position positive above, negative below
        inflowSet.valueTextColor  = .labelColor
        outflowSet.valueTextColor = .labelColor

        let data = BarChartData(dataSets: [inflowSet, outflowSet])

        // 5) bar width & grouping
        let day = 24 * 60 * 60.0
        let span: Double = {
            switch granularity {
            case .yearly:  return 45 * day
            case .monthly: return 30  * day
//            case .weekly:  return 7   * day
            }
        }()
        data.barWidth = span * 0.4

        if let first = allDates.first, let last = allDates.last {
            let startX = first.timeIntervalSince1970 - span*0.5
            let endX   = last.timeIntervalSince1970  + span*0.5
            chart.xAxis.axisMinimum = startX
            chart.xAxis.axisMaximum = endX

            data.groupBars(fromX: startX, groupSpace: span*0.2, barSpace: 0)
        }

        // enforce one-label-per-bucket
        chart.xAxis.granularity = span
        chart.xAxis.labelCount = allDates.count

        chart.data = data
        chart.notifyDataSetChanged()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(granularity: granularity)
    }

    class Coordinator: NSObject, ChartViewDelegate, AxisValueFormatter {
        var granularity: ChartGranularity
        private let yearFmt  = DateFormatter()
        private let monthFmt = DateFormatter()
 //       private let weekFmt  = DateFormatter()

        init(granularity: ChartGranularity) {
            self.granularity = granularity
            super.init()
            yearFmt.dateFormat  = "yyyy"
            monthFmt.dateFormat = "MM/yy"
//            weekFmt.dateFormat  = "dd/MM"
        }

        func stringForValue(_ value: Double, axis: AxisBase?) -> String {
            let date = Date(timeIntervalSince1970: value)
            switch granularity {
            case .yearly:  return yearFmt.string(from: date)
            case .monthly: return monthFmt.string(from: date)
 //           case .weekly:  return weekFmt.string(from: date)
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


