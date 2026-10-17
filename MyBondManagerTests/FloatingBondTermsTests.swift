import XCTest
@testable import MyBondManager

final class FloatingBondTermsTests: XCTestCase {
    private func assessment(_ terms: FloatingBondTerms, structure: BondStructure = .floating,
                            transition: String? = nil, start: String? = "2026-01-15",
                            maturity: String? = "2031-01-15") throws -> TermsAssessment {
        terms.assessment(structure: structure, transition: try transition.map(MarketDay.init),
                         accrualStart: try start.map(MarketDay.init), maturity: try maturity.map(MarketDay.init))
    }

    func testInvalidExplicitFirstCouponCannotBecomeAnImplicitRegularSchedule() {
        var terms = FloatingFixtures.plain3M()
        terms.confirmedFields.insert("firstFloatingCoupon")
        XCTAssertFalse(terms.assessment(structure: .floating, transition: nil, accrualStart: nil, maturity: nil).supported)
    }
    func testIncompleteContractRejectsAbsentFacts() throws {
        XCTAssertFalse(try assessment(FloatingBondTerms()).supported)
    }

    func testCompletePlainContractAcceptsNegativeSpreadAndBothResetAnchors() throws {
        for anchor in [FloatingResetAnchor.contractualAccrualStart, .adjustedAccrualStart] {
            var terms = FloatingFixtures.plain3M()
            terms.resetAnchor = anchor
            terms.spreadBps = -15
            XCTAssertTrue(try assessment(terms).supported)
        }
    }

    func testEveryRequiredFieldNeedsAnExplicitValueAndConfirmation() throws {
        let fields: [(String, (inout FloatingBondTerms) -> Void)] = [
            ("indexTenorMonths", { $0.indexTenorMonths = nil }), ("spreadBps", { $0.spreadBps = nil }),
            ("gearing", { $0.gearing = nil }), ("resetLagTARGETDays", { $0.resetLagTARGETDays = nil }),
            ("resetTiming", { $0.resetTiming = nil }), ("resetAnchor", { $0.resetAnchor = nil }),
            ("dayCount", { $0.dayCount = nil }), ("frequency", { $0.frequency = nil }),
            ("accrualAdjustment", { $0.accrualAdjustment = nil }), ("paymentAdjustment", { $0.paymentAdjustment = nil }),
            ("roll", { $0.roll = nil }), ("payoff", { $0.payoff = nil })
        ]
        for (field, remove) in fields {
            var missing = FloatingFixtures.plain3M()
            remove(&missing)
            XCTAssertFalse(try assessment(missing).supported, "Missing \(field) accepted")
            var unconfirmed = FloatingFixtures.plain3M()
            unconfirmed.confirmedFields.remove(field)
            XCTAssertFalse(try assessment(unconfirmed).supported, "Unconfirmed \(field) accepted")
        }
    }

    func testUnsupportedPayoffsTimingAndDayCountsRemainDraftValues() throws {
        for payoff in [FloatingPayoff.cappedOrFloored, .other] {
            var terms = FloatingFixtures.plain3M(); terms.payoff = payoff
            XCTAssertFalse(try assessment(terms).supported)
            XCTAssertEqual(try JSONDecoder().decode(FloatingBondTerms.self, from: JSONEncoder().encode(terms)).payoff, payoff)
        }
        var terms = FloatingFixtures.plain3M(); terms.resetTiming = .inArrears
        XCTAssertFalse(try assessment(terms).supported)
        for dayCount in [FloatingDayCount.actual365Fixed, .actualActualICMA] {
            terms = FloatingFixtures.plain3M(); terms.dayCount = dayCount
            XCTAssertFalse(try assessment(terms).supported)
            XCTAssertEqual(try JSONDecoder().decode(FloatingBondTerms.self, from: JSONEncoder().encode(terms)).dayCount, dayCount)
        }
    }

