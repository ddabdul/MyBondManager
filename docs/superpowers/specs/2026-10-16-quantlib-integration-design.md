# QuantLib integration design

Status: expanded proposed scope for user review, 2026-10-16. The user explicitly included genuine floating/fixed-to-floating forecasting and requested the Bridge data-source/bootstrap approach. This document authorizes no implementation by itself.

## Outcome

Replace the app's bespoke fixed/zero-coupon financial arithmetic with embedded QuantLib, then build projection curves from market quotes and support genuine EURIBOR floating/fixed-to-floating coupons. Keep BondSchedule.preview as the single application entry point and preserve the review, persistence, event and export contracts. This is an engine replacement, not a source of missing instrument facts.

## Constraints

- No instrument-specific branches, ISIN lookup tables, issuer URLs or bundled instrument records in application code or configuration.
- macOS deployment target 15.0; Swift language mode 5.0; native bridge C++20; universal arm64 and x86_64 local app.
- Pin QuantLib 1.44 and Boost 1.88.0; static linking; no Python, server, Homebrew library, network or package installation required to run the delivered app.
- Stage 1 supports the existing fixed/zero instruments. The completed programme also supports EURIBOR 1M/3M/6M/12M vanilla reset-in-advance floating and fixed-to-floating coupons, explicit Actual/360 floating accrual, TARGET, and phase-specific Following/Modified Following payment conventions. Automatic projection quotes are available only for 3M/6M; other tenors require imported matching quotes.
- Preserve explicit confirmed Fixed overrides and their constant-rate warning as a separate assumption; genuinely Floating selections use required index terms, historical fixings and a bootstrapped projection curve.
- Missing provider facts remain missing. Confirmed instrument terms are saved once per normalized ISIN; each purchase keeps its own trade and schedule.
- Contractual identity dates stay unadjusted; fixed accrual remains contractual, while floating accrual uses its explicitly confirmed adjustment. Payment adjustment alone adds no interest. Keep the original contractual maturity and actual redemption percentage.
- Unknown first-coupon dates and ambiguous rolls must not silently become guessed approvals. Preserve the historical-opening exclusion when neither possible opening payment enters the forecast.
- Preserve legacy bonds.json structure, approval timestamps, event identities and prospective activation; version native sidecar metadata for market snapshots, read version 1, and reject unknown versions. Do not rewrite financial history or auto-approve terms on startup/import.
- No silent fallback to the old financial engine after a native failure. Report errors per ISIN and allow other instruments to complete.
- Retain the existing Estimated YTM formula and label in this release; do not reinterpret purchase cost as a clean or dirty quote.

## Boundary

A small C interface backed by Objective-C++ owns QuantLib objects. It accepts only calendar dates, numerical terms and convention selections; it never receives an ISIN, issuer name, Core Data object, purchase identity or network client. It returns contractual coupon dates, adjusted payment dates, amounts and errors. Swift owns eligibility, entitlement, event keys, cash-flow presentation, persistence and explicit approval.

Use a local, statically linked QuantLib archive built from pinned source for both architectures. Generated headers, archives and source caches live under ignored Vendor/QuantLib; scripts and version locks are committed. Copy the license notices into the app. Expose no QuantLib C++ types to Swift.

QuantLib Schedule and FixedRateLeg own schedule generation and ActualActual(ISMA, schedule) owns ICMA reference-period amounts. TARGET owns payment adjustment. Stage 1 does not use global evaluation dates or fixings. Curve bootstrap requires an explicit evaluation date: protect every native QuantLib entry with the same mutex and use SavedSettings to restore state on every success/error path. Keep historical fixings in request-local data rather than IndexManager. Do not mutate shared calendars. This is cash-flow projection, without callable valuation or a discounting price engine.

## Dates, stubs and readiness

The native API uses integer YYYYMMDD values, not timezone-based instants or serial dates. Validate real dates and finite amounts before construction; limit schedules to 1,200 coupon periods plus redemption. QuantLib's representable range is checked before invoking it; dates before 1901 produce a clear Needs review reason rather than crashing or substituting a date. Payments adjusted past 2199 are rejected. This explicitly tightens the existing calendar helper's 1900 lower boundary and must be documented/tested.

A supplied first coupon must be after accrual start and on the unadjusted maturity-anchored grid. Pass it as a first-date stub when it precedes maturity; first-at-maturity is a single-period schedule. If unknown, construct the backward schedule only to identify the existing possible historical opening dates; do not expose guessed opening payments. For unknown roll, compare relevant day-of-month and end-of-month schedules and reference-period amounts before permitting calculation; a difference requires confirmation, including a reference boundary before accrual start.

