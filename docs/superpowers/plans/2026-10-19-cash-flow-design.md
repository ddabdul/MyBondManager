# Cash Flow Design Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this approved design inline, with test-driven-development and verification-before-completion.

**Goal:** Apply the approved native macOS financial-calendar design, preserving calculations, historical scope and explicit approvals.

**Architecture:** Upcoming List and Calendar share canonical CalendarReceipt data and filters. Past report keeps its immutable report/export snapshot. Small SwiftUI presentation components provide aligned totals, notices and receipt rows without changing persistence or calculation engines.

**Design:** SF Pro with tabular amounts; semantic macOS surfaces, native blue selection, green coupon accents and restrained amber attention. Preserve the purple-blue identity as a narrow accent. Year tiles are the primary visual feature; payment rows stay compact. Left-align labels and dates, right-align amounts. Use disclosure controls for years/months, with no hover scaling. Preserve Years/Year/Month navigation and day drill-down. Keep controls and summary usable at 900-point app widths.

- [x] Task 1: Add a failing native regression for an explicit Past report workflow and visible scope; add List/Calendar receipt-total agreement regression. Update relevant native selector helpers to identify controls by segment labels.
- [x] Task 2: Replace CashFlowView's workflow checkbox and legacy component list with Upcoming/Past report and shared canonical results. Add reusable summary, notice, compact receipt row and explicit year/month List disclosure presentation. Verify date/bank/type filters, return to Upcoming and saved-data refresh.
- [x] Task 3: Restyle CashFlowCalendarView with quiet surfaces and legible day totals/payment counts; keep year tiles, native breadcrumbs and day-detail amounts. Restyle PastPaymentsView as compact rows with visible eligibility scope and concise expandable exclusions, preserving exact exported report. Reduce review header prose; distinguish status, assumptions, projections and blocking errors.
- [x] Task 4: Add cash-flow-only collapsible portfolio summary, verify native layouts in dark/light and narrow/wide sizes, inspect screenshots. Run the full test suite, obtain focused code/design review, document semantics, build/package the universal app. Do not commit or push unless requested.

**Verification:** xcodebuild Debug macOS test using /tmp/MyBondManager-quantlib; universal Release build using /tmp/MyBondManager-quantlib-release; scripts/verify-quantlib-build.sh packaged-app. Tests use in-memory portfolios and fake Calendar stores, with no changes to the user's database or Calendar.

**Completed validation:** 319 macOS tests passed; native screenshot/click checks cover List/Calendar receipt agreement, year/month disclosure, past review, bounded exclusions, sidebar collapse, 900/1100/1500-point navigation and light/dark appearance. Focused review findings on exclusion scrolling/count terminology and Upcoming date boundaries were addressed. Universal release and package verification passed. Build: /tmp/MyBondManager-Cash-Flow-Redesign-2026-10-19/MyBondManager.app. No commit/push or live portfolio/Calendar changes.

## Portfolio appearance correction

The user rejected the separate black workspace and narrow accent. Reuse the existing palette: PanelBackground (#57575A), window/table surface (appearance-aware), GradientStart (#9400D4), GradientEnd (#007AFF), coupon green and repayment blue. Use the portfolio's rounded large title on a full-width gradient header, SF body text, tabular right-aligned amounts and alternating compact rows. Year tiles use the same gradient as the summary tiles. Keep workflow and filters on the grey panel beneath the header. All calculations, report scopes, approvals and export payloads remain unchanged.

- [x] Align List, Calendar and Past report presentation to the portfolio; inspect native screenshots and verify tests and the universal build.

Correction validation: all 319 macOS tests passed. Inspected full app at 900 and 1500 points, expanded payment rows and gradient year tiles. Focused review contrast finding resolved by keeping payment labels in primary text with decorative colour markers. Universal Release build and self-contained package verification passed: /tmp/MyBondManager-Cash-Flow-App-Style-2026-10-19/MyBondManager.app. Changes remain uncommitted.

## Contrast review follow-up

Verified the reviewer finding against the forced dark app appearance and grey panel. Shared assumption labels, projected/conditional explanations, warnings, exclusion reasons and bank metadata now use primary text; blue/orange remain in status icons. A focused native rendering fixture exposes both row surfaces with projected, conditional and warning-bearing receipts. Inspected the screenshot and confirmed all text remains visible; existing native disclosure, report, calendar and navigation checks passed (9 tests), followed by all 3 design tests including the new fixture. Focused source review reports no remaining actionable findings.
