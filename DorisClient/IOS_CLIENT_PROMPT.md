# Doris iOS Client - Implementation Prompt

## Current Status (Dec 31, 2024)

### What's Working ✅
- iOS app builds and runs on simulator (iOS 17+, Xcode 26)
- Tap-to-listen interaction works
- Speech recognition with SFSpeechRecognizer working
- Silence detection (1.5s) triggers send
- API calls to Mac server working (localhost:8080)
- Audio playback of ElevenLabs TTS responses working
- State machine: idle → listening → thinking → speaking → idle
- IdleView: Breathing coral circle animation
- ListeningView: Pulsing circles responding to mic amplitude (replaced SiriWaveView)
- SpeakingView: Pulsing circles responding to audio output (replaced SiriWaveView)

### What's NOT Working ❌
- **ThinkingView SceneKit animation not rendering** - The OS1 twisted infinity loop (ported from Three.js CodePen) is not displaying. The state transitions to .thinking but nothing visible appears. Added debug prints and a red circle fallback - need to test if those show up.

### What Was Changed From Original Plan
- **Removed SiriWaveView package** - Replaced with custom SwiftUI pulsing circle animations for Her aesthetic
- **ThinkingView** - Attempted SceneKit port of the OS1 CodePen animation (https://codepen.io/psyonline/pen/yayYWg) with custom tube geometry along a parametric curve
- **AudioRecorderService** - Fixed silence detection bug where timer started immediately instead of after first speech detected
- **DorisViewModel** - Added 1.5s minimum thinking time so animation is visible (but animation still not rendering)

### Files Modified
```
DorisClient/
├── DorisClient.xcodeproj/project.pbxproj  # Removed SiriWaveView package
├── DorisClient/
│   ├── Info.plist                         # Added bundle ID and other required keys
│   ├── Views/
│   │   ├── ListeningView.swift            # Custom pulsing circles (no SiriWaveView)
│   │   ├── SpeakingView.swift             # Custom pulsing circles (no SiriWaveView)  
│   │   └── ThinkingView.swift             # SceneKit OS1 animation (NOT WORKING)
│   ├── ViewModels/
│   │   └── DorisViewModel.swift           # Added minimum thinking time
│   └── Services/
│       └── AudioRecorderService.swift     # Fixed silence detection timing
```

### Next Steps to Debug ThinkingView
1. Run app, trigger thinking state
2. Check Xcode console for "OS1SceneView:" debug prints
3. Check if red circle fallback appears (would indicate view is mounting but SceneKit failing)
4. If nothing appears, the state may not be changing to .thinking at all

### Project Locations
- iOS Client: `/Users/adambell/Doris-Swift/DorisClient/DorisClient.xcodeproj`
- Mac Server: `/Users/adambell/Doris-Swift/Doris/Doris.xcodeproj`

### Server Details
- Mac server runs on port 8080
- API: `POST /chat` with `{"message":"...", "include_audio": true}` returns `{"text":"...", "audio":"<base64 MP3>"}`
- Server must be running for iOS client to work

### Her-Inspired Design
- Background: #1a1a1a (near black)
- Primary accent: #d1684e (warm coral)
- Animations: Minimal, breathing circles for idle/listening/speaking
- ThinkingView: Should be the OS1 twisted infinity loop from the movie

### Reference
- OS1 loading animation CodePen: https://codepen.io/psyonline/pen/yayYWg
- Uses Three.js TubeGeometry with parametric curve
- White tube on coral background, rotates around X axis
