import Foundation
import AppFeedbackCore

/// Collects events for assertions. `record` is `nonisolated` and can be called
/// from any context, so the storage is lock-guarded rather than actor-isolated —
/// exactly the shape a real adopter's sink has to be.
final class RecordingAnalytics: FeedbackAnalytics, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FeedbackEvent] = []

    var events: [FeedbackEvent] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    var names: [String] { events.map(\.name) }

    func record(_ event: FeedbackEvent) {
        lock.lock(); defer { lock.unlock() }
        storage.append(event)
    }
}
