#pragma once
#include "QuantLibBridge.h"
#include <ql/termstructure.hpp>
#include <ql/termstructures/yieldtermstructure.hpp>
#include <ql/shared_ptr.hpp>
QuantLib::ext::shared_ptr<QuantLib::YieldTermStructure> buildProjectionCurve(
    const MBMQLCurveRequest &request, MBMQLCurveDiagnostics *diagnostics = nullptr);
