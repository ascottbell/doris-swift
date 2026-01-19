//
//  ClaudeService.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import Foundation

// MARK: - Tool Executor Protocol

protocol ToolExecutor {
    func execute(toolName: String, input: [String: Any]) async -> String
}

// MARK: - Tool Definitions

struct DorisTools {
    static let allTools: [[String: Any]] = [
        // MARK: Gmail Tools
        [
            "name": "gmail_search",
            "description": "Search emails using Gmail query syntax. Examples: 'from:school', 'subject:pajama day', 'is:unread newer_than:1d', 'from:gabby'",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Gmail search query"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Max results to return (default 10)"
                    ]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "gmail_send",
            "description": "Send a new email",
            "input_schema": [
                "type": "object",
                "properties": [
                    "to": [
                        "type": "string",
                        "description": "Recipient email address"
                    ],
                    "subject": [
                        "type": "string",
                        "description": "Email subject"
                    ],
                    "body": [
                        "type": "string",
                        "description": "Email body text"
                    ]
                ],
                "required": ["to", "subject", "body"]
            ]
        ],
        [
            "name": "gmail_reply",
            "description": "Reply to an existing email thread",
            "input_schema": [
                "type": "object",
                "properties": [
                    "message_id": [
                        "type": "string",
                        "description": "ID of the message to reply to"
                    ],
                    "body": [
                        "type": "string",
                        "description": "Reply body text"
                    ]
                ],
                "required": ["message_id", "body"]
            ]
        ],
        [
            "name": "gmail_label",
            "description": "Add or remove a label from an email",
            "input_schema": [
                "type": "object",
                "properties": [
                    "message_id": [
                        "type": "string",
                        "description": "ID of the message"
                    ],
                    "label": [
                        "type": "string",
                        "description": "Label name (will be created if doesn't exist)"
                    ],
                    "action": [
                        "type": "string",
                        "enum": ["add", "remove"],
                        "description": "Whether to add or remove the label"
                    ]
                ],
                "required": ["message_id", "label", "action"]
            ]
        ],
        [
            "name": "gmail_archive",
            "description": "Archive an email (remove from inbox)",
            "input_schema": [
                "type": "object",
                "properties": [
                    "message_id": [
                        "type": "string",
                        "description": "ID of the message to archive"
                    ]
                ],
                "required": ["message_id"]
            ]
        ],
        [
            "name": "gmail_trash",
            "description": "Move an email to trash",
            "input_schema": [
                "type": "object",
                "properties": [
                    "message_id": [
                        "type": "string",
                        "description": "ID of the message to trash"
                    ]
                ],
                "required": ["message_id"]
            ]
        ],
        [
            "name": "gmail_mark_read",
            "description": "Mark an email as read or unread",
            "input_schema": [
                "type": "object",
                "properties": [
                    "message_id": [
                        "type": "string",
                        "description": "ID of the message"
                    ],
                    "read": [
                        "type": "boolean",
                        "description": "true to mark as read, false for unread"
                    ]
                ],
                "required": ["message_id", "read"]
            ]
        ],
        
