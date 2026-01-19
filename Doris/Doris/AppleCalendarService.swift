//
//  AppleCalendarService.swift
//  Doris
//
//  Created by Adam Bell on 12/31/25.
//

import Foundation
import EventKit

class AppleCalendarService {
    private let eventStore = EKEventStore()
    private var hasAccess = false
    private let allowedCalendarName = "Indestructible"  // Only use this calendar
    
    init() {
        print("🗓️ AppleCalendar: Initialized (filtering to '\(allowedCalendarName)' only)")
    }
    
    // MARK: - Authorization
    
    func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .authorized, .fullAccess:
            hasAccess = true
            print("🟢 AppleCalendar: Already authorized")
            return
            
        case .notDetermined:
            // Request access
            if #available(macOS 14.0, *) {
                hasAccess = try await eventStore.requestFullAccessToEvents()
            } else {
                hasAccess = try await eventStore.requestAccess(to: .event)
            }
            
            if hasAccess {
                print("🟢 AppleCalendar: Access granted")
            } else {
                print("🔴 AppleCalendar: Access denied by user")
                throw CalendarServiceError.accessDenied
            }
            
        case .denied, .restricted:
            print("🔴 AppleCalendar: Access denied or restricted")
            throw CalendarServiceError.accessDenied
            
        case .writeOnly:
            print("🔴 AppleCalendar: Write-only access, need full access")
            throw CalendarServiceError.accessDenied
            
        @unknown default:
            throw CalendarServiceError.accessDenied
        }
    }
    
    private func ensureAccess() async throws {
        if !hasAccess {
            try await requestAccess()
        }
    }
    
    // MARK: - Fetch Events
    
    func getTodaysEvents() async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return try await getEvents(from: startOfDay, to: endOfDay)
    }
    
    private func getAllowedCalendars() -> [EKCalendar]? {
        let calendars = eventStore.calendars(for: .event).filter { $0.title == allowedCalendarName }
        if calendars.isEmpty {
            print("⚠️ AppleCalendar: Calendar '\(allowedCalendarName)' not found!")
            return nil
        }
        return calendars
    }
    
    func getEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        try await ensureAccess()
        
        // Only query the allowed calendar
        let calendars = getAllowedCalendars()
        
        // Debug logging
        let allCalendars = eventStore.calendars(for: .event)
        print("🗓️ AppleCalendar: All calendars: \(allCalendars.map { $0.title })")
        print("🗓️ AppleCalendar: Using calendar: \(calendars?.map { $0.title } ?? ["none"])")
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let ekEvents = eventStore.events(matching: predicate)
        
        // Sort by start date
        let sortedEvents = ekEvents.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        
        print("🗓️ AppleCalendar: Found \(sortedEvents.count) events from \(startDate) to \(endDate)")
        
        return sortedEvents.map { CalendarEvent(from: $0) }
    }
    
    func getNextUpcomingEvent() async throws -> CalendarEvent? {
        try await ensureAccess()
        
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .month, value: 1, to: now)!
        
        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
        
        // Get the first event that starts after now
        let upcoming = ekEvents
            .filter { ($0.startDate ?? Date.distantPast) > now }
            .sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
            .first
        
        return upcoming.map { CalendarEvent(from: $0) }
    }
    
    // MARK: - Raw Data for Claude
    
    func getEventsRawData(from startDate: Date, to endDate: Date) async throws -> String {
        let events = try await getEvents(from: startDate, to: endDate)
        
        guard !events.isEmpty else {
            return "No events found."
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMM d"
        
        var result = ""
        for event in events {
            result += "- \(event.title) [id: \(event.id)]"
            
            if let start = event.startTime {
                if event.isAllDay {
                    result += " (all day on \(dayFormatter.string(from: start)))"
                } else {
                    result += " on \(formatter.string(from: start))"
                }
            }
            
            if let location = event.location, !location.isEmpty {
                result += " at \(location)"
            }
            
            if let notes = event.description, !notes.isEmpty {
                // Truncate long notes
                let truncated = notes.count > 100 ? String(notes.prefix(100)) + "..." : notes
                result += " - Note: \(truncated)"
            }
            
            result += "\n"
        }
        
        return result
    }
    
    // MARK: - Create Events
    
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        notes: String? = nil,
        isAllDay: Bool = false,
        calendarName: String? = nil
    ) async throws -> String {
        try await ensureAccess()
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        
        // Find calendar - use specified name or default
        if let calendarName = calendarName {
            if let calendar = eventStore.calendars(for: .event).first(where: { $0.title == calendarName }) {
                event.calendar = calendar
            } else {
                print("⚠️ AppleCalendar: Calendar '\(calendarName)' not found, using default")
                event.calendar = eventStore.defaultCalendarForNewEvents
            }
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }
        
        try eventStore.save(event, span: .thisEvent)
        
        print("🟢 AppleCalendar: Created event '\(title)' with ID: \(event.eventIdentifier ?? "unknown")")
        return event.eventIdentifier ?? "unknown"
    }
    
    // Convenience method for quick event creation
    func createQuickEvent(
        title: String,
        date: Date,
        durationMinutes: Int = 60,
        location: String? = nil
    ) async throws -> String {
        let endDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: date)!
        return try await createEvent(
            title: title,
            startDate: date,
            endDate: endDate,
            location: location
        )
    }
    
    // MARK: - Update Events
    
    func updateEvent(
        eventId: String,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        location: String? = nil,
        notes: String? = nil
    ) async throws {
        try await ensureAccess()
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarServiceError.eventNotFound
        }
        
        if let title = title {
            event.title = title
        }
        if let startDate = startDate {
            event.startDate = startDate
        }
        if let endDate = endDate {
            event.endDate = endDate
        }
        if let location = location {
            event.location = location
        }
        if let notes = notes {
            event.notes = notes
        }
        
        try eventStore.save(event, span: .thisEvent)
        print("🟢 AppleCalendar: Updated event '\(event.title ?? "Untitled")'")
    }
    
    // Reschedule convenience method
    func rescheduleEvent(
        eventId: String,
        newStartDate: Date,
        newEndDate: Date? = nil
    ) async throws {
        try await ensureAccess()
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarServiceError.eventNotFound
        }
        
        // Calculate duration if new end date not provided
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let endDate = newEndDate ?? newStartDate.addingTimeInterval(duration)
        
        event.startDate = newStartDate
        event.endDate = endDate
        
        try eventStore.save(event, span: .thisEvent)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
        print("🟢 AppleCalendar: Rescheduled '\(event.title ?? "Untitled")' to \(formatter.string(from: newStartDate))")
    }
    
    // MARK: - Delete Events
    
    func deleteEvent(eventId: String) async throws {
        try await ensureAccess()
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarServiceError.eventNotFound
        }
        
        let title = event.title ?? "Untitled"
        try eventStore.remove(event, span: .thisEvent)
        print("🟢 AppleCalendar: Deleted event '\(title)'")
    }
    
    // MARK: - Availability
    
    func checkAvailability(from startDate: Date, to endDate: Date) async throws -> (isFree: Bool, conflicts: [CalendarEvent]) {
        try await ensureAccess()
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
        
        // Filter out all-day events for conflict checking (they usually don't block time)
        let conflicts = ekEvents
            .filter { !$0.isAllDay }
            .map { CalendarEvent(from: $0) }
        
        return (conflicts.isEmpty, conflicts)
    }
    
    func findFreeTime(on date: Date, durationMinutes: Int = 60, startHour: Int = 9, endHour: Int = 17) async throws -> [Date] {
        try await ensureAccess()
        
        let calendar = Calendar.current
        var startOfDay = calendar.startOfDay(for: date)
        startOfDay = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: startOfDay)!
        var endOfDay = calendar.startOfDay(for: date)
        endOfDay = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: endOfDay)!
        
        // Get all events for the day
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        
        var freeSlots: [Date] = []
        var currentTime = startOfDay
        let duration = TimeInterval(durationMinutes * 60)
        
        for event in ekEvents {
            guard let eventStart = event.startDate, let eventEnd = event.endDate else { continue }
            
            // Check if there's a free slot before this event
            if currentTime.addingTimeInterval(duration) <= eventStart {
                freeSlots.append(currentTime)
            }
            
            // Move current time to after this event
            if eventEnd > currentTime {
                currentTime = eventEnd
            }
        }
        
        // Check if there's a free slot after the last event
        if currentTime.addingTimeInterval(duration) <= endOfDay {
            freeSlots.append(currentTime)
        }
        
        return freeSlots
    }
    
    // MARK: - Search
    
    func searchEvents(matching searchText: String, from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [CalendarEvent] {
        try await ensureAccess()
        
        let start = startDate ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let end = endDate ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
        
        let searchLower = searchText.lowercased()
        let filtered = ekEvents.filter { event in
            let titleMatch = event.title?.lowercased().contains(searchLower) ?? false
            let locationMatch = event.location?.lowercased().contains(searchLower) ?? false
            let notesMatch = event.notes?.lowercased().contains(searchLower) ?? false
            return titleMatch || locationMatch || notesMatch
        }
        
        return filtered
            .sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
            .map { CalendarEvent(from: $0) }
    }
    
    // MARK: - List Calendars
    
    func listCalendars() async throws -> [(name: String, id: String)] {
        try await ensureAccess()
        
        return eventStore.calendars(for: .event).map { ($0.title, $0.calendarIdentifier) }
    }
}

// MARK: - Models

extension CalendarEvent {
    init(from ekEvent: EKEvent) {
        self.init(
            id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: ekEvent.title ?? "Untitled",
            startTime: ekEvent.startDate,
            endTime: ekEvent.endDate,
            location: ekEvent.location,
            description: ekEvent.notes,
            isAllDay: ekEvent.isAllDay
        )
    }
}

enum CalendarServiceError: LocalizedError {
    case accessDenied
    case noEvents
    case eventNotFound
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access denied. Please enable in System Settings > Privacy & Security > Calendars."
        case .noEvents:
            return "No events found."
        case .eventNotFound:
            return "Event not found."
        }
    }
}
