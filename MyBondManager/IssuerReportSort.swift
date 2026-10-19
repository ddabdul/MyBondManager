import Foundation

struct IssuerReportSort {
    enum Column {
        case issuer, principal, averageMaturity
        var label: String {
            switch self {
            case .issuer: return "issuer"
            case .principal: return "principal"
            case .averageMaturity: return "average maturity"
            }
        }
    }
    private(set) var column: Column = .principal
    private(set) var ascending = false

    mutating func select(_ next: Column) {
        if column == next { ascending.toggle() }
        else { column = next; ascending = next == .issuer }
    }

    func sorted(_ rows: [PortfolioReportData.Issuer]) -> [PortfolioReportData.Issuer] {
        func namePrecedes(_ lhs: String, _ rhs: String) -> Bool {
            let order = lhs.localizedStandardCompare(rhs)
            return order == .orderedSame ? lhs < rhs : order == .orderedAscending
        }
        return rows.sorted { lhs, rhs in
            if column == .issuer {
                return ascending ? namePrecedes(lhs.name, rhs.name) : namePrecedes(rhs.name, lhs.name)
            }
            let left = column == .principal ? lhs.principal : lhs.averageMaturityYears
            let right = column == .principal ? rhs.principal : rhs.averageMaturityYears
            if left == right { return namePrecedes(lhs.name, rhs.name) }
            return ascending ? left < right : left > right
        }
    }
}
