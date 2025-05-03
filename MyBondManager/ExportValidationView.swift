//
//  ExportValidationView.swift
//  MyBondManager
//
//  Created by Olivier on 06/05/2025.
//

import SwiftUI
import CoreData

struct ExportValidationView: View {
    let folderURL: URL
    @Environment(\.managedObjectContext) private var viewContext

    @State private var issues: [String] = []
    @State private var isValid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isValid ? "✅ JSON matches Core Data" : "❗️ Found discrepancies")
                .font(.title2)
                .foregroundColor(isValid ? .green : .red)

            Divider()

            if issues.isEmpty {
                Text("No issues detected.")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(issues, id: \.self) { issue in
                            Text("• \(issue)")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear(perform: runValidation)
        .frame(minWidth: 500, minHeight: 300)
    }

    private func runValidation() {
        var foundIssues: [String] = []

        // JSON decoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // ——— 1. Validate bonds.json —————————————————————————————————
        let bondsURL = folderURL.appendingPathComponent("bonds.json")
        do {
            let data = try Data(contentsOf: bondsURL)
            let jsonBonds = try decoder.decode([BondCodable].self, from: data)

            // Fetch core data bonds
            let request: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
            let cdBonds = try viewContext.fetch(request)

            // Index by ID
            let jsonById = Dictionary(uniqueKeysWithValues: jsonBonds.map { ($0.id, $0) })
            let cdById   = Dictionary(uniqueKeysWithValues: cdBonds.map { ($0.id, $0) })

            // 1a) Missing / extra
            for cd in cdBonds {
                if jsonById[cd.id] == nil {
                    foundIssues.append("Bond \(cd.name) (\(cd.id)) missing from JSON")
                }
            }
            for jb in jsonBonds {
                if cdById[jb.id] == nil {
                    foundIssues.append("JSON contains unknown bond \(jb.name) (\(jb.id))")
                }
            }

            // 1b) Field mismatches
            for (id, jb) in jsonById {
                guard let cd = cdById[id] else { continue }
                if cd.name != jb.name {
                    foundIssues.append("Bond[\(jb.id)] name: CoreData=\(cd.name) JSON=\(jb.name)")
                }
                if cd.isin != jb.isin {
                    foundIssues.append("Bond[\(jb.id)] isin mismatch")
                }
                if cd.issuer != jb.issuer {
                    foundIssues.append("Bond[\(jb.id)] issuer mismatch")
                }
                if cd.initialPrice != jb.initialPrice {
                    foundIssues.append("Bond[\(jb.id)] initialPrice: CoreData=\(cd.initialPrice) JSON=\(jb.initialPrice)")
                }
                // …repeat for any other key fields you care about…
            }
        }
        catch {
            foundIssues.append("Error validating bonds.json: \(error.localizedDescription)")
        }

        // ——— 2. Validate etfs.json ————————————————————————————————————
        let etfsURL = folderURL.appendingPathComponent("etfs.json")
        do {
            let data = try Data(contentsOf: etfsURL)
            let jsonETFs = try decoder.decode([ETFEntityCodable].self, from: data)

            let request: NSFetchRequest<ETFEntity> = ETFEntity.fetchRequest()
            let cdETFs = try viewContext.fetch(request)

            let jsonById = Dictionary(uniqueKeysWithValues: jsonETFs.map { ($0.id, $0) })
            let cdById   = Dictionary(uniqueKeysWithValues: cdETFs.map { ($0.id, $0) })

            for cd in cdETFs {
                if jsonById[cd.id] == nil {
                    foundIssues.append("ETF \(cd.etfName) (\(cd.id)) missing from JSON")
                }
            }
            for je in jsonETFs {
                if cdById[je.id] == nil {
                    foundIssues.append("JSON contains unknown ETF \(je.etfName) (\(je.id))")
                }
            }

            for (id, je) in jsonById {
                guard let cd = cdById[id] else { continue }
                if cd.etfName != je.etfName {
                    foundIssues.append("ETF[\(id)] name mismatch")
                }
                if cd.isin != je.isin {
                    foundIssues.append("ETF[\(id)] isin mismatch")
                }
                if cd.lastPrice != je.lastPrice {
                    foundIssues.append("ETF[\(id)] lastPrice: Core=\(cd.lastPrice) JSON=\(je.lastPrice)")
                }
                // you could also compare counts of priceHistory/holdings:
                if cd.etfPriceMany.count != je.priceHistory.count {
                    foundIssues.append("ETF[\(id)] priceHistory count mismatch: Core=\(cd.etfPriceMany.count) JSON=\(je.priceHistory.count)")
                }
                if cd.etftoholding.count != je.holdings.count {
                    foundIssues.append("ETF[\(id)] holdings count mismatch: Core=\(cd.etftoholding.count) JSON=\(je.holdings.count)")
                }
            }
        }
        catch {
            foundIssues.append("Error validating etfs.json: \(error.localizedDescription)")
        }

        // Finalize
        DispatchQueue.main.async {
            self.issues = foundIssues
            self.isValid = foundIssues.isEmpty
        }
    }
}
