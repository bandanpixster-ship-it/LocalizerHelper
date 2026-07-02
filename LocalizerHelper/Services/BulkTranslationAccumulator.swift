//
//  BulkTranslationAccumulator.swift
//  LocalizerHelper
//

import Foundation

/// Collects translated (key, language, value) results per source file as concurrent translation
/// tasks complete, and flushes each file to disk in one batched write — instead of one file
/// read+write per translated string, which would be slow (a `.xcstrings` file re-serializes its
/// entire JSON document per write) and unsafe under concurrency (concurrent per-key read-modify-
/// write calls against the same file can clobber each other's changes).
actor BulkTranslationAccumulator {
    private var pending: [URL: [(key: String, language: String, value: String)]] = [:]

    func add(file: URL, key: String, language: String, value: String) {
        pending[file, default: []].append((key, language, value))
    }

    /// Flushes files whose pending update count has reached `threshold`, writing each with a
    /// single call to `fileUpdater`. Returns the files that were flushed (for cache refresh).
    func flushIfNeeded(threshold: Int, fileUpdater: LocalizationFileUpdater) -> [URL] {
        var flushed: [URL] = []
        for (file, updates) in pending where updates.count >= threshold {
            if (try? fileUpdater.applyBulkUpdates(to: file, updates: updates)) != nil {
                flushed.append(file)
            }
            pending[file] = nil
        }
        return flushed
    }

    /// Flushes every remaining file regardless of how many updates it has queued — call this at
    /// the end of a run (or on cancellation) so nothing completed gets silently dropped.
    func flushAll(fileUpdater: LocalizationFileUpdater) -> [URL] {
        var flushed: [URL] = []
        for (file, updates) in pending where !updates.isEmpty {
            if (try? fileUpdater.applyBulkUpdates(to: file, updates: updates)) != nil {
                flushed.append(file)
            }
        }
        pending.removeAll()
        return flushed
    }
}
