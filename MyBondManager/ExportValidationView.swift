//
//  ExportValidationView.swift
//  MyBondManager
//  Updated 10/05/2025 – security-scoped access + Close button
//

import SwiftUI
import CoreData

struct ExportValidationView: View {
    let folderURL: URL
    var bondOnly = false
    var excludedSchedules = 0
    @State private var nativeExclusions: Int?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var issues: [String] = []
    @State private var isValid = false
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(isLoading ? "Checking positions..." : (isValid ? "Positions match export" : "Found position discrepancies"))
                .font(.title2)
                .foregroundColor(isValid ? .green : .red)

            if let warning = BondTermsPresentation.exclusions(nativeExclusions ?? excludedSchedules) { Text(warning).foregroundStyle(.orange) }
            Text(bondOnly ? "bonds.json keeps the webapp format. Keep bond-terms.json beside it for Mac-to-Mac reading. Neither file contains financial history."
                 : "Legacy positions transfer. Use Export Bonds to include approved native terms for another Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Text("External webapp rendering has not been checked here.").font(.caption).foregroundStyle(.secondary)
            Divider()

            // Issue list or “no issues”
            if isLoading { ProgressView() }
            else if issues.isEmpty {
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
        .task { await runValidation() }
    }

    @MainActor private func runValidation() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if bondOnly {
                let payload = try await ImportManager().prepareBonds(from: folderURL)
                nativeExclusions = payload.unresolvedCount
                issues = try await viewContext.perform { try PositionsTransferValidation.bondIssues(payload, context: viewContext) }
            } else {
                let payload = try await ImportManager().prepare(from: folderURL)
                issues = try await viewContext.perform {
                    try PositionsTransferValidation.issues(bonds: payload.bonds, etfs: payload.etfs, context: viewContext)
                }
            }
            isValid = issues.isEmpty
        } catch {
            issues = ["Could not validate positions: \(error.localizedDescription)"]
            isValid = false
        }
    }
}
