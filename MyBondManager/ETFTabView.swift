//
//  ETFTabView.swift
//  MyBondManager
//

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct ETFTabView: View {

    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var notifier: LaunchNotifier

    // MARK: - Passed State
    let geo: GeometryProxy
    @Binding var selectedDepotBank: String

    // MARK: - Actions Passed from Parent
    let exportAction: () -> Void
    let importAction: () -> Void

    // MARK: - Local State
    @State private var showingAddETF = false
    @State private var showingSellETF = false
    @State private var isRefreshingETF = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top Action Bar
      //      HStack {
      //          Button(action: exportAction) {
      //              Label("Export", systemImage: "square.and.arrow.up")
      //          }
      //          Button(action: importAction) {
      //              Label("Import", systemImage: "square.and.arrow.down")
      //          }

       //         Spacer()

       //         Button {
       //             Task {
       //                 isRefreshingETF = true
       //                 let updater = ETFPriceUpdater(context: viewContext)
       //                 do {
       //                     try await updater.refreshAllPrices()
        //                } catch {
        //                    DispatchQueue.main.async {
        //                        notifier.alertMessage = """
        //                        ❗️ Failed refreshing ETF prices:
        //                        \(error.localizedDescription)
        //                        """
         //                   }
         //               }
         //               DispatchQueue.main.async {
         //                   isRefreshingETF = false
         //               }
         //           }
         //       } label: {
         //           if isRefreshingETF {
         //               ProgressView()
         //           } else {
         //               Label("Refresh", systemImage: "arrow.clockwise.circle")
         //           }
         //       }

         //       Button {
         //           showingAddETF = true
         //       } label: {
         //           Label("Add", systemImage: "plus")
         //       }

         //       Button {
         //           showingSellETF = true
         //       } label: {
         //           Label("Sell", systemImage: "minus.circle")
         //       }
         //   }
          //  .padding(.horizontal)

          //  Divider()

            // Main ETF List
            ETFListView()
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
                .background(AppTheme.panelBackground)
        }
        .sheet(isPresented: $showingAddETF) {
            AddHoldingView()
                .frame(minWidth: 500, minHeight: 400)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
        }
        .sheet(isPresented: $showingSellETF) {
            SellETFView()
                .frame(minWidth: 500, minHeight: 400)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
        }
        .alert(
            Text("ETF Refresh Error"),
            isPresented: Binding(
                get: { notifier.alertMessage != nil },
                set: { if !$0 { notifier.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                notifier.alertMessage = nil
            }
        } message: {
            Text(notifier.alertMessage ?? "")
                .frame(minWidth: 300, alignment: .leading)
        }
        .padding()
    }
}