Preserve the observation-day checkpoint rule: next contractual coupon is the first contractual coupon on or after checkpointObservedOn, not the first payment after today's clock. Preserve a contractual coupon whose adjusted payment is still pending. Purchase within an accrual period does not prorate the contractual coupon by ownership days.

## Expanded stages and Bridge reference

Complete these stages in order: native fixed/zero engine (main plan Tasks 1-5), market-data sourcing/bootstrap (market-data plan), genuine floating/fixed-to-floating forecasts (floating plan). Stage 1 alone does not complete the user's request.

Reference checkout inspected read-only: /Users/olivierelamine/Developer/bridge-app, branch feature/date-adjustment, HEAD7e288ac7460dd7d1662bc5b573a39d2db84b4d1e. No Bridge source, database, environment secrets or services were changed or run. The older Documents/Git checkout does not exist on this machine.

Use these live source files as implementation evidence, not as runtime dependencies:
- backend/app/services/external_sources_client.py: cf.com public-rates JSON; PreviousDayDate, LengthInMonths and PreviousDay percent values.
- backend/app/services/euribor_curve_source.py: index deposit plus 1/2/3/5/7/10/15/30Y swap pillars; tenor-specific swap feeds.
- backend/app/ql/euribor_bootstrap.py: DepositRateHelper and SwapRateHelper, TARGET, 2-day spot, annual fixed leg30/360 BondBasis, ModifiedFollowing, EURIBOR ACT/360, PiecewiseLogCubicDiscount with Actual365Fixed curve time.
- backend/app/services/bundesbank_client.py and domain/market_data.py: Bundesbank SDMX observations; index-specific daily historical series.
- backend/tests/test_euribor_bootstrap.py and test_euribor_bootstrap_service.py: public recorded quotes and independent expected repricing/forward fixtures.
- docs/adr/0001-bootstrapped-euribor-forward-curves.md: source limitations and the accepted 1Y swap pillar instead of a 12M fixing.

Reuse the bootstrap recipe and quote shapes, not Bridge's FastAPI/Postgres deployment or its intermediate ten-year monthly forward representation. MyBondManager retains raw quotes and uses the native bootstrapped curve directly. Single-curve projection is a documented approximation, not an OIS/multi-curve valuation model. Do not change Bridge conventions to fit another provider's different-date reference.

Provider endpoints are editable source configuration, not instrument rules. Default cf.com feeds are eurlibor.json, euriborswap.json and euribor6monthswap.json beneath https://cf.com/public-api/public-rates. Historical fixings use https://api.statistiken.bundesbank.de/rest/data with the series keys in the market-data plan. Live feed availability was not verified by this planning pass; web-tool access failed, so only repository/fixture behaviour is confirmed.

The latest user request supersedes manual-only projection-curve imports: default to fetching source quotes and bootstrapping locally. Keep dated JSON fixing/quote imports as offline/source-failure fallback. No provider credentials are copied from Bridge. Index/provider conventions in configuration are permitted; instrument/issuer-specific entries remain prohibited. Dated fixing/quote file import was explicitly selected by the user; source-built curves were then explicitly requested using Bridge as reference, so the programme supports both direct refresh and normalized offline input files.

## Market-data and floating policy

Store immutable raw quote/fixing snapshots with hashes, source dates, retrieval time, method version and calibration diagnostics. Reject mismatched fixing/swap quote dates by default rather than silently combining them; preserve the last successful snapshot. This deliberately tightens Bridge's older-of-two-dates warning policy. Treat a curve older than two TARGET business days as stale. Never substitute a 3M curve for1M/6M/12M. Do not extrapolate beyond quoted curve coverage or replace a missing published past fixing with a forward.

Source refresh publishes data only. Explicit Rebuild selected forecasts adopts a snapshot into each approved profile; term approval and event activation are unchanged. Reading/loading does not reprice or write portfolios. Saved old forecasts remain reproducible with their snapshot and visible as-of/stale labels. Market refresh failures do not erase approved terms or old forecasts.

Historical reset dates on or before valuation day require an exact published fixing; today's unpublished fixing is Pending data, never projected as actual. Future resets use QuantLib index.valueDate(fixingDate) and index.maturityDate(valueDate), not a forward beginning on the fixing date. All incoming percent values convert once to decimals. Spreads are stored explicitly in basis points. Do not floor negative rates or negative net coupons implicitly.

