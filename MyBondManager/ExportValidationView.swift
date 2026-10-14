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
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(isLoading ? "Checking positions..." : (isValid ? "Positions match export" : "Found position discrepancies"))
                .font(.title2)
                .foregroundColor(isValid ? .green : .red)

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
            let payload = try await ImportManager().prepare(from: folderURL)
            issues = try await viewContext.perform {
                try PositionsTransferValidation.issues(bonds: payload.bonds,
                    etfs: payload.etfs, context: viewContext)
            }
            isValid = issues.isEmpty
        } catch {
            issues = ["Could not validate positions: \(error.localizedDescription)"]
            isValid = false
        }
    }
}
