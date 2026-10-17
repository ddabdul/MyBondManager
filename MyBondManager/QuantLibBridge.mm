#include "QuantLibBridge.h"
#include <ql/version.hpp>
#include <ql/time/date.hpp>
#include <ql/time/calendars/target.hpp>
#include <ql/time/calendars/nullcalendar.hpp>
#include <ql/time/schedule.hpp>
#include <ql/time/daycounters/actualactual.hpp>
#include <ql/cashflows/fixedratecoupon.hpp>
#include <algorithm>
#include <cmath>
#include <vector>
#include <cstring>
#include <exception>
#include <stdexcept>

#include "QuantLibSupport.hpp"
using namespace MBMQuantLib;
const char *MBMQLVersion(void) { return QL_VERSION; }
int MBMQLAdjust(int32_t day, int32_t adjustment, int32_t *output, char *error, size_t capacity) {
    try {
        std::lock_guard<std::recursive_mutex> guard(mutex());
        if (adjustment != 0 && adjustment != 1) throw std::invalid_argument("Unsupported payment adjustment.");
        if (!output) throw std::invalid_argument("Missing payment date output.");
        auto adjusted = QuantLib::TARGET().adjust(date(day), adjustment == 0 ? QuantLib::Following : QuantLib::ModifiedFollowing);
        *output = encoded(adjusted);
        diagnostic(error, capacity, "");
        return 0;
    } catch (const std::exception &failure) {
        diagnostic(error, capacity, failure.what()); return 1;
    } catch (...) {
        diagnostic(error, capacity, "Unexpected native calendar failure."); return 3;
    }
}

int MBMQLFollowing(int32_t day, int32_t *output, char *error, size_t capacity) {
    return MBMQLAdjust(day,0,output,error,capacity);
}

namespace {
std::vector<MBMQLPayment> fixedPayments(const MBMQLRequest &request, bool endOfMonth) {
    using namespace QuantLib;
    const Date maturity = date(request.maturityDay);
    const TARGET calendar;
    std::vector<MBMQLPayment> result;
    if (request.structure == 0) {
        const Date start = date(request.startDay);
        if (start >= maturity) throw std::invalid_argument("Accrual start must precede maturity.");
        if (request.frequency != 1 && request.frequency != 2 && request.frequency != 4)
            throw std::invalid_argument("Coupon frequency is unsupported.");
        const Period tenor(12 / request.frequency, Months);
        const Date first = request.firstCouponDay ? date(request.firstCouponDay) : Date();
        if (first != Date()) {
            if (first <= start || first > maturity)
                throw std::invalid_argument("Verified first coupon contradicts accrual start or the regular schedule.");
            const Schedule regular(start, maturity, tenor, NullCalendar(), Unadjusted, Unadjusted,
                                   DateGeneration::Backward, endOfMonth);
            if (std::find(regular.dates().begin() + 1, regular.dates().end(), first) == regular.dates().end())
                throw std::invalid_argument("Verified first coupon contradicts accrual start or the regular schedule.");
        }
        Schedule schedule;
        if (first == maturity) {
            const bool regular = NullCalendar().advance(maturity, -tenor, Unadjusted, endOfMonth) == start;
            schedule = Schedule(std::vector<Date>{start, maturity}, NullCalendar(), Unadjusted,
                                Unadjusted, tenor, DateGeneration::Backward, endOfMonth, std::vector<bool>{regular});
        } else {
            schedule = Schedule(start, maturity, tenor, NullCalendar(), Unadjusted, Unadjusted,
                                DateGeneration::Backward, endOfMonth, first);
        }
        if (schedule.size() > 1201) throw std::invalid_argument("Coupon schedule exceeds 1,200 periods.");
        // Reference periods retain the final-maturity anchor even when the first
        // payable coupon is a clamped day (e.g. November30 on a May31 grid).
        std::vector<Date> referenceDates{maturity};
        for (int index = 1; index <= 1200; ++index) {
            const Date prior = NullCalendar().advance(maturity, -index * tenor, Unadjusted, endOfMonth);
            referenceDates.insert(referenceDates.begin(), prior);
            if (prior <= start) break;
        }
        if (referenceDates.front() > start) throw std::invalid_argument("Opening reference schedule exceeds 1,200 periods.");
        const Schedule referenceSchedule(referenceDates, NullCalendar(), Unadjusted, Unadjusted,
            tenor, DateGeneration::Backward, endOfMonth, std::vector<bool>(referenceDates.size() - 1, true));
        const ActualActual dayCount(ActualActual::ISMA, referenceSchedule);
        const Leg leg = FixedRateLeg(schedule).withNotionals(request.nominal)
            .withCouponRates(request.annualRate, dayCount)
            .withPaymentCalendar(calendar).withPaymentAdjustment(Following);
        size_t couponIndex = 0;
        for (const auto &flow : leg) {
            auto coupon = ext::dynamic_pointer_cast<Coupon>(flow);
            if (!coupon) throw std::runtime_error("Native leg contains a non-coupon payment.");
            result.push_back({0, encoded(coupon->accrualEndDate()), encoded(coupon->date()),
                couponIndex == 0 && !schedule.isRegular(1) ? 1 : 0,
                coupon->nominal() * coupon->rate() * coupon->accrualPeriod()});
            ++couponIndex;
        }
    }
    result.push_back({1, encoded(maturity), encoded(calendar.adjust(maturity, Following)), 0,
                      request.nominal * request.redemptionPercent / 100.0});
    for (const auto &payment : result) {
        if (!std::isfinite(payment.amount)) throw std::invalid_argument("Calculated payment amount is out of range.");
    }
    return result;
}
}
int MBMQLPayments(const MBMQLRequest *request, MBMQLPayment *output, size_t capacity,
                  size_t *count, char *error, size_t errorCapacity) {
    if (count) *count = 0;
    try {
        std::lock_guard<std::recursive_mutex> guard(mutex());
        if (!request || !count || (!output && capacity)) throw std::invalid_argument("Missing native payment buffers.");
        if (request->structure != 0 && request->structure != 1) throw std::invalid_argument("Unsupported interest structure.");
        if (request->roll < 0 || request->roll > 2) throw std::invalid_argument("Invalid coupon roll.");
        if (!std::isfinite(request->nominal) || request->nominal <= 0 ||
            !std::isfinite(request->redemptionPercent) || request->redemptionPercent <= 0 ||
            !std::isfinite(request->annualRate) || request->annualRate < 0)
            throw std::invalid_argument("Invalid native payment amount or rate.");
        auto payments = fixedPayments(*request, request->roll == 1);
        if (request->structure == 0 && request->roll == 2) {
            const auto alternative = fixedPayments(*request, true);
            bool differs = alternative.size() != payments.size();
            for (size_t i = 0; !differs && i < payments.size(); ++i) {
                differs = alternative[i].contractualDay != payments[i].contractualDay ||
                          std::abs(alternative[i].amount - payments[i].amount) > 1e-8;
            }
            if (differs) throw std::invalid_argument("Confirm the coupon month-end roll.");
        }
        if (capacity < payments.size()) {
            diagnostic(error, errorCapacity, "Native payment output capacity is insufficient.");
            return 2;
        }
        std::copy(payments.begin(), payments.end(), output);
        *count = payments.size();
        diagnostic(error, errorCapacity, "");
        return 0;
    } catch (const std::exception &failure) {
        diagnostic(error, errorCapacity, failure.what()); return 1;
    } catch (...) {
        diagnostic(error, errorCapacity, "Unexpected native payment failure."); return 3;
    }
}
