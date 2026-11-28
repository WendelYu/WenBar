import Foundation
import WenBarCore

@MainActor
@Observable
final class CustomReminderStore {
    var reminders: [CustomReminder] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("WenBar", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("reminders.json")
        load()
    }

    func add(_ reminder: CustomReminder) {
        reminders.append(reminder)
        save()
    }

    func update(_ reminder: CustomReminder) {
        if let idx = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[idx] = reminder
        } else {
            reminders.append(reminder)
        }
        save()
    }

    func delete(id: UUID) {
        reminders.removeAll { $0.id == id }
        save()
    }

    func toggleCompletion(reminderID: UUID, occurrenceDateKey: String) {
        guard let idx = reminders.firstIndex(where: { $0.id == reminderID }) else { return }
        if reminders[idx].completedOccurrenceKeys.contains(occurrenceDateKey) {
            reminders[idx].completedOccurrenceKeys.remove(occurrenceDateKey)
        } else {
            reminders[idx].completedOccurrenceKeys.insert(occurrenceDateKey)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            reminders = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([CustomReminder].self, from: data) {
            reminders = decoded
        } else if let legacyDecoded = try? JSONDecoder().decode([CustomReminder].self, from: data) {
            reminders = legacyDecoded
        } else {
            reminders = []
        }
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(reminders) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
