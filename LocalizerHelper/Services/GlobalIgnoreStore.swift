//
//  GlobalIgnoreStore.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 22/06/26.
//


import Foundation
import Combine

final class GlobalIgnoreStore: ObservableObject {
    static let shared = GlobalIgnoreStore()

    @Published private(set) var entries: [GlobalIgnoreEntry] = []

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LocalizerHelper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("global_ignores.json")
    }

    init() { load() }

    func isIgnored(key: String, language: String) -> Bool {
        entries.contains { $0.key == key && ($0.language == nil || $0.language == language) }
    }

    func add(key: String, language: String?) {
        guard !entries.contains(where: { $0.key == key && $0.language == language }) else { return }
        entries.append(GlobalIgnoreEntry(key: key, language: language))
        save()
    }

    func remove(key: String, language: String?) {
        entries.removeAll { $0.key == key && $0.language == language }
        save()
    }

    func removeAll() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([GlobalIgnoreEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
