# Doris Swift Setup

## Environment Variables

The Doris server app requires API keys to function. Set these in the Xcode scheme:

1. Open `Doris/Doris.xcodeproj` in Xcode
2. Edit Scheme (⌘<) → Run → Arguments → Environment Variables
3. Set the following values:

| Variable | Description | Required |
|----------|-------------|----------|
| `ANTHROPIC_API_KEY` | Claude API key from console.anthropic.com | Yes |
| `GOOGLE_CLIENT_ID` | Google OAuth client ID for Gmail | For Gmail |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret | For Gmail |
| `ELEVENLABS_API_KEY` | ElevenLabs API key for TTS | Optional |

## Building

1. Open `Doris/Doris.xcodeproj` for the server app
2. Open `DorisClient/DorisClient.xcodeproj` for the client app
3. Build and run each project

## Architecture

- **Doris** (Server): Runs on Mac, provides REST API on port 8080
- **DorisClient** (Client): macOS/iOS app that connects to the server

The client connects to the server URL configured in Settings.
