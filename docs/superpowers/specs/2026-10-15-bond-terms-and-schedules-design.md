# EUR bond terms and regular payment schedules

Status: design approved in chat; the user authorized the writing-plans stage on 2026-10-15 after receiving this specification. No application implementation is authorized by this document alone.

## Purpose

Improve the existing local macOS app's forecasts for the user's EUR EMTN/Eurobond portfolio. Retain the instrument terms ING already supplies, apply explicit market-convention defaults, and generate regular contractual payments consistently across the portfolio, cash-flow screen, next-payment summary, and future automatic event recording.

QuantLib remains parked. This phase retains an explicitly labeled Estimated YTM rather than adding an exact yield solver or pricing engine. Existing financial history must not be reconstructed or silently corrected.

## Confirmed product decisions

1. Collect additional terms and use them in the existing calculator in this phase.
2. Support regular fixed-rate annual, semiannual, and quarterly schedules and zero-coupon bonds.
3. Callable fixed-rate bonds remain eligible for contractual-maturity forecasts, with a visible warning that early redemption is not modeled.
4. Refresh existing holdings once, review changes and resulting payments, then apply approved terms to current/future projections. Preserve already recorded history.
5. Incomplete or unsupported instruments remain visible, with invested capital retained, but unverified payments are excluded from forecasts and automatic recording. Display the exclusions clearly.
6. The initial review can be completed over multiple sessions. Normal launches use saved approved terms. Subsequent term refreshes are manual and require review before changes are applied.
7. Use the default conventions below, recording whether each is assumed or confirmed and permitting per-bond overrides.
8. Preserve the exact legacy `bonds.json` schema for the external webapp. Supply enriched Mac-to-Mac data in a separate `bond-terms.json` file in the same export folder.
9. Bond transfers do not require `etfs.json`. Existing ETF transfer behavior remains available and unchanged.

## Scope and architecture

Extend existing bond records with optional instrument-term fields rather than introducing shared instrument entities and remapping purchases. Each purchase keeps its terms; refresh requests are deduplicated by normalized ISIN. Different purchases retain separate review/application state and immutable trade details.

Keep collection, terms validation/schedule calculation, persistence, and presentation separate. Use a single schedule calculation for the preview and saved projections. Continue using the app-selected Core Data container and fresh operation contexts, with one save and operation-local rollback. No new external dependencies.

An additive versioned Core Data migration preserves original positions, cash flows, and historical rows. Existing bonds initially have no approved enriched terms and become Needs review. Do not delete old projected rows during the schema migration; eligibility controls their display and recording until approval.

## Stored terms and provenance

Retain these ING fields when supplied:

| Term | ING source | Treatment |
| --- | --- | --- |
| Coupon rate | `InterestRate` | Full precision; never round for storage |
| Maturity | `maturityDate` | Contractual maturity, distinct from payment date |
| Coupon frequency | `InterestPaymentPeriod` | Map explicit known values; missing/unknown is not annual |
| Interest structure | `Interest`, `isZeroBond` | Fixed, zero, or unsupported/unknown |
| Accrual start | `interestStartDate` | Distinct from issue date and acquisition date |
| Issue date | `issueDate` | Retain separately; do not substitute for accrual start |
| Next scheduled coupon | `interestPaymentDate` | Consistency check, not a complete schedule |
| Redemption percentage | `redemptionPayment` | Require a valid finite positive value for readiness |
| Currency | `currencyIsoCode` | EUR only for this calculator |
| Callable status | `isBondCallableBeforeMaturity` | Retain yes/no/unknown; unknown must not become false |

Also retain selected conventions, their assumed/confirmed provenance, collection and approval timestamps, and a local activation boundary for automatic recording. Calculate readiness from validated terms; do not trust an imported Ready flag on its own.

Dates describing the instrument are calendar dates, not instants. Preserve ING's year/month/day rather than shifting them through its UTC offset. Native terms JSON uses `YYYY-MM-DD`; the legacy JSON keeps its existing ISO-8601 representation. Use a consistent EUR market calendar/time zone (Europe/Berlin) when materializing payment dates. Review discrepancies between ING dates and the dates displayed for legacy holdings; never silently reinterpret a legacy date into another day.

A manually corrected term or convention remains attached to its purchase, with its source/provenance. A manual refresh proposes changes without silently overwriting confirmed overrides. Correction controls are limited to supported terms; changing a floating-rate label alone must not make an instrument a supported fixed-rate bond.

## Default conventions

These are approved application defaults, not a claim that all EUR instruments have identical contractual terms:

| Convention | Default |
| --- | --- |
| Coupon day count | Actual/Actual (ICMA), assumed until confirmed |
| Payment calendar | TARGET, assumed until confirmed |
| Payment adjustment | Following: next TARGET business day |
| Interest during a payment delay | No additional accrual; retain contractual coupon amount |
| Redemption payment | Adjust independently from contractual maturity using the payment rule |

