#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

// All wire times are monotonic nanoseconds. Host-local durations do not need
// synchronization; cross-device ages are estimates, never presentation times.
namespace edgetiming {
constexpr uint64_t kSyncLifetimeNs = 120000000000ULL;
constexpr uint64_t kMaxProbeNs = 5000000000ULL;
constexpr size_t kMetadataBytes = 48;
constexpr size_t kMetricWindow = 120;

inline uint64_t ReadBE(const uint8_t* p, size_t n) {
    uint64_t value = 0;
    while (n--) value = (value << 8) | *p++;
    return value;
}

struct FrameTiming {
    bool timed = false, sourceValid = false;
    uint64_t sourceCapture = 0, captureCallback = 0, encodeStart = 0;
    uint64_t encodeDone = 0, sendStart = 0;
};

// Validate before exposing any metadata or removing it from the codec payload.
// Untimed Annex B is deliberately left unchanged for legacy senders.
inline bool ParseFrameTiming(const std::vector<uint8_t>& plain, uint8_t flags,
                             FrameTiming& result, size_t& payloadOffset) {
    result = {}; payloadOffset = 0;
    if (!(flags & 0x2)) return !plain.empty();
    if (plain.size() <= kMetadataBytes || plain[0] != 'E' || plain[1] != 'D' ||
        plain[2] != 'T' || plain[3] != '1') return false;
    const uint32_t metadataFlags = static_cast<uint32_t>(ReadBE(plain.data() + 4, 4));
    if (metadataFlags & ~uint32_t(1)) return false;
    FrameTiming value;
    value.timed = true; value.sourceValid = metadataFlags & 1;
    value.sourceCapture = ReadBE(plain.data() + 8, 8);
    value.captureCallback = ReadBE(plain.data() + 16, 8);
    value.encodeStart = ReadBE(plain.data() + 24, 8);
    value.encodeDone = ReadBE(plain.data() + 32, 8);
    value.sendStart = ReadBE(plain.data() + 40, 8);
    if (!value.captureCallback || value.captureCallback > value.encodeStart ||
        value.encodeStart > value.encodeDone || value.encodeDone > value.sendStart ||
        value.sendStart > static_cast<uint64_t>(INT64_MAX)) return false;
    if (value.sourceValid ? (!value.sourceCapture || value.sourceCapture > value.captureCallback)
                          : value.sourceCapture != 0) return false;
    // A timed payload must still start with a complete Annex B start code and NAL.
    const size_t n = plain.size() - kMetadataBytes;
    const auto* p = plain.data() + kMetadataBytes;
    if (n < 5 || p[0] != 0 || p[1] != 0 ||
        !(p[2] == 1 || (n >= 6 && p[2] == 0 && p[3] == 1))) return false;
    result = value; payloadOffset = kMetadataBytes;
    return true;
}

inline bool ParseUInt64(const std::string& text, uint64_t& result) {
    if (text.empty() || text.size() > 19) return false;
    uint64_t value = 0;
    for (char c : text) {
        if (c < '0' || c > '9') return false;
        const uint64_t digit = static_cast<uint64_t>(c - '0');
        if (value > (static_cast<uint64_t>(INT64_MAX) - digit) / 10) return false;
        value = value * 10 + digit;
    }
    result = value; return true;
}

inline bool ParseTimeReply(const std::string& line, uint64_t expectedT0,
                           uint64_t& t1, uint64_t& t2) {
    std::istringstream fields(line);
    std::string tag, echo, first, second, extra;
    uint64_t t0 = 0;
    return bool(fields >> tag >> echo >> first >> second) && tag == "TIME" &&
        !(fields >> extra) && ParseUInt64(echo, t0) && t0 == expectedT0 &&
        ParseUInt64(first, t1) && ParseUInt64(second, t2);
}

struct ClockSync {
    uint64_t calibratedAt = 0, bestRttNs = 0;
    uint32_t validSamples = 0;
    double offsetNs = 0, uncertaintyNs = 0; // server clock minus client clock

    bool Add(uint64_t t0, uint64_t t1, uint64_t t2, uint64_t t3) {
        if (!t0 || !t1 || !t2 || !t3 || t0 > t3 || t1 > t2 ||
            t0 > uint64_t(INT64_MAX) || t1 > uint64_t(INT64_MAX) ||
            t2 > uint64_t(INT64_MAX) || t3 > uint64_t(INT64_MAX)) return false;
        const uint64_t roundTrip = t3 - t0, serverWork = t2 - t1;
        if (roundTrip > kMaxProbeNs || serverWork > roundTrip) return false;
        const uint64_t adjustedRtt = roundTrip - serverWork;
        ++validSamples;
        if (calibratedAt && adjustedRtt >= bestRttNs) return true;
        // Subtract signed operands separately to avoid unsigned underflow and
        // summation overflow even when the two boot clocks have a large offset.
        offsetNs = double(int64_t(t1) - int64_t(t0)) / 2.0 +
                   double(int64_t(t2) - int64_t(t3)) / 2.0;
        uncertaintyNs = double(adjustedRtt) / 2.0;
        bestRttNs = adjustedRtt; calibratedAt = t3;
        return true;
    }
    bool Valid(uint64_t now) const {
        return calibratedAt && now >= calibratedAt && now - calibratedAt <= kSyncLifetimeNs;
    }
    bool AgeMs(uint64_t serverTime, uint64_t localTime, double& age) const {
        if (!serverTime || serverTime > uint64_t(INT64_MAX) ||
            localTime > uint64_t(INT64_MAX) || !Valid(localTime)) return false;
        const double delta = double(int64_t(localTime) - int64_t(serverTime)) + offsetNs;
        // Asymmetric-path error can make an estimate negative. Do not clamp it
        // to a fabricated zero-latency sample; expose its absence in the counts.
        if (!std::isfinite(delta) || delta < 0) return false;
        age = delta / 1e6; return true;
    }
};

struct Samples {
    std::vector<double> values;
    uint64_t count = 0;
    void Add(double value) {
        if (!std::isfinite(value) || value < 0) return;
        ++count; values.push_back(value);
        if (values.size() > kMetricWindow) values.erase(values.begin());
    }
    double Percentile(double q) const {
        if (values.empty()) return 0;
        auto copy = values; std::sort(copy.begin(), copy.end());
        return copy[size_t(double(copy.size() - 1) * q)];
    }
    void Json(std::ostream& out, const char* name, bool valid = true, bool zeroWhenEmpty = false) const {
        out << ",\"" << name << "P50ms\":";
        if (valid && (!values.empty() || zeroWhenEmpty)) out << Percentile(0.5); else out << "null";
        out << ",\"" << name << "P95ms\":";
        if (valid && (!values.empty() || zeroWhenEmpty)) out << Percentile(0.95); else out << "null";
        out << ",\"" << name << "SampleCount\":" << count;
        out << ",\"" << name << "WindowSamples\":" << (valid ? values.size() : 0);
    }
};
} // namespace edgetiming
