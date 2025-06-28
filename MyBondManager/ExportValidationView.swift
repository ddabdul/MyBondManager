//  ExportValidationView.swift
//  MyBondManager
//  Updated 10/05/2025 – security-scoped access + Close button
//

import SwiftUI
import CoreData

struct ExportValidationView: View {
    let folderURL: URL
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var issues: [String] = []
    @State private var isValid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(isValid ? "✅ JSON matches Core Data" : "❗️ Found discrepancies")
                .font(.title2)
                .foregroundColor(isValid ? .green : .red)

            Divider()

            // Issue list or “no issues”
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

            Spacer()

            // Close button
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
        .onAppear(perform: runValidation)
    }

    private func runValidation() {
        print("🔍 Validation started for folder:", folderURL.path)
        var foundIssues: [String] = []

        // Gain read permission for everything under folderURL
        let granted = folderURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // ——— 1. bonds.json ——————————————————————————————
        let bondsURL = folderURL.appendingPathComponent("bonds.json")
        do {
            let data = try Data(contentsOf: bondsURL)
            let jsonBonds = try decoder.decode([BondCodable].self, from: data)
            let cdBonds = try viewContext.fetch(BondEntity.fetchRequest())

            let jsonById = Dictionary(uniqueKeysWithValues: jsonBonds.map { ($0.id, $0) })
            let cdById   = Dictionary(uniqueKeysWithValues: cdBonds.map { ($0.id, $0) })

            for cd in cdBonds where jsonById[cd.id] == nil {
                foundIssues.append("Bond missing from JSON: \(cd.name) (\(cd.id))")
            }
            for jb in jsonBonds where cdById[jb.id] == nil {
                foundIssues.append("Unknown bond in JSON: \(jb.name) (\(jb.id))")
            }
            for (id, jb) in jsonById {
                guard let cd = cdById[id] else { continue }
                if cd.name != jb.name {
                    foundIssues.append("Name mismatch \(id): Core=\(cd.name) JSON=\(jb.name)")
                }
                // …add more field checks here…
            }
        }
        catch {
            foundIssues.append("❌ Error validating bonds.json: \(error.localizedDescription)")
        }

        // ——— 2. etfs.json —————————————————————————————————
        let etfsURL = folderURL.appendingPathComponent("etfs.json")
        do {
            let data = try Data(contentsOf: etfsURL)
            let jsonETFs = try decoder.decode([ETFEntityCodable].self, from: data)
            let cdETFs = try viewContext.fetch(ETFEntity.fetchRequest())

            let jsonById = Dictionary(uniqueKeysWithValues: jsonETFs.map { ($0.id, $0) })
            let cdById   = Dictionary(uniqueKeysWithValues: cdETFs.map { ($0.id, $0) })

            for cd in cdETFs where jsonById[cd.id] == nil {
                foundIssues.append("ETF missing from JSON: \(cd.etfName) (\(cd.id))")
            }
            for je in jsonETFs where cdById[je.id] == nil {
                foundIssues.append("Unknown ETF in JSON: \(je.etfName) (\(je.id))")
            }
            for (id, je) in jsonById {
                guard let cd = cdById[id] else { continue }
                if cd.etfName != je.etfName {
                    foundIssues.append("ETF name mismatch \(id): Core=\(cd.etfName) JSON=\(je.etfName)")
                }
                // …and so on…
            }
        }
        catch {
            foundIssues.append("❌ Error validating etfs.json: \(error.localizedDescription)")
        }

        // ——— 3. capital_transactions.json ———————————————————
        let txnsURL = folderURL.appendingPathComponent("capital_transactions.json")
        do {
            let data = try Data(contentsOf: txnsURL)
            let jsonTxns = try decoder.decode([CapitalTransactionCodable].self, from: data)
            let cdTxns   = try viewContext.fetch(CapitalTransaction.fetchRequest())

            let jsonById = Dictionary(uniqueKeysWithValues: jsonTxns.map { ($0.id, $0) })
            let cdById   = Dictionary(uniqueKeysWithValues: cdTxns.map {
                ($0.objectID.uriRepresentation().absoluteString, $0)
            })

            // prepare calendar for second-granularity comparisons
            let calendar = Calendar(identifier: .gregorian)

            // – missing in JSON?
            for cd in cdTxns where jsonById[cd.objectID.uriRepresentation().absoluteString] == nil {
                foundIssues.append("CapitalTransaction missing from JSON: id=\(cd.objectID.uriRepresentation().absoluteString)")
            }

            // – unknown in Core Data?
            for jt in jsonTxns where cdById[jt.id] == nil {
                foundIssues.append("Unknown CapitalTransaction in JSON: id=\(jt.id)")
            }

            // – field-by-field checks
            for (id, jt) in jsonById {
                guard let cd = cdById[id] else { continue }

                // compare only to the second to avoid sub-second mismatches
                if !calendar.isDate(cd.date, equalTo: jt.date, toGranularity: .second) {
                    foundIssues.append("Date mismatch for txn \(id): Core=\(cd.date) JSON=\(jt.date)")
                }
                if cd.amount != jt.amount {
                    foundIssues.append("Amount mismatch for txn \(id): Core=\(cd.amount) JSON=\(jt.amount)")
                }
                if cd.type != jt.type {
                    foundIssues.append("Type mismatch for txn \(id): Core=\(cd.type) JSON=\(jt.type)")
                }
                if let bond = cd.bond, jt.bondId != bond.id {
                    foundIssues.append("BondId mismatch for txn \(id): Core=\(bond.id) JSON=\(jt.bondId ?? UUID())")
                }
                if let etf = cd.etf, jt.etfId != etf.id {
                    foundIssues.append("EtfId mismatch for txn \(id): Core=\(etf.id) JSON=\(jt.etfId ?? UUID())")
                }
            }
        }
        catch {
            foundIssues.append("❌ Error validating capital_transactions.json: \(error.localizedDescription)")
        }

        // Finalize
        DispatchQueue.main.async {
            self.issues = foundIssues
            self.isValid = foundIssues.isEmpty
            print("🔍 Validation complete – isValid=\(self.isValid), issues=\(foundIssues.count)")
        }
    }
}
