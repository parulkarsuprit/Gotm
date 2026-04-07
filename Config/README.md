# Configuration

This directory contains configuration files for the Gotm app.

## Files

### Info.plist
Main app configuration. This is checked into git and contains public app settings.

### Template.xcconfig
Template for build-time configuration. Copy this to `Secrets.xcconfig` and add your private API keys.

### Secrets.xcconfig ⭐️ IMPORTANT
**This file is gitignored and should NEVER be committed!**

Contains sensitive API keys that are injected at build time.

## Setup

1. Copy the template:
   ```bash
   cp Template.xcconfig Secrets.xcconfig
   ```

2. Edit `Secrets.xcconfig` and replace placeholder values with your actual keys:
   ```
   DEEPGRAM_API_KEY = your_actual_deepgram_key_here
   ```

3. Get a Deepgram API key:
   - Sign up at https://console.deepgram.com
   - Create a new project
   - Copy your API key

## How It Works

The `Secrets.xcconfig` file is included in the Xcode build configuration. Values defined here become build settings, which are then:

1. Injected into `Info.plist` via `$(DEEPGRAM_API_KEY)`
2. Read at runtime via `Bundle.main.object(forInfoDictionaryKey: "DEEPGRAM_API_KEY")`

This approach keeps secrets:
- ✅ Out of source code
- ✅ Out of git history
- ✅ Specific to each developer/environment
- ✅ Configurable per build configuration (Debug/Release)

## Troubleshooting

### "Transcription will fail" warning in console
You haven't configured `Secrets.xcconfig`. The app will still work but transcription will fail.

### Build errors about missing xcconfig
Make sure `Secrets.xcconfig` exists (even if empty). The build system expects it.

### API key not being read
1. Clean build folder (Cmd+Shift+K)
2. Check that `Config/Secrets.xcconfig` has no syntax errors
3. Verify the key format: `KEY = value` (spaces around =)
