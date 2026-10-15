# Current Positions Transfer

Export Positions creates a new directory named with the local export date and time, such as `positions-2026-10-15_14-30-05`, in the selected folder. If the name already exists, a numeric suffix is added (`-2`, `-3`, etc.). The directory contains `bonds.json` and `etfs.json`, using the existing JSON layout. Both files are written before the directory is published; an error leaves older exports intact.

The files contain current bond records and their projected cash flows, plus ETF holdings and price history. **They do not contain historical acquisition, coupon, maturity, or sale records. This is not a complete backup.**

Import Positions decodes and validates both files before asking for replacement confirmation. Confirmation shows the counts from that prepared payload. After confirmation, the same payload replaces all current bond and ETF positions; changes to the files while the dialog is open do not change what is applied. Cancelling changes nothing. Empty arrays intentionally clear that category.

Existing destination history is retained unchanged. Import does not restore, reconstruct, or replay history. As a result, retained history can describe positions that are no longer present. Live launch processing continues from its existing checkpoint.

The original two-file format remains readable by selecting its containing folder. Duplicate identifiers, invalid financial values, mismatched ETF child identifiers, or a missing file cause an explicit error before replacement. A failed database save discards that operation, leaving persisted positions unchanged.

Export validation compares all serialized position fields, nested cash flows, holdings, and prices. Array ordering and restored Core Data object IDs do not affect matching. Dates are compared at the whole-second precision of the ISO-8601 export format; duplicate nested rows remain significant.

Daily ETF history now records the latest successful quote for each local calendar day, rather than an average. Sale history uses the execution price and date entered in the sale form. Existing historical records are not recalculated by these changes.