        // MARK: Calendar Tools
        [
            "name": "calendar_get_events",
            "description": "Get calendar events for a date range",
            "input_schema": [
                "type": "object",
                "properties": [
                    "start_date": [
                        "type": "string",
                        "description": "Start date in ISO format (YYYY-MM-DD) or relative like 'today', 'tomorrow'"
                    ],
                    "end_date": [
                        "type": "string",
                        "description": "End date in ISO format (YYYY-MM-DD) or relative"
                    ]
                ],
                "required": ["start_date", "end_date"]
            ]
        ],
        [
            "name": "calendar_create_event",
            "description": "Create a new calendar event",
            "input_schema": [
                "type": "object",
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "Event title"
                    ],
                    "start_time": [
                        "type": "string",
                        "description": "Start time in ISO format (YYYY-MM-DDTHH:MM:SS)"
                    ],
                    "end_time": [
                        "type": "string",
                        "description": "End time in ISO format"
                    ],
                    "location": [
                        "type": "string",
                        "description": "Event location (optional)"
                    ],
                    "notes": [
                        "type": "string",
                        "description": "Event notes (optional)"
                    ],
                    "all_day": [
                        "type": "boolean",
                        "description": "Whether this is an all-day event"
                    ]
                ],
                "required": ["title", "start_time", "end_time"]
            ]
        ],
        [
            "name": "calendar_update_event",
            "description": "Update an existing calendar event",
            "input_schema": [
                "type": "object",
                "properties": [
                    "event_id": [
                        "type": "string",
                        "description": "ID of the event to update"
                    ],
                    "title": [
                        "type": "string",
                        "description": "New title (optional)"
                    ],
                    "start_time": [
                        "type": "string",
                        "description": "New start time (optional)"
                    ],
                    "end_time": [
                        "type": "string",
                        "description": "New end time (optional)"
                    ],
                    "location": [
                        "type": "string",
                        "description": "New location (optional)"
                    ],
                    "notes": [
                        "type": "string",
                        "description": "New notes (optional)"
                    ]
                ],
                "required": ["event_id"]
            ]
        ],
        [
            "name": "calendar_delete_event",
            "description": "Delete a calendar event",
            "input_schema": [
                "type": "object",
                "properties": [
                    "event_id": [
                        "type": "string",
                        "description": "ID of the event to delete"
                    ]
                ],
                "required": ["event_id"]
            ]
        ],
        [
            "name": "calendar_check_availability",
            "description": "Check if a time slot is free",
            "input_schema": [
                "type": "object",
                "properties": [
                    "start_time": [
                        "type": "string",
                        "description": "Start time to check in ISO format"
                    ],
                    "end_time": [
                        "type": "string",
                        "description": "End time to check in ISO format"
                    ]
                ],
                "required": ["start_time", "end_time"]
            ]
        ],
        [
            "name": "calendar_find_free_time",
            "description": "Find available time slots on a given day",
            "input_schema": [
                "type": "object",
                "properties": [
                    "date": [
                        "type": "string",
                        "description": "Date to check in ISO format (YYYY-MM-DD)"
                    ],
                    "duration_minutes": [
                        "type": "integer",
                        "description": "Required duration in minutes (default 60)"
                    ]
                ],
                "required": ["date"]
            ]
        ],
        [
            "name": "calendar_search",
            "description": "Search for events by text in title, location, or notes",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Search text"
                    ]
                ],
                "required": ["query"]
            ]
        ],
        
        // MARK: Location Tools
        [
            "name": "location_get_current",
            "description": "Get Adam's current location (neighborhood, city, state)",
            "input_schema": [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ],
        [
            "name": "location_distance_to",
            "description": "Get distance from current location to a known place. Known places: 'home' (310 W End Ave, NYC), 'house' (Hudson Valley)",
            "input_schema": [
                "type": "object",
                "properties": [
                    "place": [
                        "type": "string",
                        "description": "Name of the place: 'home' or 'house'"
                    ]
                ],
                "required": ["place"]
            ]
        ],
        [
            "name": "location_am_i_at",
            "description": "Check if Adam is currently at a known place (home or house)",
            "input_schema": [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ],
        
        // MARK: Reminder Tools
        [
            "name": "reminders_get",
            "description": "Get reminders. Can filter by list name or get all.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "list": [
                        "type": "string",
                        "description": "Optional list name to filter by (e.g., 'Shopping', 'Work')"
                    ],
                    "include_completed": [
                        "type": "boolean",
                        "description": "Include completed reminders (default false)"
                    ]
                ],
                "required": []
            ]
        ],
        [
            "name": "reminders_get_due",
            "description": "Get reminders due within a number of days",
            "input_schema": [
                "type": "object",
                "properties": [
                    "days": [
                        "type": "integer",
                        "description": "Number of days to look ahead (default 7)"
                    ]
                ],
                "required": []
            ]
        ],
        [
            "name": "reminders_create",
            "description": "Create a new reminder",
            "input_schema": [
                "type": "object",
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "Reminder title"
                    ],
                    "due_date": [
                        "type": "string",
                        "description": "Due date/time in ISO format or relative like 'today', 'tomorrow', 'next monday'"
                    ],
                    "notes": [
                        "type": "string",
                        "description": "Additional notes (optional)"
                    ],
                    "list": [
                        "type": "string",
                        "description": "List to add to (optional, uses default if not specified)"
                    ],
                    "priority": [
                        "type": "string",
                        "enum": ["high", "medium", "low", "none"],
                        "description": "Priority level (optional)"
                    ]
                ],
                "required": ["title"]
            ]
        ],
        [
            "name": "reminders_complete",
            "description": "Mark a reminder as completed",
            "input_schema": [
                "type": "object",
                "properties": [
                    "reminder_id": [
                        "type": "string",
                        "description": "ID of the reminder to complete"
                    ]
                ],
                "required": ["reminder_id"]
            ]
        ],
        [
            "name": "reminders_delete",
            "description": "Delete a reminder",
            "input_schema": [
                "type": "object",
                "properties": [
                    "reminder_id": [
                        "type": "string",
                        "description": "ID of the reminder to delete"
                    ]
                ],
                "required": ["reminder_id"]
            ]
        ],
        [
            "name": "reminders_search",
            "description": "Search reminders by keyword",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Search text"
                    ]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "reminders_get_lists",
            "description": "Get all reminder list names",
            "input_schema": [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ],

        // MARK: Memory Tools
        [
            "name": "memory_add",
            "description": "Store a new memory about Adam, his family, preferences, or facts. Use when Adam says 'remember this', mentions something worth keeping, or shares personal info. Always identify the subject(s) of the memory.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "content": [
                        "type": "string",
                        "description": "The memory content - clear, concise statement of the fact"
                    ],
                    "category": [
                        "type": "string",
                        "enum": ["personal", "preference", "fact", "task", "relationship"],
                        "description": "Category: personal (about Adam/family), preference (likes/dislikes), fact (general info), task (recurring things to do), relationship (connections between people)"
                    ],
                    "subject": [
                        "type": "string",
                        "description": "Who/what this is about. Comma-separated if multiple. Examples: 'adam', 'levi', 'gabby', 'dani', 'billi', 'adam,gabby', 'home', 'house'"
                    ]
                ],
                "required": ["content", "category", "subject"]
            ]
        ],
        [
            "name": "memory_search",
            "description": "Search existing memories by keyword or phrase. Use to check for existing info before adding, or to recall something.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Search term or phrase"
                    ]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "memory_get_about",
            "description": "Get all memories about a specific person or thing. Use when Adam asks 'what do you know about X'.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "subject": [
                        "type": "string",
                        "description": "The person or thing to get memories about. Examples: 'levi', 'gabby', 'billi', 'house'"
                    ]
                ],
                "required": ["subject"]
            ]
        ],
        [
            "name": "memory_update",
            "description": "Correct or update an existing memory. Use when Adam corrects previous info - this supersedes the old memory and keeps a record of the change.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "old_memory_id": [
                        "type": "integer",
                        "description": "ID of the memory to correct (from memory_search results)"
                    ],
                    "new_content": [
                        "type": "string",
                        "description": "The corrected memory content"
                    ],
                    "category": [
                        "type": "string",
                        "enum": ["personal", "preference", "fact", "task", "relationship"],
                        "description": "Category for the updated memory"
                    ],
                    "subject": [
                        "type": "string",
                        "description": "Subject(s) of the memory, comma-separated if multiple"
                    ]
                ],
                "required": ["old_memory_id", "new_content", "category"]
            ]
        ],
        [
            "name": "memory_correct",
            "description": "Correct an existing memory in one step. Use when Adam says 'actually', 'not anymore', 'now it's X not Y'. This searches for the old info, finds the matching memory, and updates it. More efficient than search + update separately.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "subject": [
                        "type": "string",
                        "description": "Who/what the memory is about: adam, levi, gabby, dani, billi, home, house"
                    ],
                    "old_info": [
                        "type": "string",
                        "description": "Keywords from the OLD/wrong information to find (e.g., 'Pokémon')"
                    ],
                    "new_content": [
                        "type": "string",
                        "description": "The complete corrected memory (e.g., 'Levi is really into Minecraft')"
                    ],
                    "category": [
                        "type": "string",
                        "enum": ["personal", "preference", "fact", "task", "relationship"],
                        "description": "Category for the memory"
                    ]
                ],
                "required": ["subject", "old_info", "new_content", "category"]
            ]
        ],
        [
            "name": "memory_delete",
            "description": "Delete a memory. Use only when Adam explicitly asks to forget something.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "memory_id": [
                        "type": "integer",
                        "description": "ID of the memory to delete"
                    ]
                ],
                "required": ["memory_id"]
            ]
        ],
        [
            "name": "memory_list_subjects",
            "description": "List all known subjects (people, places, things) that have memories associated with them.",
            "input_schema": [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ],
        
        // MARK: Contact Tools
        [
            "name": "contacts_lookup",
            "description": "Look up contact info for a person by name. Searches both Doris memory and Apple Contacts. Use before sending email to someone.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name of the person to look up"
                    ]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "contacts_find_email",
            "description": "Find email address for a person. Use this when you need to send an email and only have a name. Checks Doris memory first, then Apple Contacts.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name of the person"
                    ]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "contacts_find_phone",
            "description": "Find phone number for a person. Checks Doris memory first, then Apple Contacts.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name of the person"
                    ]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "contacts_create",
            "description": "Create a new contact in Apple Contacts. Use this when asked to add someone as a contact or save contact info.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "first_name": [
                        "type": "string",
                        "description": "First name (required)"
                    ],
                    "last_name": [
                        "type": "string",
                        "description": "Last name (optional)"
                    ],
                    "email": [
                        "type": "string",
                        "description": "Email address (optional)"
                    ],
                    "phone": [
                        "type": "string",
                        "description": "Phone number (optional)"
                    ],
                    "organization": [
                        "type": "string",
                        "description": "Company or organization (optional)"
                    ],
                    "job_title": [
                        "type": "string",
                        "description": "Job title (optional)"
                    ],
                    "note": [
                        "type": "string",
                        "description": "Notes about this contact (optional)"
                    ]
                ],
                "required": ["first_name"]
            ]
        ],
        [
            "name": "contacts_search_by_email",
            "description": "Find who owns an email address. Reverse lookup - search contacts by email instead of name.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "email": [
                        "type": "string",
                        "description": "Email address to search for"
                    ]
                ],
                "required": ["email"]
            ]
        ],
        [
            "name": "contacts_search_by_phone",
            "description": "Find who owns a phone number. Reverse lookup - search contacts by phone instead of name.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "phone": [
                        "type": "string",
                        "description": "Phone number to search for"
                    ]
                ],
                "required": ["phone"]
            ]
        ],
        [
            "name": "contacts_search_by_organization",
            "description": "Find all contacts at a company or organization.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "organization": [
                        "type": "string",
                        "description": "Company or organization name to search for"
                    ]
                ],
                "required": ["organization"]
            ]
        ],
        [
            "name": "contacts_list",
            "description": "List all contacts or browse the contact list. Use when asked 'who's in my contacts' or similar.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of contacts to return (default 50, max 100)"
                    ]
                ],
                "required": []
            ]
        ],
        [
            "name": "contacts_get_birthdays",
            "description": "Get contacts with upcoming birthdays. Use when asked about birthdays coming up.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "days": [
                        "type": "integer",
                        "description": "Number of days to look ahead (default 30)"
                    ]
                ],
                "required": []
            ]
        ],
        [
            "name": "contacts_get_address",
            "description": "Get postal/mailing address for a contact. Use when asked for someone's address.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name of the person"
                    ]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "contacts_get_details",
            "description": "Get full detailed information for a contact including all phones, emails, addresses, social profiles, birthday, and notes.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name of the person"
                    ]
                ],
                "required": ["name"]
            ]
        ]
    ]
}

