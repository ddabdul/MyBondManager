import SwiftUI
import Charts

// Native tooltip regions share the chart scale, including years with zero interest.
struct ReportingInterestChart: View {
    let interest: [PortfolioReportData.Interest]
    let target: Double?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                Chart {
                    ForEach(interest) { row in
                        BarMark(x: .value("Year", String(row.year)), y: .value("Expected interest", row.amount))
                            .foregroundStyle(AppTheme.tileBackground)
                            .accessibilityLabel("Expected interest in \(row.year)")
                            .accessibilityValue(CashFlowStyle.money(row.amount, precise: true))
                    }
                    if let target {
                        RuleMark(y: .value("Annual target", target))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4])).foregroundStyle(.white)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { chartGeometry in
                        if let frame = proxy.plotFrame {
                            let plot = chartGeometry[frame]
                            ForEach(interest) { row in
                                if let x = proxy.position(forX: String(row.year)) {
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .frame(width: plot.width / CGFloat(interest.count), height: plot.height)
                                        .help(Text(String(row.year) + "\nExpected interest: " + CashFlowStyle.money(row.amount, precise: true)))
                                        .accessibilityHidden(true)
                                        .position(x: plot.minX + x, y: plot.midY)
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .currency(code: "EUR").notation(.compactName))
                    }
                }
                .chartXAxisLabel("Payment year")
                .frame(width: max(geometry.size.width, CGFloat(interest.count) * 48), height: 260)
                .padding(.top, 10)
            }
        }
    }
}
