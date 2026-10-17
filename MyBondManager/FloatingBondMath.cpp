#include "FloatingBondMath.hpp"
#include "CurveBootstrap.hpp"
#include "QuantLibSupport.hpp"
#include <ql/settings.hpp>
#include <ql/time/schedule.hpp>
#include <ql/time/calendars/target.hpp>
#include <ql/time/calendars/nullcalendar.hpp>
#include <ql/time/daycounters/actual360.hpp>
#include <ql/indexes/ibor/euribor.hpp>
#include <cmath>
#include <map>
#include <vector>
using namespace QuantLib;
using namespace MBMQuantLib;
namespace {
struct PeriodPayment { Date start, end, paid; bool fixed; MBMQLPayment fixedPayment{}; };
std::vector<PeriodPayment> periods(const MBMQLFloatingRequest &r) {
    const Date start = date(r.startDay), maturity = date(r.maturityDay);
    const Date transition = r.transitionDay ? date(r.transitionDay) : start;
    if (start >= maturity || transition < start || transition >= maturity)
        throw std::invalid_argument("Floating phase dates contradict accrual start or maturity.");
    if (r.floatingFrequency != 1 && r.floatingFrequency != 2 && r.floatingFrequency != 4 && r.floatingFrequency != 12)
        throw std::invalid_argument("Unsupported floating coupon frequency.");
    if (r.floatingRoll < 0 || r.floatingRoll > 1 || r.accrualAdjustment < 0 || r.accrualAdjustment > 1 ||
        r.paymentAdjustment < 0 || r.paymentAdjustment > 1 || r.floatingDayCount != 0 || r.resetAnchor < 0 || r.resetAnchor > 1)
        throw std::invalid_argument("Unsupported floating conventions or reset anchor.");
    std::vector<PeriodPayment> result;
    if (r.transitionDay) {
        MBMQLRequest fixed{0,r.startDay,r.maturityDay,r.firstCouponDay,r.fixedFrequency,r.fixedRoll,
                           1,r.fixedAnnualRate,100};
        MBMQLPayment payments[1201]; size_t count = 0; char error[512];
        const int status = MBMQLPayments(&fixed,payments,1201,&count,error,sizeof(error));
        if (status) throw std::invalid_argument(error);
        bool boundary = false; Date previous = start;
        for (size_t i = 0; i < count; ++i) {
            const auto &payment = payments[i];
            if (payment.kind != 0) continue;
            const Date end = date(payment.contractualDay);
            if (end == transition) boundary = true;
            if (end <= transition) {
                if (payment.irregularOpening && !r.firstCouponDay)
                    throw std::invalid_argument("Confirm the fixed phase first coupon for its irregular opening period.");
                result.push_back({previous,end,date(payment.paymentDay),true,payment});
            }
            previous = end;
        }
        if (!boundary) throw std::invalid_argument("Off-grid fixed-to-floating transition is not supported; verify the phase schedule.");
    }
    const Period tenor(12 / r.floatingFrequency, Months);
    const bool eom = r.floatingRoll == 1;
    const Date first = r.firstFloatingCouponDay ? date(r.firstFloatingCouponDay) : Date();
    Schedule regular(transition,maturity,tenor,NullCalendar(),Unadjusted,Unadjusted,DateGeneration::Backward,eom);
    if (first != Date() && (first <= transition || first > maturity ||
        std::find(regular.dates().begin()+1,regular.dates().end(),first) == regular.dates().end()))
        throw std::invalid_argument("First floating coupon contradicts the regular phase schedule.");
    Schedule schedule;
    if (first == maturity) {
        schedule = Schedule(std::vector<Date>{transition,maturity},NullCalendar(),Unadjusted,Unadjusted,
            tenor,DateGeneration::Backward,eom,std::vector<bool>{false});
    } else {
        schedule = Schedule(transition,maturity,tenor,NullCalendar(),Unadjusted,Unadjusted,DateGeneration::Backward,eom,first);
    }
    if (!r.firstFloatingCouponDay && !schedule.isRegular(1))
        throw std::invalid_argument("Confirm the first floating coupon for its irregular opening period.");
    for (size_t i = 1; i < schedule.size(); ++i) {
        const auto end = schedule.date(i);
        result.push_back({schedule.date(i-1),end,TARGET().adjust(end,r.paymentAdjustment ? ModifiedFollowing : Following),false,{}});
    }
    if (result.size() > 1200) throw std::invalid_argument("Coupon schedule exceeds 1,200 periods.");
    return result;
}
}
int MBMQLFloatingCouponDays(const MBMQLFloatingRequest *request, int32_t *output, size_t capacity,
    size_t *count, char *error, size_t errorCapacity) {
    if (count) *count = 0;
    try {
        std::lock_guard<std::recursive_mutex> guard(mutex());
        if (!request || !count || (!output && capacity)) throw std::invalid_argument("Missing floating date buffers.");
        const auto all = periods(*request);
        if (capacity < all.size()) { diagnostic(error,errorCapacity,"Floating date capacity is insufficient.");return 2; }
        for (size_t i=0;i<all.size();++i) output[i]=encoded(all[i].end);
        *count=all.size();diagnostic(error,errorCapacity,"");return 0;
    } catch (const std::exception &failure) { diagnostic(error,errorCapacity,failure.what());return 1; }
    catch (...) { diagnostic(error,errorCapacity,"Unexpected native phase schedule failure.");return 3; }
}
int MBMQLFloatingPayments(const MBMQLFloatingRequest *request, const MBMQLCurveRequest *curveRequest,
    const MBMQLPublishedFixing *fixings, size_t fixingCount, MBMQLFloatingPayment *output,
    size_t capacity, size_t *count, char *error, size_t errorCapacity) {
    if (count) *count=0;
    try {
        std::lock_guard<std::recursive_mutex> guard(mutex());
        SavedSettings settings;
        if (!request || !curveRequest || !count || (!output && capacity) || (fixingCount && !fixings) || fixingCount>100000)
            throw std::invalid_argument("Missing or excessive floating calculation buffers.");
        const auto &r=*request;
        if (!std::isfinite(r.nominal) || r.nominal<=0 || !std::isfinite(r.spreadBps) ||
            !std::isfinite(r.gearing) || r.gearing<=0 || !std::isfinite(r.redemptionPercent) || r.redemptionPercent<=0 ||
            !std::isfinite(r.fixedAnnualRate) || r.fixedAnnualRate<0 || r.resetLagDays<0 || r.resetLagDays>10)
            throw std::invalid_argument("Invalid floating coupon amount, spread, gearing or lag.");
        if (r.indexTenorMonths!=curveRequest->indexTenorMonths) throw std::invalid_argument("Curve tenor does not match the floating index.");
        const Date valuation=date(r.valuationDay), acquisition=date(r.acquisitionDay), from=date(r.paymentFromDay);
        if (date(curveRequest->quoteDay)>valuation) throw std::invalid_argument("Curve quote day is after valuation.");
        std::map<int32_t,double> published;
        for (size_t i=0;i<fixingCount;++i) {
            if (!std::isfinite(fixings[i].rate) || date(fixings[i].day)>valuation || !published.emplace(fixings[i].day,fixings[i].rate).second)
                throw std::invalid_argument("Published fixings must be finite, unique and no later than valuation.");
        }
        Euribor index(Period(r.indexTenorMonths,Months));
        ext::shared_ptr<YieldTermStructure> curve;
        std::vector<MBMQLFloatingPayment> result;
        for (const auto &period : periods(r)) {
            if (period.end<acquisition || period.paid<from) continue;
            if (period.fixed) {
                auto payment=period.fixedPayment;payment.amount*=r.nominal;
                result.push_back({payment,0,0,0,r.fixedAnnualRate});continue;
            }
            const Date accrualStart=r.accrualAdjustment ? TARGET().adjust(period.start,ModifiedFollowing) : period.start;
            const Date accrualEnd=r.accrualAdjustment ? TARGET().adjust(period.end,ModifiedFollowing) : period.end;
            if (accrualEnd<=accrualStart) throw std::invalid_argument("Adjusted floating accrual period is empty or reversed.");
            const Date anchor=r.resetAnchor ? accrualStart : period.start;
            if (r.resetLagDays==0 && !TARGET().isBusinessDay(anchor))
                throw std::invalid_argument("Zero-lag reset anchor is not a TARGET fixing day.");
            const Date fixing=TARGET().advance(anchor,-r.resetLagDays,Days);
            double rate;int source;
            if (fixing<=valuation) {
                auto found=published.find(encoded(fixing));
                if (found==published.end()) throw std::invalid_argument("Pending fixing: exact published reset is missing for the eligible coupon.");
                rate=found->second;source=1;
            } else {
                if (!curve) curve=buildProjectionCurve(*curveRequest);
                const Date value=index.valueDate(fixing), end=index.maturityDate(value);
                if (value<curve->referenceDate() || end>curve->maxDate()) throw std::invalid_argument("Floating reset exceeds the quoted curve horizon.");
                rate=curve->forwardRate(value,end,Actual360(),Simple).rate();source=2;
            }
            const double effective=r.gearing*rate+r.spreadBps/10000.0;
            const double amount=r.nominal*effective*Actual360().yearFraction(accrualStart,accrualEnd);
            if (!std::isfinite(amount) || !std::isfinite(effective) || !std::isfinite(rate)) throw std::invalid_argument("Floating coupon amount is out of range.");
            result.push_back({{0,encoded(period.end),encoded(period.paid),0,amount},source,encoded(fixing),rate,effective});
        }
        const Date maturity=date(r.maturityDay), paid=TARGET().adjust(maturity,r.paymentAdjustment ? ModifiedFollowing : Following);
        if (maturity>=acquisition && paid>=from) {
            const double amount=r.nominal*r.redemptionPercent/100.0;
            if (!std::isfinite(amount)) throw std::invalid_argument("Redemption amount is out of range.");
            result.push_back({{1,encoded(maturity),encoded(paid),0,amount},0,0,0,0});
        }
        if (capacity<result.size()) { diagnostic(error,errorCapacity,"Floating output capacity is insufficient.");return 2; }
        std::copy(result.begin(),result.end(),output);*count=result.size();diagnostic(error,errorCapacity,"");return 0;
    } catch (const std::exception &failure) { diagnostic(error,errorCapacity,failure.what());return 1; }
    catch (...) { diagnostic(error,errorCapacity,"Unexpected native floating calculation failure.");return 3; }
}