Floating coupon terms include index tenor, spread, gearing, reset lag/timing, confirmed reset anchor (contractual or adjusted accrual start), floating coupon frequency, explicitly confirmed Actual/360 day count, accrual adjustment, payment adjustment and month-end rule. Fixed-to-floating terms also require the transition boundary and first floating coupon when irregular. Require the fixed-to-floating transition on the fixed regular grid anchored to final maturity; off-grid transitions remain Needs review with an actionable unsupported-phase-schedule reason. Do not reanchor fixed coupons to the transition. Build the fixed phase and floating phase separately; no overlapping or missing accrual at transition and no duplicate redemption. Missing or unsupported terms remain Needs review.

Compute a complete contractual date schedule for checkpoint validation, but resolve amounts/fixings only inside the purchase entitlement and adjusted-payment calculation window. Recent buyers must not supply irrelevant old fixings. Receipt reconciliation uses original activation as its window start, independently of the advancing global launch watermark, with event-key/legacy-alias idempotency and no pre-activation backfill.

Floating reset dates use the explicitly selected contractual or adjusted accrual-start anchor and move backward by the confirmed TARGET business-day lag; published lookup and projection use the same date. Only floating ACT/360 is supported initially; missing/unconfirmed or other floating day counts are not silently inherited from fixed ICMA conventions.

Each payment carries fixed/known-fixing/projected provenance. Forecast-derived interest must not be posted as received when its payment date passes. Once required published fixings are explicitly adopted, normal prospective/idempotent receipt rules may apply; existing recorded amounts are never rewritten after a fixing correction. Negative, nonzero known interest uses signed history entries; the existing payment.amount >0 gate must be revised for interest only.

Use optional structured fields in existing Codable terms/profiles and an immutable file-based market-data catalogue; no Core Data schema migration is needed. Profiles/drafts embed the frozen input snapshot, avoiding dependence on another machine's catalogue paths. Native sidecar version2 embeds/deduplicates referenced snapshots; version1 remains readable, old readers reject version2. Legacy bonds.json keeps its key set and exports current forecast amounts for the existing webapp; uncertainty/provenance travels only in native metadata and is clearly labelled in the Mac UI.

## Scope excluded from this programme

No automatic missing-instrument enrichment, paid/login-gated feed integration, ECB government-curve-as-OIS substitution, callable/option valuation, rate-in-arrears convexity, capped/floored or averaged/compounded overnight products, arbitrary schedule transitions or exact yield/accrued-price solver. Missing index caps/floors/arrears metadata must not be assumed absent merely to obtain Ready. Unsupported contracts remain reviewable drafts. Fixed Estimated YTM remains estimated; genuine floating forecasts show no fixed-rate Estimated YTM. A future valuation/pricing project needs its own price/settlement conventions and discount curve.

## Acceptance

Use anonymous fixtures and hand-derived answers, not ISIN-dependent expectations: annual/semiannual/quarterly coupons, long first coupon 3777.4725274725274 per 100000 at 6.875%, short/leap/DST periods, day-of-month versus end-of-month, TARGET holiday delays, zero coupon, non-par redemption, confirmed Fixed overrides, historical-opening exclusions, and invalid inputs. Existing regression tests remain acceptance tests; explain numerical differences rather than refreshing expected values from QuantLib output.

Run explicit review/apply, native roundtrip, legacy export and duplicate-event tests with in-memory stores. A copied Release app must run offline without development dependencies. No live portfolio migration or runtime test is implied by passing isolated tests.

## Primary references checked for this plan

- [QuantLib 1.44 release](https://github.com/lballabio/QuantLib/releases/tag/v1.44).
- [QuantLib build options](https://raw.githubusercontent.com/lballabio/QuantLib/v1.44/CMakeLists.txt).
- [Schedule API](https://raw.githubusercontent.com/lballabio/QuantLib/master/ql/time/schedule.hpp), [fixed coupon API](https://raw.githubusercontent.com/lballabio/QuantLib/master/ql/cashflows/fixedratecoupon.hpp), [ActualActual API](https://raw.githubusercontent.com/lballabio/QuantLib/master/ql/time/daycounters/actualactual.hpp). API examples were inspected upstream; compile against the pinned release in Task 1 before relying on them.
- [Boost 1.88.0 release checksum](https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz.json).
