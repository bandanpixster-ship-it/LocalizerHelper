//
//  ScanProgressCounter.swift
//  LocalizerHelper
//

import Foundation

/// Thread-safe counter that concurrent background tasks (e.g. `TaskGroup` children) can bump
/// as they each finish a unit of work, without hopping to the main actor on every increment.
/// The UI polls `current` on its own cadence instead.
nonisolated final class ScanProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
