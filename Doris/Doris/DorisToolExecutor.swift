//
//  DorisToolExecutor.swift
//  Doris
//
//  Created by Adam Bell on 12/31/25.
//

import Foundation

class DorisToolExecutor: ToolExecutor {
    private let gmailService: GmailService
    private let calendarService: AppleCalendarService
    private let locationService: LocationService
    private let remindersService: AppleRemindersService
    private let contactsService: ContactsService
    private let memoryStore: MemoryStore

    init(gmailService: GmailService, calendarService: AppleCalendarService, locationService: LocationService, remindersService: AppleRemindersService, contactsService: ContactsService, memoryStore: MemoryStore) {
        self.gmailService = gmailService
        self.calendarService = calendarService
        self.locationService = locationService
        self.remindersService = remindersService
        self.contactsService = contactsService
        self.memoryStore = memoryStore
    }
    
    func execute(toolName: String, input: [String: Any]) async -> String {
        print("🔧 ToolExecutor: Executing \(toolName)")
        
        do {
            switch toolName {
            // MARK: - Gmail Tools
            case "gmail_search":
                return try await executeGmailSearch(input: input)
            case "gmail_send":
                return try await executeGmailSend(input: input)
            case "gmail_reply":
                return try await executeGmailReply(input: input)
            case "gmail_label":
                return try await executeGmailLabel(input: input)
            case "gmail_archive":
                return try await executeGmailArchive(input: input)
            case "gmail_trash":
                return try await executeGmailTrash(input: input)
            case "gmail_mark_read":
                return try await executeGmailMarkRead(input: input)
                
            // MARK: - Calendar Tools
            case "calendar_get_events":
                return try await executeCalendarGetEvents(input: input)
            case "calendar_create_event":
                return try await executeCalendarCreateEvent(input: input)
            case "calendar_update_event":
                return try await executeCalendarUpdateEvent(input: input)
            case "calendar_delete_event":
                return try await executeCalendarDeleteEvent(input: input)
            case "calendar_check_availability":
                return try await executeCalendarCheckAvailability(input: input)
            case "calendar_find_free_time":
                return try await executeCalendarFindFreeTime(input: input)
            case "calendar_search":
                return try await executeCalendarSearch(input: input)
                
            // MARK: - Location Tools
            case "location_get_current":
                return try await executeLocationGetCurrent()
            case "location_distance_to":
                return try await executeLocationDistanceTo(input: input)
            case "location_am_i_at":
                return try await executeLocationAmIAt()
                
            // MARK: - Reminder Tools
            case "reminders_get":
                return try await executeRemindersGet(input: input)
            case "reminders_get_due":
                return try await executeRemindersGetDue(input: input)
            case "reminders_create":
                return try await executeRemindersCreate(input: input)
            case "reminders_complete":
                return try await executeRemindersComplete(input: input)
            case "reminders_delete":
                return try await executeRemindersDelete(input: input)
            case "reminders_search":
                return try await executeRemindersSearch(input: input)
            case "reminders_get_lists":
                return executeRemindersGetLists()

            // MARK: - Memory Tools
            case "memory_add":
                return executeMemoryAdd(input: input)
            case "memory_search":
                return executeMemorySearch(input: input)
            case "memory_get_about":
                return executeMemoryGetAbout(input: input)
            case "memory_update":
                return executeMemoryUpdate(input: input)
            case "memory_delete":
                return executeMemoryDelete(input: input)
            case "memory_list_subjects":
                return executeMemoryListSubjects()
            case "memory_correct":
                return executeMemoryCorrect(input: input)

            // MARK: - Contact Tools
            case "contacts_lookup":
                return try await executeContactsLookup(input: input)
            case "contacts_find_email":
                return try await executeContactsFindEmail(input: input)
            case "contacts_find_phone":
                return try await executeContactsFindPhone(input: input)
            case "contacts_create":
                return try await executeContactsCreate(input: input)
            case "contacts_search_by_email":
                return try await executeContactsSearchByEmail(input: input)
            case "contacts_search_by_phone":
                return try await executeContactsSearchByPhone(input: input)
            case "contacts_search_by_organization":
                return try await executeContactsSearchByOrganization(input: input)
            case "contacts_list":
                return try await executeContactsList(input: input)
            case "contacts_get_birthdays":
                return try await executeContactsGetBirthdays(input: input)
            case "contacts_get_address":
                return try await executeContactsGetAddress(input: input)
            case "contacts_get_details":
                return try await executeContactsGetDetails(input: input)

            default:
                return "Error: Unknown tool '\(toolName)'"
            }
        } catch {
            print("🔴 ToolExecutor: Error executing \(toolName): \(error)")
            return "Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Gmail Implementations
    
    private func executeGmailSearch(input: [String: Any]) async throws -> String {
        guard let query = input["query"] as? String else {
            return "Error: Missing 'query' parameter"
        }
        let limit = input["limit"] as? Int ?? 10
        
        let messages = try await gmailService.searchMessages(query: query, limit: limit)
        
        if messages.isEmpty {
            return "No emails found matching '\(query)'"
        }
        
        var result = "Found \(messages.count) email(s):\n"
        for msg in messages {
            result += "- ID: \(msg.id) | From: \(msg.sender) | Subject: \(msg.subject) | Date: \(formatDate(msg.date))\n"
        }
        return result
    }
    
    private func executeGmailSend(input: [String: Any]) async throws -> String {
        guard let to = input["to"] as? String,
              let subject = input["subject"] as? String,
              let body = input["body"] as? String else {
            return "Error: Missing required parameters (to, subject, body)"
        }
        
        let messageId = try await gmailService.sendEmail(to: to, subject: subject, body: body)
        return "Email sent successfully to \(to). Message ID: \(messageId)"
    }
    
    private func executeGmailReply(input: [String: Any]) async throws -> String {
        guard let messageId = input["message_id"] as? String,
              let body = input["body"] as? String else {
            return "Error: Missing required parameters (message_id, body)"
        }
        
        let newMessageId = try await gmailService.replyToEmail(messageId: messageId, body: body)
        return "Reply sent successfully. Message ID: \(newMessageId)"
    }
    
    private func executeGmailLabel(input: [String: Any]) async throws -> String {
        guard let messageId = input["message_id"] as? String,
              let label = input["label"] as? String,
              let action = input["action"] as? String else {
            return "Error: Missing required parameters (message_id, label, action)"
        }
        
        if action == "add" {
            try await gmailService.addLabel(messageId: messageId, labelName: label)
            return "Label '\(label)' added to message"
        } else if action == "remove" {
            try await gmailService.removeLabel(messageId: messageId, labelName: label)
            return "Label '\(label)' removed from message"
        } else {
            return "Error: Invalid action '\(action)'. Use 'add' or 'remove'"
        }
    }
    
    private func executeGmailArchive(input: [String: Any]) async throws -> String {
        guard let messageId = input["message_id"] as? String else {
            return "Error: Missing 'message_id' parameter"
        }
        
        try await gmailService.archiveMessage(messageId: messageId)
        return "Message archived successfully"
    }
    
    private func executeGmailTrash(input: [String: Any]) async throws -> String {
        guard let messageId = input["message_id"] as? String else {
            return "Error: Missing 'message_id' parameter"
        }
        
        try await gmailService.trashMessage(messageId: messageId)
        return "Message moved to trash"
    }
    
    private func executeGmailMarkRead(input: [String: Any]) async throws -> String {
        guard let messageId = input["message_id"] as? String,
              let read = input["read"] as? Bool else {
            return "Error: Missing required parameters (message_id, read)"
        }
        
        if read {
            try await gmailService.markAsRead(messageId: messageId)
            return "Message marked as read"
        } else {
            try await gmailService.markAsUnread(messageId: messageId)
            return "Message marked as unread"
        }
    }
    
    // MARK: - Calendar Implementations
    
    private func executeCalendarGetEvents(input: [String: Any]) async throws -> String {
        guard let startDateStr = input["start_date"] as? String,
              let endDateStr = input["end_date"] as? String else {
            return "Error: Missing required parameters (start_date, end_date)"
        }
        
        print("🗓️ executeCalendarGetEvents: start_date='\(startDateStr)', end_date='\(endDateStr)'")
        
        guard let startDate = parseDate(startDateStr) else {
            return "Error: Could not parse start_date '\(startDateStr)'"
        }
        
        let calendar = Calendar.current
        
        // Get start of day in LOCAL timezone
        let startOfDay = calendar.startOfDay(for: startDate)
        
        // Get end of day in LOCAL timezone (23:59:59)
        var endDate: Date
        if let parsed = parseDate(endDateStr) {
            var components = calendar.dateComponents([.year, .month, .day], from: parsed)
            components.hour = 23
            components.minute = 59
            components.second = 59
            endDate = calendar.date(from: components) ?? parsed
        } else {
            var components = calendar.dateComponents([.year, .month, .day], from: startDate)
            components.hour = 23
            components.minute = 59
            components.second = 59
            endDate = calendar.date(from: components) ?? startDate
        }
        
        print("🗓️ executeCalendarGetEvents: LOCAL startOfDay=\(startOfDay), endDate=\(endDate)")
        
        let rawData = try await calendarService.getEventsRawData(from: startOfDay, to: endDate)
        return rawData
    }
    
    private func executeCalendarCreateEvent(input: [String: Any]) async throws -> String {
        guard let title = input["title"] as? String,
              let startTimeStr = input["start_time"] as? String,
              let endTimeStr = input["end_time"] as? String else {
            return "Error: Missing required parameters (title, start_time, end_time)"
        }
        
        guard let startDate = parseDateTime(startTimeStr),
              let endDate = parseDateTime(endTimeStr) else {
            return "Error: Invalid date format. Use ISO format (YYYY-MM-DDTHH:MM:SS)"
        }
        
        let location = input["location"] as? String
        let notes = input["notes"] as? String
        let isAllDay = input["all_day"] as? Bool ?? false
        
        let eventId = try await calendarService.createEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: location,
            notes: notes,
            isAllDay: isAllDay
        )
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return "Created event '\(title)' on \(formatter.string(from: startDate)). Event ID: \(eventId)"
    }
    
    private func executeCalendarUpdateEvent(input: [String: Any]) async throws -> String {
        guard let eventId = input["event_id"] as? String else {
            return "Error: Missing 'event_id' parameter"
        }
        
        let title = input["title"] as? String
        let startDate = (input["start_time"] as? String).flatMap { parseDateTime($0) }
        let endDate = (input["end_time"] as? String).flatMap { parseDateTime($0) }
        let location = input["location"] as? String
        let notes = input["notes"] as? String
        
        try await calendarService.updateEvent(
            eventId: eventId,
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: location,
            notes: notes
        )
        
        return "Event updated successfully"
    }
    
    private func executeCalendarDeleteEvent(input: [String: Any]) async throws -> String {
        guard let eventId = input["event_id"] as? String else {
            return "Error: Missing 'event_id' parameter"
        }
        
        try await calendarService.deleteEvent(eventId: eventId)
        return "Event deleted successfully"
    }
    
    private func executeCalendarCheckAvailability(input: [String: Any]) async throws -> String {
        guard let startTimeStr = input["start_time"] as? String,
              let endTimeStr = input["end_time"] as? String else {
            return "Error: Missing required parameters (start_time, end_time)"
        }
        
        guard let startDate = parseDateTime(startTimeStr),
              let endDate = parseDateTime(endTimeStr) else {
            return "Error: Invalid date format"
        }
        
        let (isFree, conflicts) = try await calendarService.checkAvailability(from: startDate, to: endDate)
        
        if isFree {
            return "That time slot is free - no conflicts"
        } else {
            var result = "That time slot has \(conflicts.count) conflict(s):\n"
            for event in conflicts {
                result += "- \(event.title)"
                if let start = event.startTime {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "h:mm a"
                    result += " at \(formatter.string(from: start))"
                }
                result += "\n"
            }
            return result
        }
    }
    
    private func executeCalendarFindFreeTime(input: [String: Any]) async throws -> String {
        guard let dateStr = input["date"] as? String else {
            return "Error: Missing 'date' parameter"
        }
        
        guard let date = parseDate(dateStr) else {
            return "Error: Invalid date format. Use YYYY-MM-DD"
        }
        
        let duration = input["duration_minutes"] as? Int ?? 60
        
        let freeSlots = try await calendarService.findFreeTime(on: date, durationMinutes: duration)
        
        if freeSlots.isEmpty {
            return "No free \(duration)-minute slots found on that day"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        var result = "Found \(freeSlots.count) free slot(s) for \(duration) minutes:\n"
        for slot in freeSlots {
            result += "- \(formatter.string(from: slot))\n"
        }
        return result
    }
    
    private func executeCalendarSearch(input: [String: Any]) async throws -> String {
        guard let query = input["query"] as? String else {
            return "Error: Missing 'query' parameter"
        }
        
        let events = try await calendarService.searchEvents(matching: query)
        
        if events.isEmpty {
            return "No events found matching '\(query)'"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        
        var result = "Found \(events.count) event(s):\n"
        for event in events {
            result += "- \(event.title) [id: \(event.id)]"
            if let start = event.startTime {
                result += " on \(formatter.string(from: start))"
            }
            result += "\n"
        }
        return result
    }
    
    // MARK: - Location Implementations
    
    private func executeLocationGetCurrent() async throws -> String {
        do {
            let description = try await locationService.getCurrentLocationDescription()
            return "Adam is currently in \(description)"
        } catch LocationError.permissionDenied {
            return "Error: Location permission denied. Enable it in System Settings > Privacy & Security > Location Services."
        } catch {
            return "Error getting location: \(error.localizedDescription)"
        }
    }
    
    private func executeLocationDistanceTo(input: [String: Any]) async throws -> String {
        guard let place = input["place"] as? String else {
            return "Error: Missing 'place' parameter. Use 'home' or 'house'"
        }
        
        do {
            let (_, description) = try await locationService.distanceTo(placeName: place)
            
            // Get the full place name for nicer output
            let placeName: String
            switch place.lowercased() {
            case "home":
                placeName = "home (Upper West Side)"
            case "house":
                placeName = "the Hudson Valley house"
            default:
                placeName = place
            }
            
            return "\(description) from \(placeName)"
        } catch LocationError.unknownPlace(let name) {
            return "Error: I don't know where '\(name)' is. I know: home, house"
        } catch LocationError.permissionDenied {
            return "Error: Location permission denied. Enable it in System Settings."
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    private func executeLocationAmIAt() async throws -> String {
        do {
            if let place = try await locationService.currentKnownPlace() {
                return "Yes, Adam is at \(place.name) (\(place.address))"
            } else {
                // Get current location description as fallback
                let description = try await locationService.getCurrentLocationDescription()
                return "Adam is not at home or the house. Currently in \(description)"
            }
        } catch LocationError.permissionDenied {
            return "Error: Location permission denied. Enable it in System Settings."
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Reminder Implementations
    
    private func executeRemindersGet(input: [String: Any]) async throws -> String {
        let listName = input["list"] as? String
        let includeCompleted = input["include_completed"] as? Bool ?? false
        
        let reminders: [DorisReminder]
        if let listName = listName {
            reminders = try await remindersService.getReminders(forList: listName, includeCompleted: includeCompleted)
        } else {
            reminders = try await remindersService.getReminders(includeCompleted: includeCompleted)
        }
        
        if reminders.isEmpty {
            if let listName = listName {
                return "No reminders found in '\(listName)' list"
            }
            return "No reminders found"
        }
        
        var result = "Found \(reminders.count) reminder(s):\n"
        for reminder in reminders {
            result += "- \(reminder.title) [id: \(reminder.id)]"
            if let dueDate = reminder.dueDate {
                result += " (due: \(formatDate(dueDate)))"
            }
            if let list = reminder.list {
                result += " [\(list)]"
            }
            if reminder.isCompleted {
                result += " ✓"
            }
            result += "\n"
        }
        return result
    }
    
    private func executeRemindersGetDue(input: [String: Any]) async throws -> String {
        let days = input["days"] as? Int ?? 7
        
        let reminders = try await remindersService.getDueReminders(within: days)
        
        if reminders.isEmpty {
            return "No reminders due within the next \(days) day(s)"
        }
        
        var result = "Found \(reminders.count) reminder(s) due within \(days) day(s):\n"
        for reminder in reminders {
            result += "- \(reminder.title) [id: \(reminder.id)]"
            if let dueDate = reminder.dueDate {
                result += " (due: \(formatDate(dueDate)))"
            }
            result += "\n"
        }
        return result
    }
    
    private func executeRemindersCreate(input: [String: Any]) async throws -> String {
        guard let title = input["title"] as? String else {
            return "Error: Missing 'title' parameter"
        }
        
        let notes = input["notes"] as? String
        let listName = input["list"] as? String
        
        // Parse due date if provided
        var dueDate: Date? = nil
        if let dueDateStr = input["due_date"] as? String {
            dueDate = parseDateTimeForReminder(dueDateStr)
        }
        
        // Parse priority
        var priority = 0
        if let priorityStr = input["priority"] as? String {
            switch priorityStr.lowercased() {
            case "high": priority = 1
            case "medium": priority = 5
            case "low": priority = 9
            default: priority = 0
            }
        }
        
        let reminderId = try await remindersService.createReminder(
            title: title,
            notes: notes,
            dueDate: dueDate,
            listName: listName,
            priority: priority
        )
        
        var result = "Created reminder '\(title)'"
        if let dueDate = dueDate {
            result += " due \(formatDate(dueDate))"
        }
        if let listName = listName {
            result += " in '\(listName)' list"
        }
        result += ". ID: \(reminderId)"
        return result
    }
    
    private func executeRemindersComplete(input: [String: Any]) async throws -> String {
        guard let reminderId = input["reminder_id"] as? String else {
            return "Error: Missing 'reminder_id' parameter"
        }
        
        try await remindersService.completeReminder(id: reminderId)
        return "Reminder marked as completed"
    }
    
    private func executeRemindersDelete(input: [String: Any]) async throws -> String {
        guard let reminderId = input["reminder_id"] as? String else {
            return "Error: Missing 'reminder_id' parameter"
        }
        
        try await remindersService.deleteReminder(id: reminderId)
        return "Reminder deleted"
    }
    
    private func executeRemindersSearch(input: [String: Any]) async throws -> String {
        guard let query = input["query"] as? String else {
            return "Error: Missing 'query' parameter"
        }
        
        let reminders = try await remindersService.searchReminders(matching: query)
        
        if reminders.isEmpty {
            return "No reminders found matching '\(query)'"
        }
        
        var result = "Found \(reminders.count) reminder(s) matching '\(query)':\n"
        for reminder in reminders {
            result += "- \(reminder.title) [id: \(reminder.id)]"
            if let dueDate = reminder.dueDate {
                result += " (due: \(formatDate(dueDate)))"
            }
            result += "\n"
        }
        return result
    }
    
    private func executeRemindersGetLists() -> String {
        let lists = remindersService.getLists()

        if lists.isEmpty {
            return "No reminder lists found"
        }

        return "Reminder lists: \(lists.joined(separator: ", "))"
    }

    // MARK: - Memory Implementations

    private func executeMemoryAdd(input: [String: Any]) -> String {
        guard let content = input["content"] as? String,
              let categoryStr = input["category"] as? String,
              let subject = input["subject"] as? String else {
            return "Error: Missing required parameters (content, category, subject)"
        }

        guard let category = MemoryCategory(rawValue: categoryStr) else {
            return "Error: Invalid category. Use: personal, preference, fact, task, relationship"
        }

        // Check for potential duplicates
        let similar = memoryStore.findSimilarMemories(content: content, subject: subject)

        if let newId = memoryStore.addMemory(
            content: content,
            category: category,
            source: .explicit,
            subject: subject.lowercased(),
            confidence: 1.0
        ) {
            var result = "Memory stored (id: \(newId)): \(content)"
            if !similar.isEmpty {
                result += "\n\nNote: Found \(similar.count) similar memory(s) - you may want to review for duplicates."
            }
            return result
        } else {
            return "Error: Failed to store memory"
        }
    }

    private func executeMemorySearch(input: [String: Any]) -> String {
        guard let query = input["query"] as? String else {
            return "Error: Missing 'query' parameter"
        }

        let memories = memoryStore.searchMemories(keyword: query)

        if memories.isEmpty {
            return "No memories found matching '\(query)'"
        }

        var result = "Found \(memories.count) memory(s):\n"
        for memory in memories {
            result += "- [id: \(memory.id)] \(memory.content)"
            if let subject = memory.subject {
                result += " (about: \(subject))"
            }
            result += "\n"
        }
        return result
    }

    private func executeMemoryGetAbout(input: [String: Any]) -> String {
        guard let subject = input["subject"] as? String else {
            return "Error: Missing 'subject' parameter"
        }

        let memories = memoryStore.getMemories(bySubject: subject)

        if memories.isEmpty {
            return "No memories found about '\(subject)'"
        }

        var result = "Found \(memories.count) memory(s) about \(subject):\n"
        for memory in memories {
            result += "- [id: \(memory.id), \(memory.category.rawValue)] \(memory.content)\n"
        }
        return result
    }

    private func executeMemoryUpdate(input: [String: Any]) -> String {
        guard let oldId = input["old_memory_id"] as? Int,
              let newContent = input["new_content"] as? String,
              let categoryStr = input["category"] as? String else {
            return "Error: Missing required parameters (old_memory_id, new_content, category)"
        }

        guard let category = MemoryCategory(rawValue: categoryStr) else {
            return "Error: Invalid category"
        }

        let subject = input["subject"] as? String

        if let newId = memoryStore.supersedeMemory(
            oldId: oldId,
            newContent: newContent,
            category: category,
            subject: subject?.lowercased()
        ) {
            return "Memory updated. Old memory (id: \(oldId)) superseded by new memory (id: \(newId)): \(newContent)"
        } else {
            return "Error: Failed to update memory. Make sure the old memory ID exists."
        }
    }

    private func executeMemoryDelete(input: [String: Any]) -> String {
        guard let memoryId = input["memory_id"] as? Int else {
            return "Error: Missing 'memory_id' parameter"
        }

        if memoryStore.deleteMemory(id: memoryId) {
            return "Memory (id: \(memoryId)) deleted"
        } else {
            return "Error: Failed to delete memory. Make sure the ID exists."
        }
    }

    private func executeMemoryListSubjects() -> String {
        let subjects = memoryStore.getAllSubjects()

        if subjects.isEmpty {
            return "No subjects found in memory yet"
        }

        return "Known subjects: \(subjects.joined(separator: ", "))"
    }

    private func executeMemoryCorrect(input: [String: Any]) -> String {
        guard let subject = input["subject"] as? String,
              let oldInfo = input["old_info"] as? String,
              let newContent = input["new_content"] as? String,
              let categoryStr = input["category"] as? String else {
            return "Error: Missing required parameters (subject, old_info, new_content, category)"
        }

        guard let category = MemoryCategory(rawValue: categoryStr) else {
            return "Error: Invalid category"
        }

        // First, find memories about this subject
        let subjectMemories = memoryStore.getMemories(bySubject: subject)

        // Search for the old info within those memories
        let oldInfoLower = oldInfo.lowercased()
        let matchingMemory = subjectMemories.first { memory in
            memory.content.lowercased().contains(oldInfoLower)
        }

        if let oldMemory = matchingMemory {
            // Found it - supersede
            if let newId = memoryStore.supersedeMemory(
                oldId: oldMemory.id,
                newContent: newContent,
                category: category,
                subject: subject.lowercased()
            ) {
                return "Corrected: '\(oldMemory.content)' → '\(newContent)' (old id: \(oldMemory.id), new id: \(newId))"
            } else {
                return "Error: Found memory but failed to update it"
            }
        } else {
            // Didn't find matching memory - just add the new one
            if let newId = memoryStore.addMemory(
                content: newContent,
                category: category,
                source: .explicit,
                subject: subject.lowercased(),
                confidence: 1.0
            ) {
                return "No existing memory found about '\(oldInfo)' for \(subject). Added as new memory (id: \(newId)): \(newContent)"
            } else {
                return "Error: Failed to store memory"
            }
        }
    }

    // MARK: - Contact Implementations
    
    private func executeContactsLookup(input: [String: Any]) async throws -> String {
        guard let name = input["name"] as? String else {
            return "Error: Missing 'name' parameter"
        }
        
        // First check Doris memory for stored contact info
        let memories = memoryStore.searchMemories(keyword: name)
        let contactMemories = memories.filter { memory in
            let content = memory.content.lowercased()
            return content.contains("email") || content.contains("@") || content.contains("phone")
        }
        
        var result = ""
        
        if !contactMemories.isEmpty {
            result += "From memory:\n"
            for memory in contactMemories {
                result += "- \(memory.content)\n"
            }
            result += "\n"
        }
        
        // Then check Apple Contacts
        let contacts = try await contactsService.searchByName(name)
        
        if contacts.isEmpty && contactMemories.isEmpty {
            return "No contact information found for '\(name)' in memory or Apple Contacts."
        }
        
        if !contacts.isEmpty {
            result += "From Apple Contacts:\n"
            result += contactsService.formatSearchResults(contacts)
        }
        
        return result
    }
    
    private func executeContactsFindEmail(input: [String: Any]) async throws -> String {
        guard let name = input["name"] as? String else {
            return "Error: Missing 'name' parameter"
        }
        
        // First check Doris memory
        let memories = memoryStore.searchMemories(keyword: name)
        for memory in memories {
            let content = memory.content.lowercased()
            // Look for email patterns in memory
            if content.contains("email") || content.contains("@") {
                // Try to extract email from memory content
                if let emailRange = memory.content.range(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: .regularExpression) {
                    let email = String(memory.content[emailRange])
                    return "Found email for \(name) in memory: \(email)"
                }
            }
        }
        
        // Fall back to Apple Contacts
        if let email = try await contactsService.findEmail(for: name) {
            return "Found email for \(name): \(email)"
        }
        
        return "No email found for '\(name)'. You can ask me to remember it: 'Remember that \(name)'s email is example@email.com'"
    }
    
    private func executeContactsFindPhone(input: [String: Any]) async throws -> String {
        guard let name = input["name"] as? String else {
            return "Error: Missing 'name' parameter"
        }
        
        // First check Doris memory
        let memories = memoryStore.searchMemories(keyword: name)
        for memory in memories {
            let content = memory.content.lowercased()
            if content.contains("phone") || content.contains("number") || content.contains("cell") {
                // Try to extract phone from memory content
                if let phoneRange = memory.content.range(of: #"[\d\-\(\)\s\.]{10,}"#, options: .regularExpression) {
                    let phone = String(memory.content[phoneRange])
                    return "Found phone for \(name) in memory: \(phone)"
                }
            }
        }
        
        // Fall back to Apple Contacts
        if let phone = try await contactsService.findPhone(for: name) {
            return "Found phone for \(name): \(phone)"
        }
        
        return "No phone number found for '\(name)'. You can ask me to remember it: 'Remember that \(name)'s phone is 555-123-4567'"
    }

    private func executeContactsCreate(input: [String: Any]) async throws -> String {
        guard let firstName = input["first_name"] as? String else {
            return "Error: Missing 'first_name' parameter"
        }

        let lastName = input["last_name"] as? String
        let email = input["email"] as? String
        let phone = input["phone"] as? String
        let organization = input["organization"] as? String
        let jobTitle = input["job_title"] as? String
        let note = input["note"] as? String

        let contact = try await contactsService.createContact(
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            organization: organization,
            jobTitle: jobTitle,
            note: note
        )

        var result = "Created contact: \(contact.displayName)"
        if let email = email { result += "\nEmail: \(email)" }
        if let phone = phone { result += "\nPhone: \(phone)" }
        if let org = organization { result += "\nOrganization: \(org)" }

        return result
    }

    private func executeContactsSearchByEmail(input: [String: Any]) async throws -> String {
        guard let email = input["email"] as? String else {
            return "Error: Missing 'email' parameter"
        }

        let contacts = try await contactsService.searchByEmail(email)

        if contacts.isEmpty {
            return "No contact found with email '\(email)'"
        }

        var result = "Found \(contacts.count) contact(s) with email '\(email)':\n"
        for contact in contacts {
            result += "- \(contact.displayName)"
            if let phone = contact.primaryPhone {
                result += " | Phone: \(phone)"
            }
            result += "\n"
        }
        return result
    }

    private func executeContactsSearchByPhone(input: [String: Any]) async throws -> String {
        guard let phone = input["phone"] as? String else {
            return "Error: Missing 'phone' parameter"
        }

        let contacts = try await contactsService.searchByPhone(phone)

        if contacts.isEmpty {
            return "No contact found with phone number '\(phone)'"
        }

        var result = "Found \(contacts.count) contact(s) with phone '\(phone)':\n"
        for contact in contacts {
            result += "- \(contact.displayName)"
            if let email = contact.primaryEmail {
                result += " | Email: \(email)"
            }
            result += "\n"
        }
        return result
    }

    private func executeContactsSearchByOrganization(input: [String: Any]) async throws -> String {
        guard let organization = input["organization"] as? String else {
            return "Error: Missing 'organization' parameter"
        }

        let contacts = try await contactsService.searchByOrganization(organization)

        if contacts.isEmpty {
            return "No contacts found at '\(organization)'"
        }

        var result = "Found \(contacts.count) contact(s) at '\(organization)':\n"
        for contact in contacts {
            result += "- \(contact.displayName)"
            if let title = contact.jobTitle {
                result += " (\(title))"
            }
            if let email = contact.primaryEmail {
                result += " | \(email)"
            }
            result += "\n"
        }
        return result
    }

    private func executeContactsList(input: [String: Any]) async throws -> String {
        let limit = min(input["limit"] as? Int ?? 50, 100)

        let contacts = try await contactsService.listAllContacts(limit: limit)

        if contacts.isEmpty {
            return "No contacts found."
        }

        var result = "Contact list (\(contacts.count) shown):\n"
        for contact in contacts {
            result += "- \(contact.displayName)"
            if let org = contact.organization {
                result += " (\(org))"
            }
            result += "\n"
        }
        return result
    }

    private func executeContactsGetBirthdays(input: [String: Any]) async throws -> String {
        let days = input["days"] as? Int ?? 30

        let birthdays = try await contactsService.getUpcomingBirthdays(withinDays: days)

        if birthdays.isEmpty {
            return "No birthdays found in the next \(days) days."
        }

        var result = "Upcoming birthdays (next \(days) days):\n"
        for (contact, daysUntil) in birthdays {
            let dayText = daysUntil == 0 ? "TODAY!" : (daysUntil == 1 ? "tomorrow" : "in \(daysUntil) days")
            result += "- \(contact.displayName): \(contact.formattedBirthday ?? "unknown date") (\(dayText))\n"
        }
        return result
    }

    private func executeContactsGetAddress(input: [String: Any]) async throws -> String {
        guard let name = input["name"] as? String else {
            return "Error: Missing 'name' parameter"
        }

        let contacts = try await contactsService.searchByName(name)

        if contacts.isEmpty {
            return "No contact found for '\(name)'"
        }

        // Find first contact with an address
        for contact in contacts {
            if let address = contact.primaryAddress {
                var result = "Address for \(contact.displayName):\n"
                if let label = address.label {
                    result += "(\(label))\n"
                }
                result += address.formatted
                return result
            }
        }

        return "No address found for '\(name)'. The contact exists but has no address saved."
    }

    private func executeContactsGetDetails(input: [String: Any]) async throws -> String {
        guard let name = input["name"] as? String else {
            return "Error: Missing 'name' parameter"
        }

        let contacts = try await contactsService.searchByName(name)

        if contacts.isEmpty {
            return "No contact found for '\(name)'"
        }

        // Get full details for the first (best) match
        let contact = contacts[0]
        return contactsService.getFullContactDetails(contact)
    }

    private func parseDateTimeForReminder(_ string: String) -> Date? {
        // First try the existing parseDateTime
        if let date = parseDateTime(string) {
            return date
        }
        
        // Then try parseDate (for date-only strings)
        if let date = parseDate(string) {
            // Set to 9am for date-only reminders
            let calendar = Calendar.current
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
        }
        
        return nil
    }
    
    // MARK: - Date Helpers
    
    private func parseDate(_ string: String) -> Date? {
        let lower = string.lowercased().trimmingCharacters(in: .whitespaces)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        print("🗓️ parseDate: Parsing '\(string)', today is \(today)")
        
        // Handle relative dates
        switch lower {
        case "today":
            return today
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: today)
        default:
            break
        }
        
        // Handle "next monday", "next week", etc.
        if lower.hasPrefix("next ") {
            let dayName = String(lower.dropFirst(5))
            if let weekday = weekdayFromName(dayName) {
                let result = nextWeekday(weekday)
                print("🗓️ parseDate: 'next \(dayName)' -> \(String(describing: result))")
                return result
            }
            if dayName == "week" {
                return calendar.date(byAdding: .day, value: 7, to: today)
            }
        }
        
        // Handle bare day names like "friday", "monday"
        if let weekday = weekdayFromName(lower) {
            let result = nextWeekday(weekday)
            print("🗓️ parseDate: '\(lower)' (bare day name) -> \(String(describing: result))")
            return result
        }
        
        // Handle "this friday", "this monday"
        if lower.hasPrefix("this ") {
            let dayName = String(lower.dropFirst(5))
            if let weekday = weekdayFromName(dayName) {
                let result = thisWeekday(weekday)
                print("🗓️ parseDate: 'this \(dayName)' -> \(String(describing: result))")
                return result
            }
        }
        
        // Try ISO format
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        if let date = isoFormatter.date(from: string) {
            return date
        }
        
        // Try common formats
        let formats = ["yyyy-MM-dd", "MM/dd/yyyy", "MMM d, yyyy", "MMMM d, yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        
        return nil
    }
    
    private func parseDateTime(_ string: String) -> Date? {
        // Try ISO 8601 with time
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }
        
        // Try without timezone
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "MM/dd/yyyy h:mm a",
            "MMM d, yyyy 'at' h:mm a"
        ]
        
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: string) {
                return date
            }
        }
        
        return nil
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func weekdayFromName(_ name: String) -> Int? {
        let days = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, 
                    "thursday": 5, "friday": 6, "saturday": 7]
        return days[name.lowercased()]
    }
    
    private func nextWeekday(_ weekday: Int) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        
        var daysToAdd = weekday - todayWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7  // If it's today or past, go to next week
        }
        
        let result = calendar.date(byAdding: .day, value: daysToAdd, to: today)
        print("🗓️ nextWeekday: target=\(weekday), todayWeekday=\(todayWeekday), daysToAdd=\(daysToAdd), result=\(String(describing: result))")
        return result
    }
    
    private func thisWeekday(_ weekday: Int) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        
        let daysToAdd = weekday - todayWeekday
        // For "this friday", if today IS friday, return today
        // If friday already passed this week, still return this week's friday (past date)
        
        let result = calendar.date(byAdding: .day, value: daysToAdd, to: today)
        print("🗓️ thisWeekday: target=\(weekday), todayWeekday=\(todayWeekday), daysToAdd=\(daysToAdd), result=\(String(describing: result))")
        return result
    }
}
