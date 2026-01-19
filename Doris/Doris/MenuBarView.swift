//
//  MenuBarView.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import SwiftUI
import Combine

struct MenuBarView: View {
    @State private var inputText: String = ""
    @State private var responseText: String = "Responses will appear here..."
    @State private var isLoading: Bool = false

    // Use shared core instead of creating services
    private var core: DorisCore { DorisCore.shared }
    
    var body: some View {
        VStack(spacing: 16) {
            // Response text view
            ScrollView {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Thinking...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                } else {
                    Text(responseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
            }
            .frame(height: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Input field
            HStack {
                TextField(core.voiceService.isListening ? "Listening..." : "Type your message...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLoading || core.voiceService.isListening)
                    .onSubmit {
                        handleSubmit()
                    }

                // Microphone button
                Button(action: handleVoiceInput) {
                    Image(systemName: core.voiceService.isListening ? "mic.fill" : "mic")
                        .font(.title2)
                        .foregroundColor(core.voiceService.isListening ? .red : .primary)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                Button(action: handleSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isLoading || core.voiceService.isListening)
            }
            
            Divider()
            
            // Action buttons
            HStack {
                Button("Clear History") {
                    core.clearHistory()
                    responseText = "Conversation history cleared."
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            // Request permissions on launch
            core.locationService.requestPermission()

            // Request reminders permission
            Task {
                let granted = await core.remindersService.requestAccess()
                print("📝 Reminders access: \(granted ? "granted" : "denied")")
            }
        }
    }
    
    private func handleVoiceInput() {
        if core.voiceService.isListening {
            // Stop listening
            core.voiceService.stopListening()
        } else {
            // Start listening
            Task {
                do {
                    // Request permissions if needed
                    if !core.voiceService.checkPermissions() {
                        let granted = await core.voiceService.requestPermissions()
                        if !granted {
                            await MainActor.run {
                                responseText = "Microphone and speech recognition permissions are required. Please enable them in System Settings."
                            }
                            return
                        }
                    }

                    // Start listening
                    let transcription = try await core.voiceService.startListening()

                    // Set the text and submit
                    await MainActor.run {
                        inputText = transcription
                        handleSubmit()
                    }
                } catch {
                    await MainActor.run {
                        responseText = "Voice recognition error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func handleSubmit() {
        guard !inputText.isEmpty else { return }

        let userInput = inputText

        // Clear input immediately
        inputText = ""

        // Check if user is asking about time (fast path - no tools needed)
        let timeQuery = userInput.lowercased()
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
            print("⏰ Current time: \(currentDate), formatted: \(timeString)")
            responseText = "It's \(timeString)"
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
}

#Preview {
    MenuBarView()
}
