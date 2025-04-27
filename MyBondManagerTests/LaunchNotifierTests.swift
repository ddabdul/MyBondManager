//
//  LaunchNotifierTests.swift
//  MyBondManager
//
//  Created by Olivier on 27/04/2025.
//  Updated on 27/04/2025.
//

import XCTest
import CoreData
@testable import MyBondManager

class LaunchNotifierTests: XCTestCase {
    var container: NSPersistentContainer!

    override func setUp() {
        super.setUp()
        // Clean slate for UserDefaults
        UserDefaults.standard.removeObject(forKey: "lastLaunchDate")

        // In-memory Core Data stack
        container = NSPersistentContainer(name: "MyBondManager")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStoresSync()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "lastLaunchDate")
        container = nil
        super.tearDown()
    }

    func testMaturityAndCouponAlert() {
        let ctx = container.viewContext

        // 1) Bond that matured yesterday
        let b1 = BondEntity(context: ctx)
        b1.id             = UUID()
        b1.name           = "UnitTestBond"
        b1.issuer         = "UnitTestIssuer"
        b1.depotBank      = "UnitTestBank"
        b1.parValue       = 1234
        b1.couponRate     = 2.5
        b1.maturityDate   = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        b1.acquisitionDate = Date().addingTimeInterval(-1_000_000)
        b1.initialPrice   = 1200
        b1.isin           = "UTTEST01"
        b1.wkn            = "UT01"
        b1.yieldToMaturity = 0.02

        // 2) Bond with a coupon anniversary today
        let b2 = BondEntity(context: ctx)
        b2.id              = UUID()
        b2.name            = "CouponBond"
        b2.issuer          = "CouponIssuer"
        b2.depotBank       = "CouponBank"
        b2.parValue        = 500
        b2.couponRate      = 4.0
        // set maturity month/day to today but next year
        let todayMD = Calendar.current.dateComponents([.month, .day], from: Date())
        var dc = DateComponents()
        dc.year  = Calendar.current.component(.year, from: Date()) + 1
        dc.month = todayMD.month
        dc.day   = todayMD.day
        b2.maturityDate    = Calendar.current.date(from: dc)!
        b2.acquisitionDate = Date().addingTimeInterval(-2_000_000)
        b2.initialPrice    = 480
        b2.isin            = "UTTEST02"
        b2.wkn             = "UT02"
        b2.yieldToMaturity = 0.04

        try! ctx.save()

        // 3) Simulate last launch two days ago
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        UserDefaults.standard.set(twoDaysAgo, forKey: "lastLaunchDate")

        // 4) Run notifier
        let notifier = LaunchNotifier(context: ctx)

        // 5) Verify both events show up
        XCTAssertNotNil(notifier.alertMessage)
        let msg = notifier.alertMessage!
        XCTAssertTrue(msg.contains("UnitTestBond"))
        XCTAssertTrue(msg.contains("CouponBond"))
    }
}

private extension NSPersistentContainer {
    func loadPersistentStoresSync() {
        let sem = DispatchSemaphore(value: 0)
        loadPersistentStores { _, error in
            XCTAssertNil(error)
            sem.signal()
        }
        sem.wait()
    }
}
