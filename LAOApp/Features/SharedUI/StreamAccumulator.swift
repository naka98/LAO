import Foundation

// MARK: - Stream Accumulator

/// Thread-safe buffer that accumulates streaming CLI output chunks
/// and returns the full snapshot after each append.
final class StreamAccumulator: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()

    func append(_ chunk: String) -> String {
        lock.lock()
        buffer += chunk
        let snapshot = buffer
        lock.unlock()
        return snapshot
    }
}

// MARK: - Throttled MainActor Updater

/// Throttles MainActor UI updates to reduce contention during parallel streaming.
final class ThrottledMainActorUpdater: @unchecked Sendable {
    private let interval: TimeInterval
    private var lastFireTime: Date = .distantPast
    private var pendingValue: String?
    private var scheduledTask: Task<Void, Never>?
    private let lock = NSLock()

    init(interval: TimeInterval = 0.15) { self.interval = interval }

    func update(_ value: String, apply: @MainActor @Sendable @escaping (String) -> Void) {
        let (fireValue, needsSchedule) = lock.withLock { () -> (String?, Bool) in
            pendingValue = value
            let elapsed = Date().timeIntervalSince(lastFireTime)
            let shouldFire = elapsed >= interval
            if shouldFire { lastFireTime = Date() }
            let needs = !shouldFire && scheduledTask == nil
            return (shouldFire ? value : nil, needs)
        }

        if let v = fireValue {
            Task { @MainActor in apply(v) }
        } else if needsSchedule {
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(self?.interval ?? 0.15 * 1000)))
                guard let self else { return }
                let val = self.lock.withLock { () -> String? in
                    let v = self.pendingValue
                    self.pendingValue = nil
                    self.lastFireTime = Date()
                    self.scheduledTask = nil
                    return v
                }
                if let v = val { apply(v) }
            }
            lock.withLock { scheduledTask = task }
        }
    }

    /// Flush any pending value immediately on MainActor.
    func flush(apply: @MainActor @Sendable @escaping (String) -> Void) {
        let val = lock.withLock { () -> String? in
            scheduledTask?.cancel()
            scheduledTask = nil
            let v = pendingValue
            pendingValue = nil
            return v
        }
        if let v = val {
            Task { @MainActor in apply(v) }
        }
    }
}
