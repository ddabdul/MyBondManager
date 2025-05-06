//
//  YTMTimeSeriesView.swift
//  MyBondManager
//
//  Created by Olivier on 06/05/2025.
//


//
//  YTMTimeSeriesView.swift
//  MyBondManager
//
//  Created 05/15/2025.
//  Shows how the portfolio’s weighted average YTM evolves over time.
//

import SwiftUI
import CoreData
import Charts      // macOS 14+

@available(macOS 14.0, *)
struct YTMTimeSeriesView: View {
    @Binding var selectedDepotBank: String
    @Environment(\.managedObjectContext) private var moc

    /// Only bonds maturing today or later
    private static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    // fetch all still‐active bonds
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \BondEntity.acquisitionDate, ascending: true)
        ],
        predicate: NSPredicate(format: "maturityDate >= %@", Self.startOfToday as NSDate),
        animation: .default
    )
    private var bondEntities: FetchedResults<BondEntity>

    /// apply the same depot‐bank filter
    private var filteredBonds: [BondEntity] {
        guard selectedDepotBank != "All"
        else { return Array(bondEntities) }
        return bondEntities.filter { $0.depotBank == selectedDepotBank }
    }

    /// one data‐point per acquisition‐month, at month‐end
    struct YTMPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let ytm: Double
    }

    private var ytmTimeSeries: [YTMPoint] {
        let cal = Calendar.current

        // 1) all unique acquisition‐month starts
        let monthStarts = Set(filteredBonds.map {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.acquisitionDate))!
        })

        return monthStarts
            .sorted()
            .map { monthStart in
                // compute month‐end
                let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1),
                                        to: monthStart)!
                // keep all bonds acquired on or before monthEnd
                let holdings = filteredBonds.filter { $0.acquisitionDate <= monthEnd }
                let totalPar = holdings.reduce(0) { $0 + $1.parValue }
                let weighted = holdings.reduce(0) {
                    $0 + ($1.yieldToMaturity * $1.parValue)
                }
                let avgYTM = totalPar > 0 ? weighted / totalPar : 0
                return YTMPoint(date: monthEnd, ytm: avgYTM)
            }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Avg. YTM Over Time")
                .font(.headline)
                .padding(.bottom, 4)

            Chart {
                ForEach(ytmTimeSeries) { pt in
                    LineMark(
                        x: .value("Month", pt.date),
                        y: .value("Avg YTM", pt.ytm)
                    )
                    PointMark(
                        x: .value("Month", pt.date),
                        y: .value("Avg YTM", pt.ytm)
                    )
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 240)
            .padding()
            .background(AppTheme.tileBackground)
            .cornerRadius(8)
        }
        .padding()
    }
}

@available(macOS 14.0, *)
struct YTMTimeSeriesView_Previews: PreviewProvider {
    static var previews: some View {
        // supply a constant "All" for the bank filter
        YTMTimeSeriesView(selectedDepotBank: .constant("All"))
            .environment(\.managedObjectContext,
                         PersistenceController.shared.container.viewContext)
    }
}