    func testNumericBoundsRejectInvalidInputsWithoutDiscardingSignedSpreads() throws {
        for tenor in [1, 3, 6, 12] {
            var terms = FloatingFixtures.plain3M(); terms.indexTenorMonths = tenor
            XCTAssertTrue(try assessment(terms).supported)
        }
        for frequency in [1, 2, 4, 12] {
            var terms = FloatingFixtures.plain3M(); terms.frequency = frequency
            XCTAssertTrue(try assessment(terms).supported)
        }
        let invalid: [(inout FloatingBondTerms) -> Void] = [
            { $0.indexTenorMonths = 2 }, { $0.frequency = 3 }, { $0.resetLagTARGETDays = -1 },
            { $0.resetLagTARGETDays = 11 }, { $0.spreadBps = .nan }, { $0.spreadBps = .infinity },
            { $0.gearing = 0 }, { $0.gearing = -1 }, { $0.gearing = .nan }, { $0.gearing = .infinity }
        ]
        for edit in invalid {
            var terms = FloatingFixtures.plain3M(); edit(&terms)
            XCTAssertFalse(try assessment(terms).supported)
        }
        for lag in [0, 10] {
            var terms = FloatingFixtures.plain3M(); terms.resetLagTARGETDays = lag
            XCTAssertTrue(try assessment(terms).supported)
        }
    }

    func testMixedPhaseRequiresTransitionStrictlyInsideKnownContractDates() throws {
        let terms = FloatingFixtures.plain3M()
        XCTAssertTrue(try assessment(terms, structure: .fixedToFloating, transition: "2028-01-15").supported)
        for transition in [nil, "2026-01-15", "2025-01-15", "2031-01-15", "2032-01-15"] {
            XCTAssertFalse(try assessment(terms, structure: .fixedToFloating, transition: transition).supported)
        }
        XCTAssertFalse(try assessment(terms, structure: .fixedToFloating, transition: "2028-01-15", start: nil).supported)
        XCTAssertFalse(try assessment(terms, structure: .fixedToFloating, transition: "2028-01-15", maturity: nil).supported)
    }

    func testOldPartialDraftDecodesWithoutFabricatingFactsOrConfirmations() throws {
        let decoded = try JSONDecoder().decode(FloatingBondTerms.self, from: Data(#"{"indexTenorMonths":3}"#.utf8))
        XCTAssertEqual(decoded.indexTenorMonths, 3)
        XCTAssertNil(decoded.spreadBps)
        XCTAssertNil(decoded.gearing)
        XCTAssertNil(decoded.resetLagTARGETDays)
        XCTAssertNil(decoded.dayCount)
        XCTAssertNil(decoded.resetAnchor)
        XCTAssertNil(decoded.payoff)
        XCTAssertTrue(decoded.confirmedFields.isEmpty)
        XCTAssertFalse(try assessment(decoded).supported)
    }
}

enum FloatingFixtures {
    static func plain3M() -> FloatingBondTerms {
        FloatingBondTerms(indexTenorMonths: 3, spreadBps: 15, gearing: 1, resetLagTARGETDays: 2,
            resetTiming: .inAdvance, resetAnchor: .contractualAccrualStart, dayCount: .actual360, frequency: 4,
            accrualAdjustment: .unadjusted, paymentAdjustment: .following, roll: .dayOfMonth, payoff: .plain,
            confirmedFields: ["indexTenorMonths", "spreadBps", "gearing", "resetLagTARGETDays", "resetTiming",
                              "resetAnchor", "dayCount", "frequency", "accrualAdjustment", "paymentAdjustment", "roll", "payoff"])
    }
}

extension FloatingBondTermsTests {
    private func snapshot() throws -> MarketDataSnapshot {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = MarketDataPayload(formatVersion: 1, method: "euribor-singlecurve-v1", sourceName: "Public fixture",
            quotes: try CurveFixtures.quotes(), historicalFixings: [PublishedFixing(day: try MarketDay("2026-10-08"), rate: 0.02642)])
        return try MarketDataStore(directory: directory).save(payload, retrievedAt: Date(timeIntervalSince1970: 1791504000))
    }
    func testProjectionContextRejectsFutureMarketObservationsAndTampering() throws {
        let market = try snapshot()
        XCTAssertNoThrow(try ProjectionContext(valuationDay: MarketDay("2026-10-08"), marketData: market).validate())
        XCTAssertThrowsError(try ProjectionContext(valuationDay: MarketDay("2026-10-07"), marketData: market).validate())
        let tampered = MarketDataSnapshot(id: "invalid", payload: market.payload, calibration: market.calibration, retrievedAt: market.retrievedAt)
        XCTAssertThrowsError(try ProjectionContext(valuationDay: MarketDay("2026-10-08"), marketData: tampered).validate())
    }
    func testProjectionContextFreezesSnapshotAndValuationThroughCodable() throws {
        let context = ProjectionContext(valuationDay: try MarketDay("2026-10-09"), marketData: try snapshot())
        let decoded = try JSONDecoder().decode(ProjectionContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(decoded, context)
        XCTAssertNoThrow(try decoded.validate())
    }
}
