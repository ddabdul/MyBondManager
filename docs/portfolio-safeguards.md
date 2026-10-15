# Portfolio safeguards

QuantLib remains deferred. Bond calculations retain the annual coupon schedule and approximate yield formula.

## Bond entry and changes

Collected bond details belong to the normalized ISIN requested. Changing the ISIN clears them, and late responses cannot restore obsolete details. Coupon rates retain their full precision when stored and used for cash flows.

Financial values, acquisition/maturity dates, and bank cannot be changed when identified history for that bond exists. Descriptive corrections remain available. Older history did not identify its bond, so any unlinked legacy bond history conservatively protects financial changes to all bonds. The save error explains this restriction. Bonds with no related or ambiguous history remain editable.

New bond acquisitions identify the bond through the existing optional history event key. Existing history is never rewritten automatically. A future correction/reconciliation feature is needed for financial changes that would affect recorded history.

## ETF transaction dates

Enter purchases and sales in chronological day order for each ISIN. A purchase or sale dated before a recorded sale is rejected before holdings change. This prevents later entry of a backdated trade from assigning gains to the wrong period.

New sale-history rows identify the normalized ISIN through the existing event key. Their cutoff survives removing an empty ETF and re-entering it, or replacing positions by import. Earlier unlinked legacy sales impose a conservative date cutoff across all ETFs because the original instrument cannot be determined safely. Transactions on the same local calendar day are allowed; these forms record transaction days, not intraday execution ordering.

## Deletion and cash-flow display

Bond deletions use one isolated save, cascade to projected cash flows, and retain historical records. A failed deletion leaves the database intact and reports an error instead of appearing to succeed.

Cash-flow filters include entire selected days, including bonds maturing today. The screen observes inserted and deleted cash flows, so recalculation replaces its displayed rows. Cards group by position identity, keeping identically named positions at different banks separate. Next Coupon uses positive persisted interest payments bounded by acquisition and maturity; zero coupons and dates after redemption cannot become the next payment.

Positions JSON remains unchanged. It is still a transfer of current positions, not a full backup, and it does not carry the history used by these safeguards to a new installation.
