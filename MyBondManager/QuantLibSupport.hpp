#pragma once
#include <ql/time/date.hpp>
#include <algorithm>
#include <cstring>
#include <mutex>
#include <stdexcept>
namespace MBMQuantLib {
inline std::recursive_mutex &mutex() { static std::recursive_mutex value; return value; }
inline void diagnostic(char *buffer, size_t capacity, const char *message) noexcept {
    if (!buffer || !capacity) return;
    const size_t length = std::min(capacity - 1, std::strlen(message));
    std::memcpy(buffer, message, length); buffer[length] = 0;
}
inline QuantLib::Date date(int32_t value) {
    int year = value / 10000, month = value / 100 % 100, day = value % 100;
    if (year < 1901 || year > 2199 || month < 1 || month > 12 || day < 1 || day > 31)
        throw std::invalid_argument("QuantLib dates must be valid days in 1901...2199.");
    return QuantLib::Date(day, static_cast<QuantLib::Month>(month), year);
}
inline int32_t encoded(const QuantLib::Date &value) {
    return value.year() * 10000 + value.month() * 100 + value.dayOfMonth();
}
}
