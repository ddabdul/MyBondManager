# EURIBOR market inputs

The default direct sources are cf.com public deposit and tenor-specific swap quotes, plus Bundesbank published EURIBOR history. Automatic quotes support3M/6M. Matching1M/12M quotes can be imported; another tenor is never substituted. Bridge is a read-only reference, not a runtime dependency.

Normalized JSON inputs contain formatVersion1, method euribor-singlecurve-v1, sourceName, quotes(indexTenorMonths, quoteDay, depositRate, swaps(years,rate)) and historicalFixings(day,rate). All normalized rates are decimals. Source percentages convert once at the HTTP boundary. An empty historical list is valid for future-only resets; an eligible past reset still requires an exact published fixing during instrument calculation.

Projection uses the index deposit and1/2/3/5/7/10/15/30Y swap pillars, TARGET two-day spot, annual fixed30/360 BondBasis, ModifiedFollowing and EURIBOR ACT/360. The log-cubic discount interpolator explicitly matches the Python wrapper's monotonic spline defaults. This is a single-curve approximation without FRA inputs, OIS discounting or callable valuation. Every deposit/swap must reprice within0.01bp; forwards use index value/maturity dates and never extrapolate beyond the quoted horizon.

Source snapshots are immutable and content-addressed. Their identity includes normalized financial inputs and calibration diagnostics, excluding retrieval time. Local catalogue refresh/import does not approve bonds, replace their frozen snapshots or rewrite financial history. A separate explicit adoption validates both forecast and activation-based receipt windows. Quotes older than two TARGET business days are stale; weekends are not counted as business days.

Legacy bonds.json remains a dated forecast in its existing webapp format. Native version 2 embeds the frozen snapshot and valuation context for genuine floating provenance and offline Mac-to-Mac reproduction.


Use **Market Data** to save public-source snapshots or import normalized dated JSON. Use **Review Terms** to select a matching snapshot and valuation day for a floating draft, confirm the contract fields, preview, then apply once per ISIN. Refreshing a source does not change approved forecasts. **Rebuild approved floating forecasts** adopts the selected context explicitly, preserving approval and activation dates. Each ISIN succeeds or fails separately; a missing fixing or receipt conflict leaves its old forecast intact.

Floating contracts currently support EURIBOR 1M/3M/6M/12M, plain in-advance coupons, explicit spread/gearing/reset lag, ACT/360 and separate contractual or adjusted reset anchors. Historical resets on or before valuation require published observations. Future resets use the frozen curve; projected interest never becomes a receipt. Fixed-to-floating changes must fall on the fixed phase's contractual grid. Caps/floors, in-arrears coupons, off-grid phase changes and callable valuation remain unsupported and visible as review reasons. A manually confirmed Fixed override remains a constant-rate assumption with its warning.