Keep contractual accrual dates unadjusted; moving the payment does not move the accrual boundary. Confirmed terms override defaults. Store alternative conventions explicitly; only conventions implemented and tested by this phase may produce Ready projections. Unsupported overrides require review rather than silently using a different convention.

Use calendar-date rules and independent holiday fixtures, including leap years and Easter-dependent TARGET closures. Do not implement a second general-purpose financial library. Exact accrued-interest calculations, irregular-coupon prorating, and exact yield conventions remain outside scope.

## Regular schedules and projections

- Use frequency, accrual start, maturity and ING's next coupon checkpoint to establish a consistent regular schedule. Reject contradictory inputs; do not invent a frequency or silently smooth irregular periods.
- Generate periods using an anchored calendar rule, avoiding cumulative month-end drift. An ambiguous month-end roll or evidence of a short/long first or final coupon requires confirmation/correction before readiness.
- For regular periods, coupon amount is nominal times annual coupon rate divided by payments per year. Buying within a coupon period does not prorate the next contractual coupon by ownership days. Ex-coupon complications require review rather than assuming entitlement despite contrary terms.
- Zero-coupon bonds have no interest events even if ING supplies a nominal next-interest date or payment frequency. They have a redemption event.
- Redemption amount is nominal times redemption percentage divided by 100. Gains/losses and Estimated YTM must use that amount consistently rather than hard-coding nominal redemption.
- Retain the current legacy cash-flow nature strings and cash decomposition for compatibility. Principal plus positive capital-gain components must sum to actual redemption, and a signed capital loss must not be deducted from that cash amount a second time. Expected-profit analysis must not be counted as an additional cash payment.
- A fixed-rate callable bond can be Ready with a call warning. Floating-rate, inflation-linked, perpetual, amortizing or irregular structures are outside this phase and need review. A known contractual maturity schedule is not a modeled call schedule.
- Recalculate from approved saved terms without another network request or review. An unapproved refresh cannot alter the saved schedule.

Nominal, acquisition cost/date and bank are trade data. Instrument-term refresh must not overwrite them. Financial-history safeguards remain in place; approving supported instrument terms is a controlled forward-projection operation, not a way to bypass ordinary trade-edit restrictions.

## One-time migration and review

Offer a resumable Review bond terms workflow for existing holdings. Fetch once per ISIN, then present existing versus proposed terms and the resulting dated payment amounts for each purchase. Allow selecting which reviewed holdings to apply. Show field-specific failures; do not lose successful drafts when another ISIN fails.

Applying the selected immutable review payload saves validated terms, readiness/provenance and eligible projections atomically. Recheck bond identity and relevant trade inputs in the write context; if the holding changed while review was open, require a new preview rather than apply a stale calculation.

Past days and recorded historical rows remain unchanged. Forecasts from the current day can use the approved schedule. Automatic history recording activates prospectively from the local approval/import boundary; approving or importing terms must not retroactively claim that a past or earlier-today payment was received. No automatic historical reconstruction is introduced.

For holdings left Needs review, preserve the holding and old stored projections but omit those unverified payments from the forecast and from automatic recording. Explain this once in the migration workflow and keep a visible unresolved count/action until completion. Approval is persisted per holding, not in one global flag that could incorrectly approve unresolved or newly imported positions.

## Event identity and adjusted maturity

Adopted payment dates may fall after contractual maturity. Every relevant consumer must use the correct distinction: cash-flow eligibility, active/matured holdings, next coupon, next redemption, portfolio summary, launch alerts and history processing must not discard or record the final payment early merely because contractual maturity was reached.

Identify an economic payment independently of its adjusted payment date and of a regenerated Core Data object ID. Preserve deduplication against existing legacy event keys when an already-recorded coupon/redemption moves dates or is regenerated. Do not rewrite old keys/rows to achieve this; retain/resolve compatibility information before replacing projections. A save failure cannot advance an event checkpoint.

Native transfer restores terms and projections, not historical event records or another Mac's launch checkpoint. Reuse approved valid terms without another ING review, but establish a new local prospective event-activation boundary. Do not replay the source Mac's history or reset the destination's existing historical checkpoint.

## Presentation

Keep the current visual design. Add the collected terms, convention provenance, readiness reason and call warning to bond entry/detail/review surfaces. Holdings continue to contribute invested capital regardless of readiness. Forecasts and Next Coupon include Ready payments only, and show the number of excluded holdings when the total is incomplete.

Keep the current calculation labeled Estimated YTM. Do not claim an exact market yield or use ING's displayed approximate yield as an exact validation benchmark.

Add clearly labeled bond-only export/import actions without removing the existing all-positions transfer. Bond-only import replaces the bond category after a concrete replacement confirmation; an empty bond list intentionally clears that category. Bond-only operations never alter ETFs. Existing all-positions behavior remains available; legacy-only imports do not silently preserve stale enriched terms for replaced bonds.

## Two-file bond transfer

