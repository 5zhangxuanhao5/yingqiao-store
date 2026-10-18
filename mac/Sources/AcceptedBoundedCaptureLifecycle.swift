import Foundation

/// Bounds only the asynchronous public callback. It does not claim to cancel an
/// operation inside WindowServer; late success must be cleaned up by its owner.
enum CaptureLifecycleError: Error, Sendable, Equatable, CustomNSError {
    case timeout(phase: String)
    case superseded
    case alreadyStopped

    static var errorDomain: String { "EdgeLinkCaptureLifecycle" }
    var errorCode: Int {
        switch self { case .timeout: return 1; case .superseded: return 2; case .alreadyStopped: return 3 }
    }
    var errorUserInfo: [String: Any] {
        switch self {
        case .timeout(let phase): return [NSLocalizedDescriptionKey: "捕获阶段超时：\(phase)", "phase": phase]
        case .superseded: return [NSLocalizedDescriptionKey: "捕获会话已经结束或被替换"]
        case .alreadyStopped: return [NSLocalizedDescriptionKey: "此捕获实例已结束，请创建新会话"]
        }
    }
}

private protocol CapturePendingOperation: AnyObject, Sendable {
    func cancel(_ error: any Error)
}

/// A one-shot continuation and its timer. The SDK completion holds this small
/// object, never a NativeCapture, virtual display, encoder, or stream owner.
private final class CaptureCallbackGate<Value: Sendable>: CapturePendingOperation, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var pendingResult: Result<Value, any Error>?
    private var finished = false
    private var terminalWasFailure = false
    private var timer: DispatchSourceTimer?
    private var launched = false
    private var lateSuccessHandled = false
    private let onFinished: @Sendable () -> Void
    private let onLateSuccess: (@Sendable () -> Void)?

    init(onFinished: @escaping @Sendable () -> Void, onLateSuccess: (@Sendable () -> Void)?) {
        self.onFinished = onFinished; self.onLateSuccess = onLateSuccess
    }

    func install(_ continuation: CheckedContinuation<Value, any Error>, timeout: TimeInterval,
                 phase: String, timerQueue: DispatchQueue) {
        lock.lock()
        if finished, let result = pendingResult {
            pendingResult = nil; lock.unlock(); onFinished(); continuation.resume(with: result); return
        }
        self.continuation = continuation
        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        source.schedule(deadline: .now() + max(0.001, timeout))
        source.setEventHandler { [weak self] in self?.cancel(CaptureLifecycleError.timeout(phase: phase)) }
        timer = source
        source.resume()
        lock.unlock()
    }

    func claimLaunch() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !finished, !launched else { return false }
        launched = true; return true
    }

    func complete(_ result: Result<Value, any Error>) {
        finish(result, isSDKCallback: true)
    }

    func cancel(_ error: any Error) { finish(.failure(error), isSDKCallback: false) }

    private func finish(_ result: Result<Value, any Error>, isSDKCallback: Bool) {
        lock.lock()
        if finished {
            // A duplicate normal success is harmless. Cleanup is needed only
            // after timeout/cancellation, and only once for this old resource.
            let cleanup: (@Sendable () -> Void)?
            if isSDKCallback, case .success = result, terminalWasFailure,
               launched, !lateSuccessHandled {
                lateSuccessHandled = true; cleanup = onLateSuccess
            } else { cleanup = nil }
            lock.unlock(); cleanup?(); return
        }
        finished = true
        if case .failure = result { terminalWasFailure = true }
        let saved = continuation; continuation = nil
        if saved == nil { pendingResult = result }
        let source = timer; timer = nil
        lock.unlock()
        source?.setEventHandler {}; source?.cancel()
        onFinished()
        saved?.resume(with: result)
    }
}

/// Generations are per capture instance. Retiring a generation releases every
/// app-owned wait immediately, including enumeration and first-frame waits.
final class BoundedCaptureLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var operations: [UUID: any CapturePendingOperation] = [:]
    private let controlQueue: DispatchQueue
    private let deadlineQueue: DispatchQueue

    init(controlQueue: DispatchQueue = DispatchQueue(label: "edgelink.capture.control", qos: .userInitiated)) {
        self.controlQueue = controlQueue
        self.deadlineQueue = DispatchQueue(label: "edgelink.capture.deadlines", qos: .utility)
    }

    @discardableResult func nextGeneration() -> UInt64 {
        lock.lock()
        generation &+= 1
        let value = generation, pending = Array(operations.values)
        operations.removeAll()
        lock.unlock()
        pending.forEach { $0.cancel(CaptureLifecycleError.superseded) }
        return value
    }

    func isCurrent(_ value: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return value == generation
    }

    var pendingCount: Int { lock.lock(); defer { lock.unlock() }; return operations.count }

    private func register(_ operation: any CapturePendingOperation, id: UUID, generation value: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value == generation else { return false }
        operations[id] = operation; return true
    }
    private func forget(_ id: UUID) { lock.lock(); operations.removeValue(forKey: id); lock.unlock() }

    func run<Value: Sendable>(generation: UInt64, phase: String, timeout: TimeInterval,
                             onLateSuccess: (@Sendable () -> Void)? = nil,
                             start: @escaping @Sendable (@escaping @Sendable (Result<Value, any Error>) -> Void) -> Void) async throws -> Value {
        let id = UUID()
        let gate = CaptureCallbackGate<Value>(onFinished: { [weak self] in self?.forget(id) }, onLateSuccess: onLateSuccess)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard register(gate, id: id, generation: generation) else {
                    continuation.resume(throwing: CaptureLifecycleError.superseded); return
                }
                gate.install(continuation, timeout: timeout, phase: phase, timerQueue: deadlineQueue)
                // Cancellation before this block runs suppresses the SDK call.
                // A concurrent cancellation after launch uses late cleanup.
                controlQueue.async {
                    guard gate.claimLaunch() else { return }
                    start { result in gate.complete(result) }
                }
            }
        } onCancel: { gate.cancel(CancellationError()) }
    }
}

/// Thread-safe single-assignment event: a first frame may arrive before the SDK
/// start completion. Its result stays available to a later bounded waiter.
final class CaptureOneShotEvent<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, any Error>?
    private var callback: (@Sendable (Result<Value, any Error>) -> Void)?

    func complete(_ value: Result<Value, any Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value; let handler = callback; callback = nil
        lock.unlock(); handler?(value)
    }
    func subscribe(_ handler: @escaping @Sendable (Result<Value, any Error>) -> Void) {
        lock.lock()
        if let result { lock.unlock(); handler(result); return }
        callback = handler; lock.unlock()
    }
    func clearSubscriber() { lock.lock(); callback = nil; lock.unlock() }
}
