# Portfolio Reliability Design

Status: implemented on `codex/portfolio-reliability` following user authorization on 2026-10-14. Original scope choices and constraints are retained. See the implementation plan execution record for verification and adjustments.

## Purpose and confirmed choices

Implement the Ponytail full audit recommendations in the existing personal macOS portfolio app. Protect saved positions, correct financial results, and make operations reliable with the smallest complete changes.

The user confirmed on 2026-10-14:

- Export/Import remains **current positions only, clearly labeled**. It is not a complete backup.
- Daily ETF price history stores the **latest quote for that day**.
- Do not implement application code during planning.

## Constraints

- Keep SwiftUI, Core Data, Swift 5.0, and macOS 15.0.
- Add no dependencies; preserve the existing visual design.
- Preserve the current annual coupon schedule and approximate yield-to-maturity formula. Correct inconsistencies without introducing a new pricing engine.
- Preserve nominal-based historical bond invested-capital entries. Realized gain is redemption minus acquisition cost.
- Preserve existing history during positions import. Do not replay acquisition or sale history for imported positions.
- An imported empty positions list intentionally replaces that category with no positions; show replacement confirmation before mutation.
- Preserve the existing signing-team, scheme-version, Xcode user-state changes, `.DS_Store`, and `graphify-out/`.
- No automatic repair of old history, no database reset, no live endpoint calls in tests.
- No commits or pushes unless separately authorized. Proposed commit boundaries are documented for execution.

## Required behavior

### Saved data

Decode and validate both transfer files before applying changes. Retain an immutable decoded payload while replacement confirmation is open, then apply precisely that payload without rereading the files. A missing file, invalid row, duplicate identifier, or failed persistence operation must leave stored positions unchanged. Use a fresh Core Data context per write operation; failure discards only that operation's changes. Never roll back the shared view context to handle an operation failure. All write callers and price refresh use the app-selected container; no write path falls back to the production singleton.

Bond acquisition, ETF acquisition, FIFO sale, bond edits, and cash-flow recalculation each save once. Historical recorders and cash-flow generators stage objects without saving. UI callers dismiss or show success only after persistence succeeds, and show actionable errors otherwise. Main-context views receive background saves.

### Financial results

Signed losses reduce expected returns. At bond maturity, realized gain/loss equals redemption minus purchase cost. ETF sales record the user-entered execution price and date, with FIFO lots and realized gain saved together. Purchases require positive finite prices and positive integral shares; zero coupons remain valid.

### Instrument and price reliability

Normalize ISINs by trimming whitespace and uppercasing. Match against normalized stored values too, including legacy lowercase/padded identifiers without rewriting them. Bind fetched headers to the requested normalized ISIN; changing an ISIN or purchase mode invalidates obsolete results. An existing ETF never receives an unrelated instrument's quote. Reuse an existing matching ETF rather than create another identity for the same ISIN; report multiple normalized matches rather than silently merge legacy duplicates.

Allow one refresh operation at a time across launch/manual callers. Recheck each requested normalized ISIN against the resolved ETF inside the final write transaction; skip and report a quote if an intervening import changed the identity or deleted the ETF. Keep a single daily price record with the latest successfully fetched quote. Preserve the last good quote on failure and display failed instrument identifiers. Reject non-finite or non-positive quotes.

### Launch processing

Use persisted interest cash flows for eligible coupons, bounded by acquisition, maturity, and `(lastLaunchDate, now]`. Record maturity with the same interval convention. Save all due records in one transaction; advance the checkpoint only afterward. Establish launch save ownership in the same task that removes recorder saves, so no intermediate task loses launch history. Persist a stable event key on generated history so replay after a crash cannot duplicate committed events. Existing historical records remain unchanged. First-run scanning remains the existing seven-day window; this change does not recover older missing history.

### Positions transfer

Keep the legacy `bonds.json` and `etfs.json` layout readable. History is neither exported nor imported, and existing destination history remains unchanged. Label the controls and validation as positions transfer, state that existing positions are replaced, and state that history is excluded. Retain cash-flow and ETF-price data already included in the positions format.

Collect both export payloads on the context's queue. Publish a uniquely named transfer directory containing both files only after both writes succeed; a failed export leaves previously published transfer directories intact. Compare every exported field and nested collection, accepting array ordering differences and the documented ISO-8601 whole-second date precision. Reject duplicate IDs with a validation error instead of trapping in a dictionary constructor.

### Verification

Repair the disabled/stale test configuration. Hosted tests must use an in-memory application store, isolated defaults, and no startup network work. Add focused regression tests for the affected behavior rather than broad coverage targets. Verify both Debug tests and Release compilation before claiming implementation complete.

## Deferred scope

Complete backup/restore, historical reconstruction, currency conversion, fractional shares, exact bond pricing, broad UI redesign, dormant-code cleanup, and dependency removal are excluded. Old incorrect realized records require a separate, reviewable repair proposal; do not rewrite them during these fixes.

## Acceptance

The implementation plan must map every required behavior to a task, give concrete tests and failure expectations, and retain these scope choices. Execution requires user review and selection of an execution method.
