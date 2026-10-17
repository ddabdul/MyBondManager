# Current positions transfer

Both export actions create a new local-time directory such as `positions-2026-10-15_14-30-05`, adding `-2`, `-3`, etc. for collisions. Files are staged together and the directory is published only after every write succeeds. Failed writes preserve previous exports. Save pending portfolio changes before exporting.

## Bonds for the webapp and another Mac

Choose **Export > Export Bonds (webapp + Mac)**. The folder contains exactly:

- `bonds.json`: the existing webapp root array and legacy position/cash-flow schema, including whole-second ISO-8601 dates. No native fields were added.
- `bond-terms.json`: native terms linked by holding UUID and normalized ISIN, including convention provenance, approval or incomplete draft state, acquisition-day interpretation and source projection boundary. Its SHA-256 digest binds it to the exact companion `bonds.json` bytes.

Fixed-only exports retain native version 1. Genuine floating or fixed-to-floating forecasts use version 2 with deduplicated, immutable market snapshots and separate approved/draft valuation context. Import verifies content hashes, calibration, tenor, dates and recomputed payments offline; incomplete drafts remain unapproved. Floating yields use the existing legacy zero sentinel, while the app shows no fixed-bond YTM for them. The legacy JSON key set is unchanged.

Keep both files together for Mac-to-Mac reading. The webapp can continue reading `bonds.json` alone. Approved rows reflect regular frequency, actual redemption and adjusted payment dates. Needs review holdings remain in that file with an empty `cashFlows` array; the Mac reports the count of excluded schedules. The legacy file cannot communicate native readiness or call warnings to the webapp.

**Neither bond file contains financial acquisition/coupon/redemption/sale history, historical event keys, local deduplication aliases or a launch checkpoint. This is a current-position transfer, not a complete backup.** Projected cash-flow rows are not proof that a payment was received.

Calendar instrument dates in native JSON are `YYYY-MM-DD`; legacy dates remain ISO-8601 instants. Payment dates are materialized in Europe/Berlin. Schema compatibility is tested, but the external webapp is outside this repository: its actual rendering of time zones, nonannual coupons and adjusted payments still needs a representative consumer check.

## Import bonds

Choose **Import > Import Bonds** and select the containing folder. Files are read and validated once before confirmation. Confirmation shows incoming and removed counts, replacement scope, native/legacy status and unresolved count. Confirming applies that same frozen payload; subsequent file changes do not change it. If destination holding identities changed since the prompt, replacement must be reviewed again.

- Both files valid: replace the bond category atomically. Supported approved terms can be reused without another ING collection; incomplete/unsupported drafts stay Needs review.
- Only `bonds.json`: accept the old format without requiring `etfs.json`; imported bonds need review. Existing same-UUID approval is cleared rather than silently reused.
- Sidecar present but malformed, unsupported version, wrong digest, duplicate/missing/extra identity, inconsistent financial values or mismatched approved schedule/yield: reject the complete import. There is no silent fallback to legacy mode.
- Empty bond array: intentionally remove all bond positions after the explicit replacement confirmation.

Bond-only import never changes ETFs, holdings or ETF prices. Destination financial history stays unchanged even when its position is removed. Native import establishes a new local prospective activation boundary and retains the destination launch checkpoint. It does not replay source history or earlier-today payments. Safe destination aliases for the same economic holding are retained; they are never read from the sidecar. Native trade/identity conflicts with local keyed history are rejected. Ambiguous overlapping unlinked receipts require history review.

A failed database save rolls back bonds, terms and projections together. Native validation compares both representations, nested flow multisets and provenance without relying on array order or Core Data object IDs.

## Existing all-positions workflow

**Export All Positions / Import All Positions** remain available and keep the original pair `bonds.json` plus `etfs.json`. Both are required by that import mode, which replaces both categories after confirmation; empty arrays clear their category. It remains a legacy positions transfer and does not restore approved native bond terms. Use the bond-only two-file export for those terms.

Existing financial history remains unchanged. Local event aliases may be retained for safe same-identity deduplication, but approval is not retained for replaced legacy bonds. ETF holdings, quote history and their transfer schema keep their existing behavior. Export validation compares all serialized position fields and nested values, normalizing dates to legacy ISO-8601 second precision; duplicate nested rows remain significant.
