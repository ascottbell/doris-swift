# Claude Code Prompt: Add HTTP Server to Doris

## Project Overview

Doris is a native macOS Swift menubar app - a personal AI assistant with Claude API integration, persistent memory, voice I/O, and function calling for Gmail, Apple Calendar, Reminders, Location, and Memory.

**Goal:** Add an HTTP server layer so an iOS app can call the Mac app as a thin client. The MacBook stays running at home as the server. The iOS app captures voice, sends to server, and plays audio response.

## Project Location

```
/Users/adambell/Doris-Swift/Doris/
```

## Framework Choice

Use **Hummingbird** (https://github.com/hummingbird-project/hummingbird) - the lightweight, high-performance Swift HTTP server framework. It's SSWG incubated and built on SwiftNIO.

Add the package dependency:
```swift
.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
```

## Current Architecture

The app has these key files:

- `DorisApp.swift` - Entry point, uses `@NSApplicationDelegateAdaptor(AppDelegate.self)`
- `AppDelegate.swift` - Creates NSStatusItem menubar, creates NSPopover with MenuBarView
- `MenuBarView.swift` - SwiftUI view that owns all services and handles chat logic
- `ClaudeService.swift` - Claude API calls, conversation history, tool definitions, memory injection
- `DorisToolExecutor.swift` - Executes all tools (Gmail, Calendar, Location, Reminders, Memory)
- `MemoryStore.swift` - SQLite persistent memory with v2 schema
- `VoiceService.swift` - SFSpeechRecognizer input, ElevenLabs TTS output
- `GmailService.swift`, `AppleCalendarService.swift`, `AppleRemindersService.swift`, `LocationService.swift` - Integration services

**Current flow:**
1. MenuBarView creates all services in `init()`
2. User types or speaks, `handleSubmit()` is called
3. `shouldUseTools()` checks if query needs tools
4. `claudeService.sendMessage()` is called with optional `toolExecutor`
5. Response is displayed and spoken via `voiceService.speak()`

## What to Build

### 1. Create `DorisCore.swift`

A singleton/shared class that owns all the services and provides the core Doris functionality. Both the MenuBarView UI and the HTTP server will use this.

```swift
// DorisCore.swift
import Foundation

@MainActor
class DorisCore {
    static let shared = DorisCore()
    
    let claudeService: ClaudeService
    let calendarService: AppleCalendarService
    let gmailService: GmailService
    let locationService: LocationService
    let remindersService: AppleRemindersService
    let voiceService: VoiceService
    let toolExecutor: DorisToolExecutor
    
    private init() {
        self.claudeService = ClaudeService()
        self.calendarService = AppleCalendarService()
        self.gmailService = GmailService()
        self.locationService = LocationService()
        self.remindersService = AppleRemindersService()
        self.voiceService = VoiceService()
        self.toolExecutor = DorisToolExecutor(
            gmailService: gmailService,
            calendarService: calendarService,
            locationService: locationService,
            remindersService: remindersService,
            memoryStore: claudeService.memory
        )
    }
    
    // Move shouldUseTools() logic here from MenuBarView
    func shouldUseTools(_ query: String) -> Bool {
        // ... existing keyword matching logic
    }
    
    // Main chat function - returns (textResponse, audioData?)
    func chat(message: String, includeAudio: Bool = false) async throws -> (text: String, audio: Data?) {
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
```

### 2. Update `VoiceService.swift`

Add a method that returns audio Data instead of playing it:

```swift
// Add to VoiceService.swift
func synthesizeToData(_ text: String) async throws -> Data {
    guard let apiKey = elevenLabsApiKey, !apiKey.isEmpty else {
        throw VoiceError.ttsError("ElevenLabs API key not configured")
    }
    
    let url = URL(string: "\(elevenLabsEndpoint)/\(elevenLabsVoiceId)")!
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 15
    
    let body: [String: Any] = [
        "text": text,
        "model_id": "eleven_turbo_v2_5",
        "voice_settings": [
            "stability": 0.3,
            "similarity_boost": 0.7,
            "style": 0.5,
            "use_speaker_boost": true
        ]
    ]
    
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw VoiceError.ttsError("ElevenLabs API error")
    }
    
    return data
}
```

### 3. Create `DorisServer.swift`

The HTTP server using Hummingbird:

```swift
// DorisServer.swift
import Foundation
import Hummingbird

actor DorisServer {
    private var app: Application<RouterResponder<BasicRequestContext>>?
    private let port: Int
    
    init(port: Int = 8080) {
        self.port = port
    }
    
    func start() async throws {
        let router = Router()
        
        // Health check / status
        router.get("/status") { request, context -> Response in
            let body = ByteBuffer(string: #"{"status":"ok","service":"doris"}"#)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: body)
            )
        }
        
        // Main chat endpoint
        router.post("/chat") { request, context -> Response in
            // Parse request body
            guard let buffer = try await request.body.collect(upTo: 1024 * 1024),
                  let json = try? JSONSerialization.jsonObject(with: Data(buffer: buffer)) as? [String: Any],
                  let message = json["message"] as? String else {
                return Response(status: .badRequest)
            }
            
            let includeAudio = json["include_audio"] as? Bool ?? false
            
            do {
                let (text, audioData) = try await DorisCore.shared.chat(
                    message: message,
                    includeAudio: includeAudio
                )
                
                var responseDict: [String: Any] = ["text": text]
                if let audio = audioData {
                    responseDict["audio"] = audio.base64EncodedString()
                }
                
                let responseData = try JSONSerialization.data(withJSONObject: responseDict)
                let body = ByteBuffer(data: responseData)
                
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: body)
                )
            } catch {
                let errorDict = ["error": error.localizedDescription]
                let errorData = try! JSONSerialization.data(withJSONObject: errorDict)
                return Response(
                    status: .internalServerError,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: ByteBuffer(data: errorData))
                )
            }
        }
        
        // Memory endpoints
        router.get("/memory") { request, context -> Response in
            let memories = await DorisCore.shared.claudeService.getAllMemories()
            let memoryDicts = memories.map { memory -> [String: Any] in
                return [
                    "id": memory.id,
                    "content": memory.content,
                    "category": memory.category.rawValue,
                    "subject": memory.subject ?? "",
                    "confidence": memory.confidence
                ]
            }
            let responseData = try! JSONSerialization.data(withJSONObject: ["memories": memoryDicts])
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }
        
        // Clear conversation history
        router.post("/clear") { request, context -> Response in
            await DorisCore.shared.clearHistory()
            let body = ByteBuffer(string: #"{"status":"cleared"}"#)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: body)
            )
        }
        
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: port))
        )
        
        self.app = app
        
        print("🌐 DorisServer: Starting on port \(port)...")
        try await app.runService()
    }
    
    func stop() async {
        // Hummingbird handles graceful shutdown
        print("🌐 DorisServer: Stopping...")
    }
}
```

### 4. Update `MenuBarView.swift`

Remove the service creation and use DorisCore instead:

```swift
// MenuBarView.swift - updated
struct MenuBarView: View {
    @State private var inputText: String = ""
    @State private var responseText: String = "Responses will appear here..."
    @State private var isLoading: Bool = false
    
    // Use shared core instead of creating services
    private var core: DorisCore { DorisCore.shared }
    
    // Remove the init() that creates all services
    
    // Update handleSubmit to use core
    private func handleSubmit() {
        guard !inputText.isEmpty else { return }
        
        let userInput = inputText
        inputText = ""
        
        // Fast path for time
        if userInput.lowercased().contains("what time") || userInput.lowercased() == "time" {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            responseText = "It's \(formatter.string(from: Date()))"
            core.voiceService.speak(responseText)
            return
        }
        
        isLoading = true
        responseText = core.shouldUseTools(userInput.lowercased()) ? "On it..." : "Thinking..."
        
        Task {
            do {
                let (response, _) = try await core.chat(message: userInput, includeAudio: false)
                await MainActor.run {
                    responseText = response
                    isLoading = false
                    core.voiceService.speak(response)
                }
            } catch {
                await MainActor.run {
                    responseText = "Error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    // ... rest of the view code stays the same, just reference core.voiceService, core.locationService, etc.
}
```

### 5. Update `AppDelegate.swift`

Start the server when the app launches:

```swift
// AppDelegate.swift
import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var serverTask: Task<Void, Error>?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🔵 AppDelegate: applicationDidFinishLaunching called")
        
        // Initialize DorisCore first (this creates all services)
        _ = DorisCore.shared
        
        // Start HTTP server in background
        serverTask = Task {
            let server = DorisServer(port: 8080)
            try await server.start()
        }
        
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Doris")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        
        print("🟢 AppDelegate: Setup complete, server starting on port 8080")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        serverTask?.cancel()
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
```

### 6. Update Package Dependencies

In the Xcode project, add the Hummingbird package:
- URL: `https://github.com/hummingbird-project/hummingbird.git`
- Version: From 2.0.0

Then link the `Hummingbird` library to the Doris target.

## API Specification

### POST /chat

Request:
```json
{
    "message": "What's on my calendar today?",
    "include_audio": true
}
```

Response:
```json
{
    "text": "You have 3 meetings today. First up is...",
    "audio": "<base64 encoded mp3 data>"
}
```

### GET /status

Response:
```json
{
    "status": "ok",
    "service": "doris"
}
```

### GET /memory

Response:
```json
{
    "memories": [
        {
            "id": 1,
            "content": "Levi's birthday is January 3",
            "category": "personal",
            "subject": "levi",
            "confidence": 1.0
        }
    ]
}
```

### POST /clear

Response:
```json
{
    "status": "cleared"
}
```

## Testing

After implementing, test with curl:

```bash
# Check status
curl http://localhost:8080/status

# Send chat message (text only)
curl -X POST http://localhost:8080/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What time is it?"}'

# Send chat message (with audio)
curl -X POST http://localhost:8080/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello Doris", "include_audio": true}'

# Get memories
curl http://localhost:8080/memory

# Clear history
curl -X POST http://localhost:8080/clear
```

## Important Notes

1. **MainActor:** DorisCore and its services run on MainActor because they interact with UI components (VoiceService has @Published properties). The Hummingbird handlers need to properly await MainActor calls.

2. **Port binding:** The server binds to `0.0.0.0:8080` so it's accessible from other devices on the network, not just localhost.

3. **Error handling:** All errors should return proper JSON error responses, not crash the server.

4. **Audio format:** ElevenLabs returns MP3 data. The iOS client will receive base64-encoded MP3.

5. **Entitlements:** The app may need network server entitlements. Check `Doris.entitlements` if there are permission issues.

6. **Environment variables:** The server needs the same env vars as the app:
   - ANTHROPIC_API_KEY
   - ELEVENLABS_API_KEY
   - GOOGLE_CLIENT_ID
   - GOOGLE_CLIENT_SECRET

## Files to Create/Modify

**Create:**
- `DorisCore.swift`
- `DorisServer.swift`

**Modify:**
- `VoiceService.swift` (add synthesizeToData method)
- `MenuBarView.swift` (use DorisCore.shared instead of creating services)
- `AppDelegate.swift` (start server on launch)
- Xcode project (add Hummingbird package dependency)

## Success Criteria

1. App builds and runs without errors
2. Menubar UI still works exactly as before
3. `curl http://localhost:8080/status` returns `{"status":"ok","service":"doris"}`
4. `curl -X POST http://localhost:8080/chat -H "Content-Type: application/json" -d '{"message":"hello"}'` returns a response from Claude
5. Server logs show requests being handled
