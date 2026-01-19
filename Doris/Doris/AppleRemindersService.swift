//
//  AppleRemindersService.swift
//  Doris
//
//  Created by Adam Bell on 12/31/24.
//

import Foundation
import EventKit

// MARK: - Reminder Model

struct DorisReminder {
    let id: String
    let title: String
    let notes: String?
    let dueDate: Date?
    let isCompleted: Bool
    let priority: Int  // 0 = none, 1 = high, 5 = medium, 9 = low
    let list: String?
}

// MARK: - Apple Reminders Service

class AppleRemindersService {
    private let eventStore = EKEventStore()
    private var hasAccess = false
    
    init() {
        print("📝 RemindersService: Initializing")
        // Request access immediately on init
        Task {
            let granted = await requestAccess()
            print("📝 RemindersService: Initial access request - \(granted ? "granted" : "denied")")
        }
    }
    
    // MARK: - Authorization
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            hasAccess = granted
            print("📝 RemindersService: Access \(granted ? "granted" : "denied")")
            return granted
        } catch {
            print("📝 RemindersService: Access error: \(error)")
            return false
        }
    }
    
    private func ensureAccess() async -> Bool {
        if hasAccess { return true }
        return await requestAccess()
    }
    
    // MARK: - Get Reminders
    
    func getReminders(includeCompleted: Bool = false) async throws -> [DorisReminder] {
        guard await ensureAccess() else {
            throw RemindersError.accessDenied
        }
        
        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)
        
        let ekReminders = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(throwing: RemindersError.fetchFailed)
                }
            }
        }
        
        var results = ekReminders.map { mapToDorisReminder($0) }
        
        if !includeCompleted {
            results = results.filter { !$0.isCompleted }
        }
        
        // Sort by due date (nil dates at end)
        results.sort { r1, r2 in
            switch (r1.dueDate, r2.dueDate) {
            case (nil, nil): return r1.title < r2.title
            case (nil, _): return false
            case (_, nil): return true
            case (let d1?, let d2?): return d1 < d2
            }
        }
        
        print("📝 RemindersService: Found \(results.count) reminders")
        return results
    }
    
    func getReminders(forList listName: String, includeCompleted: Bool = false) async throws -> [DorisReminder] {
        guard await ensureAccess() else {
            throw RemindersError.accessDenied
        }
        
        guard let calendar = findCalendar(named: listName) else {
            throw RemindersError.listNotFound(listName)
        }
        
        let predicate = eventStore.predicateForReminders(in: [calendar])
        
        let ekReminders = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(throwing: RemindersError.fetchFailed)
                }
            }
        }
        
        var results = ekReminders.map { mapToDorisReminder($0) }
        
        if !includeCompleted {
            results = results.filter { !$0.isCompleted }
        }
        
        return results
    }
    
    func getDueReminders(within days: Int = 7) async throws -> [DorisReminder] {
        guard await ensureAccess() else {
            throw RemindersError.accessDenied
        }
        
        let calendars = eventStore.calendars(for: .reminder)
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate)!
        
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: endDate,
            calendars: calendars
        )
        
        let ekReminders = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(throwing: RemindersError.fetchFailed)
                }
            }
        }
        
        let results = ekReminders.map { mapToDorisReminder($0) }
        print("📝 RemindersService: Found \(results.count) reminders due within \(days) days")
        return results
    }
    
    // MARK: - Create Reminder
    
    func createReminder(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        listName: String? = nil,
        priority: Int = 0
    ) async throws -> String {
        guard await ensureAccess() else {
            throw RemindersError.accessDenied
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority
        
        // Set calendar (list)
        if let listName = listName, let calendar = findCalendar(named: listName) {
            reminder.calendar = calendar
        } else {
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }
        
        // Set due date with alarm
        if let dueDate = dueDate {
            let dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.dueDateComponents = dueDateComponents
            
            // Add alarm at due time
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
        }
        
        try eventStore.save(reminder, commit: true)
        print("📝 RemindersService: Created reminder '\(title)' with ID: \(reminder.calendarItemIdentifier)")
        return reminder.calendarItemIdentifier
    }
    
    // MARK: - Complete Reminder
    
    func completeReminder(id: String) async throws {
        guard await ensureAccess() else {
            throw RemindersError.accessDenied
        }
        
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.reminderNotFound(id)
        }
        
        reminder.isCompleted = true
        reminder.completionDate = Date()
        
        try eventStore.save(reminder, commit: true)
        print("📝 RemindersService: Completed reminder '\(reminder.title ?? "unknown")'")
    }
    
    func uncompleteReminder(id: String) async throws {
        guard await ensureAccess() else {
            throw RemindersError.accessDenied
        }
        
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.reminderNotFound(id)
        }
        
        reminder.isCompleted = false
        reminder.completionDate = nil
        
        try eventStore.save(reminder, commit: true)
        print("📝 RemindersService: Uncompleted reminder '\(reminder.title ?? "unknown")'")
    }
    
    // MARK: - Update Reminder
    
    func updateReminder(
        id: String,
        title: String? = nil,
        notes: String? = nil,
        dueDate: Date? = nil,
        priority: Int? = nil
    ) async throws {
        guard await ensureAccess() else {
            throw RemindersError.accessDenied
        }
        
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.reminderNotFound(id)
        }
        
        if let title = title {
            reminder.title = title
        }
        if let notes = notes {
            reminder.notes = notes
        }
        if let dueDate = dueDate {
            let dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.dueDateComponents = dueDateComponents
        }
        if let priority = priority {
            reminder.priority = priority
        }
        
        try eventStore.save(reminder, commit: true)
        print("📝 RemindersService: Updated reminder '\(reminder.title ?? "unknown")'")
    }
    
    // MARK: - Delete Reminder
    
    func deleteReminder(id: String) async throws {
        guard await ensureAccess() else {
            throw RemindersError.accessDenied
        }
        
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.reminderNotFound(id)
        }
        
        let title = reminder.title ?? "unknown"
        try eventStore.remove(reminder, commit: true)
        print("📝 RemindersService: Deleted reminder '\(title)'")
    }
    
    // MARK: - List Management
    
    func getLists() -> [String] {
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.map { $0.title }
    }
    
    // MARK: - Search
    
    func searchReminders(matching query: String) async throws -> [DorisReminder] {
        let allReminders = try await getReminders(includeCompleted: false)
        let lowercaseQuery = query.lowercased()
        
        return allReminders.filter { reminder in
            reminder.title.lowercased().contains(lowercaseQuery) ||
            (reminder.notes?.lowercased().contains(lowercaseQuery) ?? false)
        }
    }
    
    // MARK: - Helpers
    
    private func findCalendar(named name: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.first { $0.title.lowercased() == name.lowercased() }
    }
    
    private func mapToDorisReminder(_ ekReminder: EKReminder) -> DorisReminder {
        var dueDate: Date? = nil
        if let components = ekReminder.dueDateComponents {
            dueDate = Calendar.current.date(from: components)
        }
        
        return DorisReminder(
            id: ekReminder.calendarItemIdentifier,
            title: ekReminder.title ?? "Untitled",
            notes: ekReminder.notes,
            dueDate: dueDate,
            isCompleted: ekReminder.isCompleted,
            priority: ekReminder.priority,
            list: ekReminder.calendar?.title
        )
    }
}

// MARK: - Errors

enum RemindersError: LocalizedError {
    case accessDenied
    case fetchFailed
    case listNotFound(String)
    case reminderNotFound(String)
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Reminders access denied. Enable it in System Settings > Privacy & Security > Reminders."
        case .fetchFailed:
            return "Failed to fetch reminders"
        case .listNotFound(let name):
            return "Reminder list '\(name)' not found"
        case .reminderNotFound(let id):
            return "Reminder not found with ID: \(id)"
        case .saveFailed(let reason):
            return "Failed to save reminder: \(reason)"
        }
    }
}
