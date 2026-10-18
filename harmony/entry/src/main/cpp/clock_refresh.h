#pragma once
#include "timing.h"
#include <algorithm>
#include <functional>
#include <string>

namespace edgetiming {
// Called only by the post-handshake control TLS owner. No I/O or worker thread
// lives here; stop() discards every partial reply and outstanding request.
struct ClockRefresh {
    static constexpr uint64_t kIntervalNs = 90000000000ULL;
    static constexpr uint64_t kReplyTimeoutNs = 1000000000ULL;
    static constexpr uint64_t kPendingWaitNs = 2000000ULL;
    static constexpr unsigned kMaxProbes = 5;
    uint64_t due = 0, pending = 0, deadline = 0;
    unsigned attempted = 0;
    bool cycle = false, stopped = false, discardLine = false;
    ClockSync candidate;
    std::string line;
    uint64_t accepted = 0, timeouts = 0, rejected = 0, overlong = 0;

    ClockRefresh(uint64_t now, const ClockSync& initial)
      : due((initial.calibratedAt ? initial.calibratedAt : now) + kIntervalNs) {}

    std::string NextRequest(uint64_t now, const std::function<void(const ClockSync&)>& commit) {
        if (stopped) return {};
        if (pending && now >= deadline) {
            pending = 0; ++timeouts;
            // A silent/legacy host gets one bounded read window, not five
            // consecutive seconds of fast wakeups. Keep earlier valid probes.
            attempted = kMaxProbes;
        }
        if (!cycle && now >= due) { cycle = true; candidate = {}; attempted = 0; }
        if (!cycle || pending) return {};
        if (attempted == kMaxProbes) {
            if (candidate.calibratedAt) commit(candidate);
            cycle = false; due = now + kIntervalNs; return {};
        }
        pending = now; deadline = now + kReplyTimeoutNs; ++attempted;
        return "TIME " + std::to_string(now) + "\n";
    }

    // t3 is measured when SSL_read returns bytes. A line survives fragmented
    // TLS records; at most 255 bytes are retained until its newline arrives.
    void Consume(const char* bytes, size_t length, uint64_t t3) {
        if (stopped) return;
        for (size_t i = 0; i < length; ++i) {
            const char ch = bytes[i];
            if (ch == '\n') {
                if (!discardLine) {
                    uint64_t t1 = 0, t2 = 0;
                    if (pending && t3 <= deadline && ParseTimeReply(line, pending, t1, t2)) {
                        if (candidate.Add(pending, t1, t2, t3)) ++accepted;
                        else ++rejected;
                        pending = 0;
                    } else ++rejected;
                }
                discardLine = false; line.clear(); continue;
            }
            if (discardLine) continue;
            if (line.size() == 255) { line.clear(); discardLine = true; ++overlong; }
            else line += ch;
        }
    }
    uint64_t WaitNs(uint64_t now) const {
        if (stopped) return 0;
        if (pending) return std::min(kPendingWaitNs, deadline > now ? deadline - now : 0);
        return 1000000000ULL;
    }
    void Stop() { stopped = true; cycle = false; pending = 0; candidate = {}; line.clear(); discardLine = false; }
};
} // namespace edgetiming
