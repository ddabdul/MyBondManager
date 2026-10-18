#ifndef MBM_QUANTLIB_BRIDGE_H
#define MBM_QUANTLIB_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    int32_t structure;
    int32_t startDay, maturityDay, firstCouponDay;
    int32_t frequency, roll;
    double nominal, annualRate, redemptionPercent;
} MBMQLRequest;
typedef struct {
    int32_t kind, contractualDay, paymentDay, irregularOpening;
    double amount;
} MBMQLPayment;
typedef struct { int32_t years; double rate; } MBMQLSwapQuote;
typedef struct {
    int32_t quoteDay, indexTenorMonths;
    double depositRate;
    const MBMQLSwapQuote *swaps;
    size_t swapCount;
} MBMQLCurveRequest;
typedef struct { int32_t fixingDay; } MBMQLForwardProbe;
typedef struct { int32_t fixingDay, valueDay, indexEndDay; double rate; } MBMQLForwardResult;
typedef struct { double maxDepositResidual, maxSwapResidual; int32_t lastCurveDay; } MBMQLCurveDiagnostics;
int MBMQLCurveForwards(const MBMQLCurveRequest *request, const MBMQLForwardProbe *probes, size_t probeCount,
    MBMQLForwardResult *output, size_t capacity, size_t *count, MBMQLCurveDiagnostics *diagnostics,
    char *error, size_t errorCapacity);
typedef struct { int32_t day; double rate; } MBMQLPublishedFixing;
typedef struct {
    int32_t startDay, maturityDay, firstCouponDay, transitionDay, firstFloatingCouponDay;
    int32_t fixedFrequency, floatingFrequency, indexTenorMonths, resetLagDays;
    int32_t fixedRoll, floatingRoll, accrualAdjustment, paymentAdjustment;
    int32_t floatingDayCount, resetAnchor, acquisitionDay, paymentFromDay, valuationDay;
    double nominal, fixedAnnualRate, spreadBps, gearing, redemptionPercent;
} MBMQLFloatingRequest;
typedef struct {
    MBMQLPayment payment;
    int32_t rateSource, fixingDay;
    double indexRate, effectiveCouponRate;
} MBMQLFloatingPayment;
int MBMQLFloatingCouponDays(const MBMQLFloatingRequest *request, int32_t *output, size_t capacity,
    size_t *count, char *error, size_t errorCapacity);
int MBMQLFloatingPayments(const MBMQLFloatingRequest *request, const MBMQLCurveRequest *curve,
    const MBMQLPublishedFixing *fixings, size_t fixingCount, MBMQLFloatingPayment *output,
    size_t capacity, size_t *count, char *error, size_t errorCapacity);
int MBMQLAccruedInterest(const MBMQLRequest *request, int32_t acquisitionDay,
    double *amount, char *error, size_t errorCapacity);
// Annual effective purchase yield from dirty cash outlay (Actual/365 Fixed). available is zero when undefined.
int MBMQLPurchaseYield(const MBMQLPayment *payments, size_t count, int32_t acquisitionDay,
    double cost, double *yield, int32_t *available, char *error, size_t errorCapacity);
const char *MBMQLVersion(void);
int MBMQLAdjust(int32_t day, int32_t adjustment, int32_t *output, char *error, size_t errorCapacity);
int MBMQLFollowing(int32_t day, int32_t *output, char *error, size_t errorCapacity);
int MBMQLPayments(const MBMQLRequest *request, MBMQLPayment *output,
    size_t capacity, size_t *count, char *error, size_t errorCapacity);
#ifdef __cplusplus
}
#endif
#endif