class ClaudeService {
    private let apiKey: String
    private let endpoint = "https://api.anthropic.com/v1/messages"
    private let model = "claude-sonnet-4-5-20250929"
    private let maxHistoryMessages = 40 // 20 exchanges = 40 messages (user + assistant pairs)
    
    private let baseSystemPrompt = """
        You are Doris, Adam's personal AI assistant. This is a VOICE interface - your responses will be spoken aloud by a TTS engine, not read.

        CRITICAL - NEVER NARRATE YOUR THOUGHT PROCESS:
        - NEVER say things like "Adam wants me to remember this", "I should use my memory tool", "Let me search for that"
        - NEVER describe what tools you're using or why
        - NEVER explain your reasoning process out loud
        - Just DO the thing and respond naturally with the result
        - If Adam says "remember that Levi likes Minecraft", just say "Got it" or "Noted" — don't narrate storing it
        - If you need to search something, just do it silently and give the answer

        TTS FORMATTING (important for natural delivery):
        - Use punctuation to control pacing. Commas create short pauses. Periods create longer ones.
        - Use dashes — like this — for dramatic pauses or asides.
        - Use ellipses... for trailing off or hesitation.
        - For emphasis, you can use caps sparingly: "That's actually REALLY good."
        - Question marks and exclamation points affect inflection, use them intentionally.
        - Write numbers as words when spoken ("three meetings" not "3 meetings").
        - Spell out abbreviations if they should be spoken ("doctor" not "Dr.")

        HOW TO SPEAK:
        - Talk like a real person, not a document. Use contractions (you've, there's, don't).
        - No lists, bullets, or numbered items. Ever. Speak in natural sentences.
        - No "First... Second... Third..." structures. Just talk.
        - Keep it short. One to three sentences for simple answers. A few more for complex stuff.
        - Use casual transitions: "so", "anyway", "oh and", "looks like"
        - It's fine to be incomplete. "You've got a few things tomorrow — want me to run through them?" is better than listing everything unprompted.

        PERSONALITY:
        - Slightly dry, a little sarcastic, but not mean
        - Direct and helpful without being a cheerleader
        - Mild cursing is fine when it fits
        - No exclamation points, no "Great question!", no "Absolutely!"

        IMPORTANT - CURRENT TIME:
        - You do NOT have access to the current time. Never state a specific time from memory or conversation history.
        - If asked about the time, say "I don't actually have access to the current time in this context."
        - The app has a fast-path that answers time queries directly, so this should rarely come up.

        CONTEXT:
        Adam has a wife Gabby, son Levi (8, birthday Jan 3), daughter Dani (5, birthday Nov 14), and dog Billi. Second home in Hudson Valley.

        MEMORY:
        You have persistent memory. Use the memory tools to store and recall information about Adam and his family.
        - When Adam tells you something new about himself or family, store it with memory_add
        - When Adam CORRECTS something ("actually", "not anymore", "now it's"), use memory_correct - it finds and updates in one step
        - When asked "what do you know about X", use memory_get_about
        - Be proactive about remembering preferences, facts about family members, and recurring patterns
        - Subject should be lowercase: adam, gabby, levi, dani, billi, home, house
        """
    
