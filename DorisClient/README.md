# Doris iOS Client

A minimal iOS app that acts as a voice-first client for the Doris personal AI assistant.

## Project Structure

```
DorisClient/
├── DorisClient.xcodeproj/        # Xcode project
├── DorisClient/
│   ├── DorisClientApp.swift      # App entry point
│   ├── ContentView.swift          # Main view with state-based UI
│   ├── Info.plist                 # Permissions and App Transport Security
│   ├── Models/
│   │   └── DorisState.swift       # State enum (idle, listening, thinking, speaking, error)
│   ├── ViewModels/
│   │   └── DorisViewModel.swift   # State management and coordination
│   ├── Views/
│   │   ├── IdleView.swift         # Breathing circle animation
│   │   ├── ListeningView.swift    # SiriWaveView for mic input
│   │   ├── ThinkingView.swift     # Rotating ring animation
│   │   └── SpeakingView.swift     # SiriWaveView for audio output
│   └── Services/
│       ├── AudioRecorderService.swift   # Mic input + speech recognition
│       ├── AudioPlayerService.swift     # Base64 MP3 playback
│       └── DorisAPIService.swift        # HTTP client for server
```

## Features

- **Voice-first interaction**: Tap to start listening, automatic silence detection
- **Real-time speech recognition**: Live transcription as you speak
- **Beautiful animations**: State-based UI inspired by "Her"
  - Idle: Breathing circle
  - Listening: Waveform visualization
  - Thinking: Rotating ring
  - Speaking: Waveform with audio output
- **Server communication**: Connects to Doris server on local network
- **Audio playback**: Plays base64-encoded MP3 responses

## Build Status

✅ Project builds successfully for iOS Simulator
⚠️ Minor warnings (deprecated API usage in iOS 17)

## Setup

1. Open `DorisClient.xcodeproj` in Xcode
2. Wait for Swift Package Manager to resolve dependencies (SiriWaveView)
3. Build and run on iOS Simulator or device (iOS 17+)

## Configuration

The server URL can be configured programmatically in `DorisAPIService.swift`:
- Default: `http://localhost:8080`
- Stored in UserDefaults as `serverURL`

For local network access:
1. Find your Mac's IP: `ifconfig | grep "inet " | grep -v 127.0.0.1`
2. Update the default URL or implement a settings UI

## Permissions

The app requires:
- Microphone access (for voice input)
- Speech recognition (for transcription)

These are configured in Info.plist with user-facing descriptions.

## App Transport Security

The Info.plist allows arbitrary HTTP loads for local network development.
For production, consider using HTTPS or restricting to specific local domains.

## Next Steps

- Add settings UI for server IP configuration
- Implement proper error handling UI
- Add network connectivity checks
- Optimize animations and transitions
- Test with actual Doris server
