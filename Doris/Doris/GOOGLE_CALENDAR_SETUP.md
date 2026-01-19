# Google Calendar Integration Setup

## Prerequisites

1. A Google Cloud Console account
2. Google Calendar API enabled

## Setup Instructions

### 1. Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or select an existing one)
3. Name it "Doris" or whatever you prefer

### 2. Enable Google Calendar API

1. In your project, go to **APIs & Services** → **Library**
2. Search for "Google Calendar API"
3. Click on it and press **Enable**

### 3. Configure OAuth Consent Screen

1. Go to **APIs & Services** → **OAuth consent screen**
2. Choose **External** user type (or Internal if you have a Google Workspace)
3. Fill in the required fields:
   - App name: `Doris`
   - User support email: Your email
   - Developer contact: Your email
4. Click **Save and Continue**
5. On the Scopes screen, click **Add or Remove Scopes**
6. Add these scopes:
   - `.../auth/calendar.readonly` (View your calendars)
   - `.../auth/calendar.events` (View and edit events)
7. Click **Save and Continue**
8. Add yourself as a test user
9. Click **Save and Continue**

### 4. Create OAuth Credentials

1. Go to **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **OAuth client ID**
3. Application type: **Desktop app**
4. Name: `Doris macOS`
5. Click **Create**
6. You'll see a dialog with your Client ID and Client Secret - **copy these!**

### 5. Configure Doris

Add these environment variables to your Xcode scheme:

1. In Xcode, go to **Product** → **Scheme** → **Edit Scheme...**
2. Select **Run** on the left
3. Go to the **Arguments** tab
4. Under **Environment Variables**, add:
   - Name: `GOOGLE_CLIENT_ID`
   - Value: `your-client-id-here.apps.googleusercontent.com`
   
   - Name: `GOOGLE_CLIENT_SECRET`
   - Value: `your-client-secret-here`

### 6. First Run

The first time you ask Doris about your calendar:

1. Your default browser will open with Google's authorization page
2. Sign in to your Google account
3. Review the permissions and click **Allow**
4. You'll be redirected to a success page (you can close it)
5. Doris will now have access to your calendar!

The tokens are stored securely in your macOS Keychain and will persist across app restarts.

## Usage Examples

Ask Doris things like:
- "What's on my calendar today?"
- "Show me today's schedule"
- "What's my next meeting?"
- "Am I free this afternoon?"

## Troubleshooting

### "Google Calendar not configured" error
- Make sure you've set the `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` environment variables

### Authorization fails
- Check that you've added yourself as a test user in the OAuth consent screen
- Make sure the Calendar API is enabled
- Verify your redirect URI is exactly: `http://localhost:8080/callback`

### "Access denied" errors
- You may need to re-authorize. Delete the keychain entries for `com.doris.google-calendar` and try again

## Security Notes

- OAuth tokens are stored in the macOS Keychain, not in plain text files
- The app uses OAuth 2.0 with offline access to get a refresh token
- Tokens are automatically refreshed when they expire
- The local HTTP server only runs during initial authentication, then shuts down
