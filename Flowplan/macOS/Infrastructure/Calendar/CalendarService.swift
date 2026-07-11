//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import EventKit
import OSLog

/// Bridges task due dates to the system Calendar via EventKit.
///
/// The task → event mapping lives in a JSON file in Application Support, deliberately **not** in the
/// synced SwiftData model: an `EKEvent` identifier is local to a device's calendar database and
/// meaningless on another device, so syncing it would be wrong. Each device manages its own calendar
/// mirror of a task. (It's app data, not a preference, so it also doesn't belong in `UserDefaults`.)
@MainActor
final class CalendarService {

    static let shared = CalendarService()

    private let store = EKEventStore()
    private let log = Logger(subsystem: "io.apparata.Flowplan", category: "Calendar")

    /// In-memory cache of task UUID string → event identifier, persisted to disk on change.
    private var eventIDsByTask: [String: String]
    private let mappingURL: URL

    private init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mappingURL = directory.appending(path: "CalendarEvents.json")
        if let data = try? Data(contentsOf: mappingURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            eventIDsByTask = decoded
        } else {
            eventIDsByTask = [:]
        }
    }

    enum CalendarError: LocalizedError {
        case accessDenied
        case noWritableCalendar

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "Flowplan doesn't have permission to access Calendar. Enable it in System Settings ▸ Privacy & Security ▸ Calendars."
            case .noWritableCalendar:
                "There's no writable calendar to add the event to."
            }
        }
    }

    /// Requests full calendar access (needed so we can look up, update, and remove events we created).
    func requestAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            log.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Whether this device has a calendar event mirroring the task.
    func hasEvent(for task: PlanTask) -> Bool {
        guard let id = eventID(for: task.id) else { return false }
        return store.event(withIdentifier: id) != nil
    }

    /// Creates or updates an all-day event on the task's due date. Requires prior access.
    func addOrUpdateEvent(for task: PlanTask) throws {
        guard let dueDate = task.dueDate else { return }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarError.accessDenied
        }

        let event: EKEvent
        if let id = eventID(for: task.id), let existing = store.event(withIdentifier: id) {
            event = existing
        } else {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw CalendarError.noWritableCalendar
            }
            event = EKEvent(eventStore: store)
            event.calendar = calendar
        }

        event.title = task.title.isEmpty ? "Flowplan task #\(task.number)" : task.title
        event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: dueDate)
        event.endDate = event.startDate
        event.notes = "Flowplan task #\(task.number)"

        try store.save(event, span: .thisEvent, commit: true)
        setEventID(event.eventIdentifier, for: task.id)
    }

    /// Removes the task's calendar event, if any.
    func removeEvent(for task: PlanTask) throws {
        defer { setEventID(nil, for: task.id) }
        guard let id = eventID(for: task.id), let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    /// Removes mapping entries for tasks that no longer exist, keeping the file from accumulating
    /// orphans as tasks are deleted. Safe to call opportunistically.
    func pruneOrphans(livingTaskIDs: Set<UUID>) {
        let living = Set(livingTaskIDs.map(\.uuidString))
        let before = eventIDsByTask.count
        eventIDsByTask = eventIDsByTask.filter { living.contains($0.key) }
        if eventIDsByTask.count != before { persist() }
    }

    // MARK: - Per-device task → event mapping (JSON in Application Support)

    private func eventID(for taskID: UUID) -> String? {
        eventIDsByTask[taskID.uuidString]
    }

    private func setEventID(_ id: String?, for taskID: UUID) {
        if let id {
            eventIDsByTask[taskID.uuidString] = id
        } else {
            eventIDsByTask.removeValue(forKey: taskID.uuidString)
        }
        persist()
    }

    private func persist() {
        do {
            try JSONEncoder().encode(eventIDsByTask).write(to: mappingURL, options: .atomic)
        } catch {
            log.error("Failed to persist calendar mapping: \(error.localizedDescription, privacy: .public)")
        }
    }
}
