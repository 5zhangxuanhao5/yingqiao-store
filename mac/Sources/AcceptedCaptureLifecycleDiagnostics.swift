import Foundation

final class CaptureLifecycleDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private let created = DispatchTime.now().uptimeNanoseconds
    private let instanceID = UUID().uuidString
    private var events: [[String: Any]] = []
    private var first: Set<String> = []
    private var state = "created"
    private var sdkStartCompleted = false
    private var firstComplete = false

    func record(_ phase: String, detail: [String: String] = [:], error: (any Error)? = nil) {
        let now = DispatchTime.now().uptimeNanoseconds
        var event: [String: Any] = ["phase": phase,
            "at": ISO8601DateFormatter().string(from: Date()), "monotonicNs": now,
            "sinceCreatedMs": Double(now - created) / 1e6, "detail": detail]
        if let error {
            let ns = error as NSError
            event["errorDomain"] = ns.domain; event["errorCode"] = ns.code
            event["errorDescription"] = ns.localizedDescription
            if let phase = ns.userInfo["phase"] as? String { event["operationPhase"] = phase }
            if let reason = ns.localizedFailureReason { event["errorFailureReason"] = reason }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                event["underlyingErrorDomain"] = underlying.domain
                event["underlyingErrorCode"] = underlying.code
                event["underlyingErrorDescription"] = underlying.localizedDescription
            }
        }
        lock.lock(); events.append(event)
        if events.count > 64 { events.removeFirst() }; lock.unlock()
    }

    func setState(_ value: String) { lock.lock(); state = value; lock.unlock() }
    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return state == "streaming" && sdkStartCompleted && firstComplete
    }
    func startCompleted() { lock.lock(); sdkStartCompleted = true; lock.unlock() }
    func recordFirst(_ phase: String, detail: [String: String] = [:]) {
        lock.lock(); let inserted = first.insert(phase).inserted
        if phase == "firstCompleteFrame" { firstComplete = true }; lock.unlock()
        if inserted { record(phase, detail: detail) }
    }
    func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["captureInstanceID": instanceID, "startupState": state, "sdkStartCompleted": sdkStartCompleted,
                "firstCompleteFrameReceived": firstComplete, "events": events]
    }
}
