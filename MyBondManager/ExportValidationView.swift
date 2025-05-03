//
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
        print("📂 Loading bonds.json from:", bondsURL.path)
        do {
            let data = try Data(contentsOf: bondsURL)
            print("📦 bonds.json read: \(data.count) bytes")
            let jsonBonds = try decoder.decode([BondCodable].self, from: data)
            print("✅ Decoded \(jsonBonds.count) BondCodable items")

            let cdBonds = try viewContext.fetch(BondEntity.fetchRequest())
            print("💾 Fetched \(cdBonds.count) BondEntity items")

            let jsonById = Dictionary(uniqueKeysWithValues: jsonBonds.map { ($0.id, $0) })
            let cdById   = Dictionary(uniqueKeysWithValues: cdBonds.map { ($0.id, $0) })

            for cd in cdBonds where jsonById[cd.id] == nil {
                let msg = "Bond missing from JSON: \(cd.name) (\(cd.id))"
                print("⚠️", msg)
                foundIssues.append(msg)
            }
            for jb in jsonBonds where cdById[jb.id] == nil {
                let msg = "Unknown bond in JSON: \(jb.name) (\(jb.id))"
                print("⚠️", msg)
                foundIssues.append(msg)
            }
            for (id, jb) in jsonById {
                guard let cd = cdById[id] else { continue }
                if cd.name != jb.name {
                    let msg = "Name mismatch \(id): Core=\(cd.name) JSON=\(jb.name)"
                    print("⚠️", msg)
                    foundIssues.append(msg)
                }
                // …add more field checks here…
            }
        }
        catch {
            let msg = "❌ Error validating bonds.json: \(error.localizedDescription)"
            print(msg)
            foundIssues.append(msg)
        }

        // ——— 2. etfs.json —————————————————————————————————
        let etfsURL = folderURL.appendingPathComponent("etfs.json")
        print("📂 Loading etfs.json from:", etfsURL.path)
        do {
            let data = try Data(contentsOf: etfsURL)
            print("📦 etfs.json read: \(data.count) bytes")
            let jsonETFs = try decoder.decode([ETFEntityCodable].self, from: data)
            print("✅ Decoded \(jsonETFs.count) ETFEntityCodable items")

            let cdETFs = try viewContext.fetch(ETFEntity.fetchRequest())
            print("💾 Fetched \(cdETFs.count) ETFEntity items")

            let jsonById = Dictionary(uniqueKeysWithValues: jsonETFs.map { ($0.id, $0) })
            let cdById   = Dictionary(uniqueKeysWithValues: cdETFs.map { ($0.id, $0) })

            for cd in cdETFs where jsonById[cd.id] == nil {
                let msg = "ETF missing from JSON: \(cd.etfName) (\(cd.id))"
                print("⚠️", msg)
                foundIssues.append(msg)
            }
            for je in jsonETFs where cdById[je.id] == nil {
                let msg = "Unknown ETF in JSON: \(je.etfName) (\(je.id))"
                print("⚠️", msg)
                foundIssues.append(msg)
            }
            for (id, je) in jsonById {
                guard let cd = cdById[id] else { continue }
                if cd.etfName != je.etfName {
                    let msg = "ETF name mismatch \(id): Core=\(cd.etfName) JSON=\(je.etfName)"
                    print("⚠️", msg)
                    foundIssues.append(msg)
                }
                // …and so on…
            }
        }
        catch {
            let msg = "❌ Error validating etfs.json: \(error.localizedDescription)"
            print(msg)
            foundIssues.append(msg)
        }

        // Finalize
        DispatchQueue.main.async {
            self.issues = foundIssues
            self.isValid = foundIssues.isEmpty
            print("🔍 Validation complete – isValid=\(self.isValid), issues=\(foundIssues.count)")
        }
    }
}
