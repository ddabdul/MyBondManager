#include "CurveBootstrap.hpp"
#include "QuantLibSupport.hpp"
#include <ql/settings.hpp>
#include <ql/time/calendars/target.hpp>
#include <ql/indexes/ibor/euribor.hpp>
#include <ql/quotes/simplequote.hpp>
#include <ql/termstructures/yield/ratehelpers.hpp>
#include <ql/termstructures/yield/piecewiseyieldcurve.hpp>
#include <ql/math/interpolations/loginterpolation.hpp>
#include <ql/time/daycounters/actual360.hpp>
#include <ql/time/daycounters/actual365fixed.hpp>
#include <ql/time/daycounters/thirty360.hpp>
#include <cmath>
#include <set>
#include <vector>
using namespace QuantLib;
using namespace MBMQuantLib;

ext::shared_ptr<YieldTermStructure> buildProjectionCurve(const MBMQLCurveRequest &request,
                                                       MBMQLCurveDiagnostics *diagnostics) {
    if (request.indexTenorMonths != 1 && request.indexTenorMonths != 3 &&
        request.indexTenorMonths != 6 && request.indexTenorMonths != 12)
        throw std::invalid_argument("Unsupported EURIBOR tenor.");
    if (!request.swaps || request.swapCount != 8 || !std::isfinite(request.depositRate))
        throw std::invalid_argument("A finite deposit and all eight swap pillars are required.");
    const Date quoteDay = date(request.quoteDay);
    if (!TARGET().isBusinessDay(quoteDay)) throw std::invalid_argument("Curve quote day is not a TARGET business day.");
    Settings::instance().evaluationDate() = quoteDay;
    auto index = ext::make_shared<Euribor>(Period(request.indexTenorMonths, Months));
    std::vector<ext::shared_ptr<RateHelper>> helpers;
    helpers.push_back(ext::make_shared<DepositRateHelper>(Handle<Quote>(ext::make_shared<SimpleQuote>(request.depositRate)), index));
    std::set<int> years;
    for (size_t i = 0; i < request.swapCount; ++i) {
        const auto &swap = request.swaps[i];
        if (!std::isfinite(swap.rate) || !years.insert(swap.years).second)
            throw std::invalid_argument("Swap pillars must be unique and finite.");
        helpers.push_back(ext::make_shared<SwapRateHelper>(Handle<Quote>(ext::make_shared<SimpleQuote>(swap.rate)),
            Period(swap.years, Years), TARGET(), Annual, ModifiedFollowing, Thirty360(Thirty360::BondBasis), index));
    }
    if (years != std::set<int>{1,2,3,5,7,10,15,30}) throw std::invalid_argument("Required swap pillars are 1,2,3,5,7,10,15,30 years.");
    auto curve = ext::make_shared<PiecewiseYieldCurve<Discount, MonotonicLogCubic>>(quoteDay, helpers, Actual365Fixed());
    curve->discount(curve->maxDate());
    curve->freeze();
    double depositResidual = std::abs(helpers[0]->impliedQuote() - request.depositRate), swapResidual = 0;
    for (size_t i = 0; i < request.swapCount; ++i)
        swapResidual = std::max(swapResidual, std::abs(helpers[i+1]->impliedQuote() - request.swaps[i].rate));
    if (!std::isfinite(depositResidual) || !std::isfinite(swapResidual) || depositResidual > 1e-6 || swapResidual > 1e-6)
        throw std::invalid_argument("Projection curve does not reprice its inputs within 0.01bp.");
    if (diagnostics) *diagnostics = {depositResidual, swapResidual, encoded(curve->maxDate())};
    return curve;
}
int MBMQLCurveForwards(const MBMQLCurveRequest *request, const MBMQLForwardProbe *probes, size_t probeCount,
    MBMQLForwardResult *output, size_t capacity, size_t *count, MBMQLCurveDiagnostics *diagnostics,
    char *error, size_t errorCapacity) {
    if (count) *count = 0;
    try {
        std::lock_guard<std::recursive_mutex> guard(mutex());
        SavedSettings settings;
        if (!request || !count || !diagnostics || (probeCount && (!probes || !output)) || probeCount > 1201)
            throw std::invalid_argument("Invalid curve request buffers.");
        MBMQLCurveDiagnostics calibrated{};
        const auto curve = buildProjectionCurve(*request, &calibrated);
        Euribor index(Period(request->indexTenorMonths, Months));
        std::vector<MBMQLForwardResult> results;
        for (size_t i = 0; i < probeCount; ++i) {
            const Date fixing = date(probes[i].fixingDay);
            if (!index.isValidFixingDate(fixing)) throw std::invalid_argument("Reset date is not a valid TARGET fixing day.");
            const Date value = index.valueDate(fixing), end = index.maturityDate(value);
            if (value < curve->referenceDate() || end > curve->maxDate())
                throw std::invalid_argument("Reset period is outside the quoted curve horizon.");
            const double rate = curve->forwardRate(value, end, Actual360(), Simple).rate();
            if (!std::isfinite(rate)) throw std::invalid_argument("Nonfinite projected index rate.");
            results.push_back({encoded(fixing), encoded(value), encoded(end), rate});
        }
        if (capacity < results.size()) { diagnostic(error, errorCapacity, "Curve output capacity is insufficient."); return 2; }
        std::copy(results.begin(), results.end(), output);
        *count = results.size(); *diagnostics = calibrated;
        diagnostic(error, errorCapacity, ""); return 0;
    } catch (const std::exception &failure) { diagnostic(error, errorCapacity, failure.what()); return 1; }
    catch (...) { diagnostic(error, errorCapacity, "Unexpected native curve failure."); return 3; }
}