### Webapp contract: bonds.json

Preserve the existing root array, names, types, whole-second ISO-8601 dates and nested structure exactly. Do not add native fields or change the meaning of existing identity/trade fields.

Each bond retains precisely: `id`, `name`, `isin`, `issuer`, `depotBank`, `acquisitionDate`, `maturityDate`, `couponRate`, `parValue`, `initialPrice`, `yieldToMaturity`, `wkn`, and `cashFlows`. Each cash-flow row retains precisely `date`, `amount`, and `nature` with the existing nature values.

The values of projected rows reflect the approved schedule, including adjusted payment dates and nonannual coupons. Do not export stale unverified rows for Needs review bonds: export the holding with an empty `cashFlows` array until its projections are approved. This is the existing schema, not an additional webapp status convention. Clearly report the count of excluded schedules at export time; the external webapp cannot display native warnings from this file alone.

The actual webapp is outside the current repository and has not been inspected. Preserve a legacy-schema fixture and require a representative consumer check before claiming its runtime compatibility; schema compatibility alone is not evidence that the webapp displays nonannual or adjusted payments correctly.

### Native contract: bond-terms.json

Use a versioned envelope containing the enriched entries linked by the existing bond UUID and normalized ISIN. Include terms, convention provenance, approved/needs-review information, and schedule metadata needed for deterministic regeneration. Include one entry for every exported bond, even when unresolved.

Bind the sidecar to the exact companion `bonds.json` bytes using a SHA-256 digest, available in the native platform without an external dependency. This detects a sidecar copied from another export whose bond IDs happen to be unchanged. Readiness is revalidated from supported terms, field consistency and approval state, not accepted from a boolean alone.

A valid Needs review entry may have missing optional terms or a recognized unsupported structure. Preserve that state in native transfers; lack of readiness alone is not a malformed file. Reject invalid encodings, nonsensical financial values, and claims of approved supported terms that conflict with the companion position or schedule.

- Both files present and valid: freeze both decoded payloads for confirmation; import bonds and terms atomically. Valid approved terms are reusable without ING review.
- Only `bonds.json` present: accept the old format; import positions as Needs review. Imported legacy projections must not be mistaken for approved enriched schedules.
- Sidecar present but malformed, unsupported version, wrong digest, duplicate/missing/extra bond identity, or inconsistent terms: reject the complete operation with an actionable error and no changes. Do not silently downgrade to legacy import.
- A bond-only transfer requires neither `etfs.json` nor ETF changes. Both bond representations represent current positions; neither contains financial history.

Capture both representations from one coherent saved snapshot. Use the dated export folder convention already implemented. Stage both files and publish the new directory only when every write succeeds. Validate both representations, including nested legacy cash flows, without depending on array order or Core Data object IDs. Preserve the frozen-payload, failure rollback and previous-export protections already present.

## Verification and completion requirements

Use TDD and retain the existing suite. Tests must exercise real schedule/persistence behavior with deterministic dates and local response fixtures, never the production portfolio or live ING endpoints.

Cover at least:

1. ING annual/semiannual/quarterly mappings, full precision, zero flags, missing fields, malformed dates, non-EUR/unknown/unsupported structures and stale requests.
2. Hand-checked regular coupon amounts/dates, anchored month handling, irregular/contradictory schedules, zero coupons, purchase within a period, and redemption percentages other than 100.
3. TARGET weekends/holidays, year transitions and leap years, unchanged coupon amount after adjustment, and final payment after contractual maturity.
4. Resumable partial review, immutable approval drafts, changed/deleted holdings during review, failed saves, preserved trade data/history and explicit forecast exclusions.
5. Idempotent recording across recalculation, changed payment dates, old event keys, local activation boundaries, failed saves and checkpoint replay.
6. Additive migration retaining original and current-model data, optional missing terms, readiness derivation and existing history safeguards.
7. Exact legacy JSON schema fixture, two-file native round trip, legacy-only import without ETFs, approved-term reuse, invalid/stale sidecar rejection, empty-list replacement and atomic publication.
8. Portfolio/cash-flow/next-payment consumers and active/matured behavior use readiness and adjusted redemption consistently. Existing ETF workflows remain unchanged.

Before completion, run the full Debug suite and a local Release build, obtain an independent review, and inspect a representative in-memory UI preview. Record any missing actual-webapp, broker-statement or interactive checks. Do not claim a live consumer verification that was not performed.

## Exclusions and handoff

No QuantLib integration, general pricing library, exact yield solver, curve-based valuation, call valuation, floating/indexed/amortizing schedules, historical reconciliation, full backup, ETF redesign, or automatic changes to approved terms. Do not add fees/clean-versus-dirty purchase inputs in this phase.

This specification is the next approval artifact. Written-spec approval permits the writing-plans stage; implementation requires the subsequent written plan review and execution-method selection. Preserve local signing, scheme and workspace changes. Do not push this design or application work without a user request.
