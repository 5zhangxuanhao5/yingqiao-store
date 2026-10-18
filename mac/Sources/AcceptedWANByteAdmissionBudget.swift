import Foundation

/// Value state; VideoSender owns it on its existing serial queue. No sockets,
/// timers, VT calls or screen ownership. Admission happens BEFORE encoding.
struct WANByteAdmissionBudget: Sendable {
    struct Permit: Sendable { let id: UUID }
    private struct Flight: Sendable { let bytes: Int; let atNs: UInt64 }
    private var reservations: [UUID: Int] = [:]
    private var flight: [UInt64: Flight] = [:]
    private(set) var targetKbps: Int
    private(set) var lastFrameID: UInt64 = 0
    private(set) var lastACK: UInt64 = 0
    private(set) var smoothedWireBytes: Double = 0
    private(set) var rejectedForBytes = 0
    private(set) var rejectedForOldACK = 0
    private(set) var oversizedFrames = 0
    private(set) var rejectedACKs = 0
    private(set) var accountedKeyframes = 0
    private(set) var accountedDeltaFrames = 0
    private(set) var lastKeyframeWireBytes = 0
    private(set) var lastDeltaWireBytes = 0
    let targetFPS: Int

    init(kbps: Int, targetFPS: Int) {
        self.targetKbps = min(80_000, max(1_500, kbps)); self.targetFPS = max(1, targetFPS)
    }
    mutating func updateTarget(kbps: Int) { targetKbps = min(80_000, max(1_500, kbps)) }
    var outstandingBytes: Int { flight.values.reduce(0) { $0 + $1.bytes } }
    var reservedBytes: Int { reservations.values.reduce(0, +) }
    var outstandingFrames: Int { flight.count }
    var reservedFrames: Int { reservations.count }

    func byteLimit(baseRTTms: Double) -> Int {
        let rtt = baseRTTms.isFinite ? min(500, max(30, baseRTTms)) : 150
        // Approximately baseline path flight + 100ms media queue, not the
        // stalled EWMA RTT (which would grow the queue when congestion grows).
        return min(256 * 1024, max(32 * 1024, Int(Double(targetKbps) * (rtt + 100) / 8)))
    }
    func oldestACKAgeMs(nowNs: UInt64) -> Double {
        guard let oldest = flight.values.map(\.atNs).min(), nowNs >= oldest else { return 0 }
        return Double(nowNs - oldest) / 1e6
    }
    mutating func reserve(nowNs: UInt64, baseRTTms: Double) -> Permit? {
        let baseline = baseRTTms.isFinite ? min(500, max(30, baseRTTms)) : 150
        let deadline = max(350, min(1500, baseline * 2 + 150))
        if !flight.isEmpty && oldestACKAgeMs(nowNs: nowNs) > deadline {
            rejectedForOldACK += 1; return nil
        }
        let average = Double(targetKbps) * 1000 / Double(targetFPS) / 8 + 92
        let prediction = max(1536, Int(ceil(max(average, smoothedWireBytes))))
        let limit = byteLimit(baseRTTms: baseline)
        // Bootstrap allows ONE oversized estimate if no frame/reservation is
        // outstanding. A real IDR overshoot is accounted, never silently dropped.
        if !flight.isEmpty || !reservations.isEmpty {
            guard outstandingBytes + reservedBytes + prediction <= limit else {
                rejectedForBytes += 1; return nil
            }
        }
        let permit = Permit(id: UUID()); reservations[permit.id] = prediction; return permit
    }
    mutating func cancel(_ permit: Permit) { reservations.removeValue(forKey: permit.id) }
    /// Call once with the final header+encrypted payload size, just BEFORE
    /// NWConnection.send. Once encoded, keep every P frame's reference chain.
    mutating func commit(_ permit: Permit, frameID: UInt64, wireBytes: Int, nowNs: UInt64, baseRTTms: Double, keyframe: Bool = false) -> Bool {
        guard reservations.removeValue(forKey: permit.id) != nil else { return false }
        return accountAlreadyEncoded(frameID: frameID, wireBytes: wireBytes, nowNs: nowNs, baseRTTms: baseRTTms, keyframe: keyframe)
    }
    /// Accounts frames admitted before WAN enforcement was enabled. Never drop
    /// those encoded P frames when a bitrate change turns on the low-rate gate.
    mutating func accountAlreadyEncoded(frameID: UInt64, wireBytes: Int, nowNs: UInt64, baseRTTms: Double, keyframe: Bool = false) -> Bool {
        guard frameID > lastFrameID, wireBytes > 0, wireBytes <= 4 * 1024 * 1024 + 128 else { return false }
        flight[frameID] = Flight(bytes: wireBytes, atNs: nowNs); lastFrameID = frameID
        // Predict a normal next delta frame from actual delta frames only. IDR
        // bytes remain fully in flight; they must be ACKed before freeing room.
        // A large refresh frame must not masquerade as every following P frame.
        if keyframe {
            accountedKeyframes += 1; lastKeyframeWireBytes = wireBytes
        } else {
            accountedDeltaFrames += 1; lastDeltaWireBytes = wireBytes
            smoothedWireBytes = smoothedWireBytes == 0 ? Double(wireBytes) : smoothedWireBytes * 0.875 + Double(wireBytes) * 0.125
        }
        if wireBytes > byteLimit(baseRTTms: baseRTTms) { oversizedFrames += 1 }
        return true
    }
    func canReserve(nowNs: UInt64, baseRTTms: Double) -> Bool {
        var copy = self; return copy.reserve(nowNs: nowNs, baseRTTms: baseRTTms) != nil
    }
    @discardableResult mutating func acknowledge(through frameID: UInt64) -> Bool {
        guard frameID >= lastACK, frameID <= lastFrameID else { rejectedACKs += 1; return false }
        lastACK = frameID; flight = flight.filter { $0.key > frameID }; return true
    }
    mutating func stop() { reservations.removeAll(); flight.removeAll() }
    func stats(baseRTTms: Double, nowNs: UInt64) -> [String: Any] {
        ["targetKbps": targetKbps, "byteLimit": byteLimit(baseRTTms: baseRTTms),
         "outstandingWireBytes": outstandingBytes, "reservedWireBytes": reservedBytes,
         "outstandingFrames": outstandingFrames, "reservedFrames": reservedFrames,
         "oldestACKAgeMs": oldestACKAgeMs(nowNs: nowNs), "rejectedForBytes": rejectedForBytes,
         "rejectedForOldACK": rejectedForOldACK, "oversizedFrames": oversizedFrames,
         "rejectedACKs": rejectedACKs, "predictedWireBytes": smoothedWireBytes,
         "accountedKeyframes": accountedKeyframes, "accountedDeltaFrames": accountedDeltaFrames,
         "lastKeyframeWireBytes": lastKeyframeWireBytes, "lastDeltaWireBytes": lastDeltaWireBytes]
    }
}
