//
//  DorisCore.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import Foundation

@MainActor
class DorisCore {
    static let shared = DorisCore()

    let claudeService: ClaudeService
    let calendarService: AppleCalendarService
    let gmailService: GmailService
    let contactsService: ContactsService
    let locationService: LocationService
    let remindersService: AppleRemindersService
    let voiceService: VoiceService
    let toolExecutor: DorisToolExecutor

    private init() {
        self.claudeService = ClaudeService()
        self.calendarService = AppleCalendarService()
        self.gmailService = GmailService()
        self.contactsService = ContactsService()
        self.locationService = LocationService()
        self.remindersService = AppleRemindersService()
        self.voiceService = VoiceService()
        self.toolExecutor = DorisToolExecutor(
            gmailService: gmailService,
            calendarService: calendarService,
            locationService: locationService,
            remindersService: remindersService,
            contactsService: contactsService,
            memoryStore: claudeService.memory
        )

        print("🟢 DorisCore: Initialized")
    }

    // Move shouldUseTools() logic here from MenuBarView
    func shouldUseTools(_ query: String) -> Bool {
        // Calendar keywords
        let calendarKeywords = ["calendar", "schedule", "events", "meeting", "what's on",
                                 "free", "busy", "appointment", "reschedule", "cancel",
                                 "add to calendar", "create event", "delete event", "am i free"]

        // Email keywords
        let emailKeywords = ["email", "mail", "inbox", "unread", "gmail", "send",
                             "reply", "compose", "draft", "archive", "label", "flag"]

        // Reminder keywords
        let reminderKeywords = ["remind", "reminder", "reminders", "to do", "todo", "to-do",
                                "task", "tasks", "shopping list", "groceries", "don't forget",
                                "need to", "have to", "should", "pick up", "buy"]

        // Action keywords (things that require doing something)
        let actionKeywords = ["set", "create", "add", "delete", "remove",
                              "move", "change", "update", "send", "reply", "complete", "done", "mark"]

        // Location keywords
        let locationKeywords = ["where am i", "location", "how far", "distance",
                                "get home", "get to home", "get to the house",
                                "am i at", "am i home", "am i at home", "am i at the house"]

        // Memory keywords
        let memoryKeywords = ["remember", "remember this", "don't forget", "memorize",
                              "what do you know about", "what do you remember",
                              "forget", "forget about", "update memory", "you know",
                              "actually", "not anymore", "now it's", "now he", "now she",
                              "changed", "correction", "wrong", "instead"]

        // Contact keywords
        let contactKeywords = ["email", "send email", "contact", "phone number",
                               "what's", "what is", "find", "look up",
                               "gabby's", "levi's", "dani's"]

        let allKeywords = calendarKeywords + emailKeywords + reminderKeywords + actionKeywords + locationKeywords + memoryKeywords + contactKeywords
        return allKeywords.contains(where: { query.contains($0) })
    }

    // Main chat function - returns (textResponse, audioData?)
    func chat(message: String, includeAudio: Bool = false) async throws -> (text: String, audio: Data?) {
        // Fast path for time queries (no Claude needed)
        let timeQuery = message.lowercased()
        let isTimeQuestion = timeQuery.contains("what time") ||
                             timeQuery.contains("what's the time") ||
                             timeQuery.contains("tell me the time") ||
                             timeQuery.contains("current time") ||
                             timeQuery == "time" ||
                             timeQuery == "time?"

        if isTimeQuestion {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            formatter.timeZone = TimeZone.current
            formatter.locale = Locale.current
            let currentDate = Date()
            let timeString = formatter.string(from: currentDate)
            print("⏰ DorisCore: Current time: \(currentDate), formatted: \(timeString)")
            let response = "It's \(timeString)"

            var audioData: Data? = nil
            if includeAudio {
                audioData = try await voiceService.synthesizeToData(response)
            }

            return (response, audioData)
        }

        // Regular Claude processing
        let needsTools = shouldUseTools(message.lowercased())

        let response: String
        if needsTools {
            response = try await claudeService.sendMessage(message, toolExecutor: toolExecutor)
        } else {
            response = try await claudeService.sendMessage(message)
        }

        var audioData: Data? = nil
        if includeAudio {
            audioData = try await voiceService.synthesizeToData(response)
        }

        return (response, audioData)
    }

    func clearHistory() {
        claudeService.clearHistory()
    }
}
