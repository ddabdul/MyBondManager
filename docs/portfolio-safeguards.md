# Portfolio safeguards

QuantLib remains parked. The app supports reviewed regular EUR fixed-rate annual, semiannual and quarterly schedules, plus zero-coupon redemption. Yield remains an explicitly labeled Estimated YTM, using actual redemption rather than an exact pricing/yield solver.

## First review and subsequent refreshes

The additive V3 migration retains positions, existing cash-flow rows and financial history. Existing bonds initially need review: their invested capital remains visible, while unverified payments are omitted from forecasts and automatic recording. No ING collection runs during schema migration or normal launch.

Open **Review Terms**, select unresolved holdings, and choose **Collect missing terms**. Each selected ISIN is fetched once per collection batch; separate purchases retain their own trade values, draft, approval and readiness. Successful drafts survive another ISIN's failure and resume after reopening. Collect missing terms skips saved drafts; **Refresh selected from ING** explicitly requests another collection. Confirmed overrides and known unsupported restrictions are retained.

Inspect current versus proposed coupon/maturity, the acquisition-day interpretation, terms and dated payments. Correct fields as needed, choose **Save draft and preview**, then **Apply Selected Terms**. Missing values remain missing. An incomplete holding can remain Needs review; no annual frequency or callable status is invented. A changed holding or a preview spanning midnight requires a fresh preview. Applying a selected batch uses one isolated transaction; a failed member or save rolls back the batch and retains the drafts.

New entry can save a holding as Needs review once its required purchase/coupon/maturity values are supplied, or save reviewed supported terms with approval. Ordinary trade edits with no protected history invalidate approval and retain terms as an unapproved draft. Instrument changes with related history remain blocked.

## Supported terms and conventions

Readiness requires validated EUR terms, a supported structure, finite financial values, positive redemption percentage and known callable status. Fixed schedules also require supported frequency, regular accrual boundaries and a consistent next-coupon checkpoint. An aged checkpoint is compared with its original observation day. Ambiguous month-end rolls and irregular periods need review; floating, indexed, perpetual and amortizing structures are outside this phase.

The approved defaults are Actual/Actual (ICMA), TARGET and Following, each marked assumed until confirmed. These are application defaults, not universal terms for every Eurobond. Other conventions can be retained explicitly, but do not produce Ready forecasts in this version. Known unsupported provider restrictions cannot be erased by changing a structure label.

Contractual accrual boundaries remain unadjusted. Coupons for a regular period equal nominal times annual coupon rate divided by frequency; buying within the period does not prorate the next coupon by ownership days. Payment delay adds no interest. Redemption equals nominal times redemption percentage divided by 100. Zero-coupon bonds produce no coupon events, regardless of incidental provider frequency/date fields. Callable bonds use contractual maturity with an **Early redemption is not modeled** warning.

## Forecasts, dates and financial history

Instrument days use explicit calendar dates and Europe/Berlin payment instants. TARGET weekends/holidays move payments forward. Contractual maturity and redemption payment are distinct: an approved holding remains active through its adjusted redemption day, including a delayed final coupon. Cash-flow filters include whole selected market days. Next Coupon and Next Redemption use approved validated payments; missing yield estimates are excluded from the weighted yield.

Unresolved holdings remain visible with their capital and exclusion count. Grouped holdings retain every purchase and indicate mixed readiness. Legacy unverified rows remain stored but are not forecast. Analytical expected-profit and signed-loss rows are not additional cash receipts.

Terms approval/recalculation preserves past-day cash-flow values and every recorded historical row. Trade nominal, cost, acquisition instant and bank are not rewritten by terms approval. Ordinary edits to instrument identity, financial values, dates or bank are blocked when related keyed or ambiguous unlinked bond history exists; descriptive corrections remain available.

Economic payment keys use holding UUID, event kind and contractual day. Safe aliases retain exact local legacy keys before projections/import replacement; old rows and keys are not rewritten. Recalculation retains approval and activation. Approval or native import activates automatic recording prospectively at the actual local operation instant: past and earlier-today payments are never claimed as newly received. A failed event save cannot advance the launch checkpoint.

Ambiguous unlinked legacy receipts overlapping a revised payment window require history review rather than automatic attribution or a possible duplicate. Historical reconciliation remains a separate feature; this phase does not repair old records.

## ETF transaction dates and deletion

ETF behavior is unchanged. Enter purchases and sales in chronological local-day order per ISIN. Recorded keyed sale cutoffs survive deletion/import; older unlinked sales conservatively protect all ETFs. Same-day transactions are allowed. Daily ETF history stores the latest successful quote for that local day, and sale history uses entered execution price/date.

Bond deletion is isolated and atomic, cascades projected rows and preserves history. A failed save leaves persisted data intact. Current-position transfers are not history backups; see [positions-transfer.md](positions-transfer.md).
