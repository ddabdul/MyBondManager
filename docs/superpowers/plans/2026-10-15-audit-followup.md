# Audit follow-up

User authorized the twelve audit fixes on 2026-10-15. QuantLib is parked.
Keep annual coupons, approximate YTM, positions-only JSON, and existing history.
Work on the existing feature branch; preserve local Xcode settings. Do not commit or push without a new request.

## Implementation and verification

- [x] 1-2, 6: Bind bond collection to a normalized ISIN/request, retain coupon precision, reject empty provider dates. Test collection invalidation, precision and malformed responses.
- [x] 3-4: Protect history-sensitive edits and transaction ordering. Use existing history event keys, no schema migration or history reconstruction. Unknown legacy history gets conservative guards with clear errors.
- [x] 5: Delete through a fresh transaction, report failures, dismiss after success; test rollback and cascade behavior.
- [x] 7-10: Use one tested cash-flow selection/grouping model, day boundaries and observed Core Data rows. Derive Next Coupon from eligible persisted payments. Test same-name banks, today/end-day, maturity, zero coupons and recalculation.
- [x] 11-12: Remove verified dormant code and Algorithms plus its resolved dependency. Preserve unrelated project settings.
- [x] Run full Debug suite and Release build; obtain one independent review, fix substantive findings, update this record and package a local build.

## Decisions

- Financial edits must not silently contradict history. Allow descriptive changes; reject changes to financial/date/bank fields when the bond has keyed history or legacy bond history cannot be attributed safely. No-history fixture/import positions remain editable.
- Persist ETF sale identity in the existing optional history event key. Reject sales and acquisitions dated before a recorded sale for that ISIN; unknown legacy ETF sales impose a conservative cutoff across ETFs. Do not alter old rows. This also survives positions transfers or removal/re-entry of an empty ETF.
- No automatic repair of old history, exact bond-pricing engine, new dependencies, or visual redesign.

## Evidence

- History tests first reproduced rejected-sale/financial-edit failures against the old implementation, then passed with the guards.
- New collection/deletion/presentation API tests were written before implementation and initially failed to compile on missing symbols. The incomplete-provider regression subsequently failed on accepted empty metadata, then passed after validation.
- Final full suite: 62 tests passed, including regeneration replacing already-loaded rows. Log: `/tmp/mybond-followup-full.log`.
- Release build passed without Algorithms (`/tmp/mybond-followup-release.log`). Existing AppIntents metadata warning remains; recompiling the existing relationship-merge test also reports its pre-existing non-Sendable capture warning.
- Independent fresh-context review of the full change: ready, no Critical/Important/Minor issues requiring changes. Ruled outside scope: QuantLib/exact pricing, intraday sequencing, legacy reconstruction and full backup; these remain explicit constraints.
- Local ad hoc signed Release app and ZIP packaged under `builds/MyBondManager-2.0-local-audit-fixes`; signature verified. No live endpoints, manual interactive UI or user portfolio were accessed.
- `git diff --check` passes. User authorized committing and pushing this follow-up after the fresh requested review found no actionable issues. Local signing/team, scheme-version and user-state changes remain excluded from the commit.