    // Conversation history stored as array of message dictionaries
    private var conversationHistory: [[String: Any]] = []
    
    // Memory store for persistent memories
    private let memoryStore = MemoryStore()
    
    // Current conversation ID for persistence
    private var currentConversationId: Int?
    
    init() {
        // Read API key from environment variable
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
            fatalError("ANTHROPIC_API_KEY environment variable not set")
        }
        self.apiKey = key
    }

    var memory: MemoryStore {
        return memoryStore
    }
    
    private func buildSystemPrompt() -> String {
        let memories = memoryStore.getMemoriesForSystemPrompt()
        return baseSystemPrompt + memories
    }
    
    func clearHistory() {
        conversationHistory = []
        currentConversationId = nil
        print("🟡 ClaudeService: Conversation history cleared")
    }
    
    func getCurrentConversationId() -> Int? {
        return currentConversationId
    }
    
    // MARK: - Memory Management
    
    func addMemory(content: String, category: MemoryCategory) -> Bool {
        return memoryStore.addMemory(content: content, category: category)
    }
    
    func getAllMemories() -> [Memory] {
        return memoryStore.getAllMemories()
    }
    
    func searchMemories(keyword: String) -> [Memory] {
        return memoryStore.searchMemories(keyword: keyword)
    }
    
    func deleteMemory(id: Int) -> Bool {
        return memoryStore.deleteMemory(id: id)
    }
    
    func getMemories(byCategory category: MemoryCategory) -> [Memory] {
        return memoryStore.getMemories(byCategory: category)
    }
    
    func sendMessage(_ message: String, toolExecutor: ToolExecutor? = nil) async throws -> String {
        print("🔵 ClaudeService: Sending message to API...")
        print("🔵 ClaudeService: Conversation history count: \(conversationHistory.count) messages")
        
        guard let url = URL(string: endpoint) else {
            throw ClaudeError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60
        
        // Add the new user message to history
        let userMessage: [String: Any] = [
            "role": "user",
            "content": message
        ]
        conversationHistory.append(userMessage)
        
        // Persist the user message
        if currentConversationId == nil {
            // Create new conversation with title from first message
            let title = String(message.prefix(50)) + (message.count > 50 ? "..." : "")
            currentConversationId = memoryStore.createConversation(title: title)
        }
        if let convId = currentConversationId {
            _ = memoryStore.addMessage(conversationId: convId, role: "user", content: message)
        }
        
        // Trim history to last N messages if needed
        if conversationHistory.count > maxHistoryMessages {
            conversationHistory = Array(conversationHistory.suffix(maxHistoryMessages))
            print("🟡 ClaudeService: Trimmed conversation history to \(maxHistoryMessages) messages")
        }
        
        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": buildSystemPrompt(),
            "messages": conversationHistory
        ]
        
        // Add tools if executor is provided
        if toolExecutor != nil {
            requestBody["tools"] = DorisTools.allTools
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("🔵 ClaudeService: Making network request...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        
        print("🔵 ClaudeService: Response status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 ClaudeService: Error response: \(errorString)")
            }
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let content = json?["content"] as? [[String: Any]] else {
            print("🔴 ClaudeService: Failed to parse content. Raw response: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw ClaudeError.invalidResponse
        }
        
        let stopReason = json?["stop_reason"] as? String
        print("🔵 ClaudeService: Stop reason: \(stopReason ?? "nil")")

        // Check if Claude wants to use a tool
        if stopReason == "tool_use", let toolExecutor = toolExecutor {
            return try await handleToolUse(content: content, toolExecutor: toolExecutor)
        }
        
        // Regular text response
        guard let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw ClaudeError.invalidResponse
        }
        
        // Add the assistant's response to history
        let assistantMessage: [String: Any] = [
            "role": "assistant",
            "content": text
        ]
        conversationHistory.append(assistantMessage)
        
        // Persist the assistant message
        if let convId = currentConversationId {
            _ = memoryStore.addMessage(conversationId: convId, role: "assistant", content: text)
        }
        
        print("🟢 ClaudeService: Successfully received response")
        return text
    }
    
    private func handleToolUse(content: [[String: Any]], toolExecutor: ToolExecutor) async throws -> String {
        print("🔵 ClaudeService: Entering handleToolUse with \(content.count) content blocks")

        // Find tool use blocks
        var toolUses: [(id: String, name: String, input: [String: Any])] = []
        var textParts: [String] = []
        
        for block in content {
            if let type = block["type"] as? String {
                if type == "tool_use",
                   let id = block["id"] as? String,
                   let name = block["name"] as? String,
                   let input = block["input"] as? [String: Any] {
                    toolUses.append((id, name, input))
                    print("🔧 ClaudeService: Tool call - \(name)")
                } else if type == "text", let text = block["text"] as? String {
                    textParts.append(text)
                }
            }
        }
        
        guard !toolUses.isEmpty else {
            throw ClaudeError.invalidResponse
        }
        
        // Add assistant message with tool use to history
        conversationHistory.append([
            "role": "assistant",
            "content": content
        ])
        
        // Execute tools and collect results
        var toolResults: [[String: Any]] = []
        
        for toolUse in toolUses {
            let result = await toolExecutor.execute(toolName: toolUse.name, input: toolUse.input)
            toolResults.append([
                "type": "tool_result",
                "tool_use_id": toolUse.id,
                "content": result
            ])
            print("🔧 ClaudeService: Tool result for \(toolUse.name): \(result.prefix(100))...")
        }
        
        // Add tool results to history
        conversationHistory.append([
            "role": "user",
            "content": toolResults
        ])
        
        // Continue conversation with tool results
        return try await continueAfterToolUse(toolExecutor: toolExecutor)
    }
    
    private func continueAfterToolUse(toolExecutor: ToolExecutor) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw ClaudeError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60
        
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": buildSystemPrompt(),
            "messages": conversationHistory,
            "tools": DorisTools.allTools
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        print("🔵 ClaudeService: continueAfterToolUse got status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 ClaudeService: Error after tool use: \(errorString)")
            }
            throw ClaudeError.invalidResponse
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]] else {
            print("🔴 ClaudeService: Failed to parse content. Raw response: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw ClaudeError.invalidResponse
        }
        
        let stopReason = json?["stop_reason"] as? String
        
        // Claude might want to use another tool
        if stopReason == "tool_use" {
            return try await handleToolUse(content: content, toolExecutor: toolExecutor)
        }
        
        // Extract final text response
        var finalText = ""
        for block in content {
            if let type = block["type"] as? String, type == "text",
               let text = block["text"] as? String {
                finalText += text
            }
        }
        
        // Add to history
        conversationHistory.append([
            "role": "assistant",
            "content": finalText
        ])
        
        // Persist the assistant message
        if let convId = currentConversationId {
            _ = memoryStore.addMessage(conversationId: convId, role: "assistant", content: finalText)
        }
        
        print("🟢 ClaudeService: Final response after tool use")
        return finalText
    }
}

enum ClaudeError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case networkError(URLError)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let statusCode):
            return "API error with status code: \(statusCode)"
        case .networkError(let urlError):
            return "Network error: \(urlError.localizedDescription)"
        }
    }
}
