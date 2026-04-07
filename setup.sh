#!/bin/bash

# Gotm Setup Script
# Run this after cloning to configure local development environment

set -e

echo "🎙️  Setting up Gotm development environment..."

# Check if Secrets.xcconfig exists
if [ ! -f "Config/Secrets.xcconfig" ]; then
    echo "📋 Creating Secrets.xcconfig from template..."
    cp Config/Template.xcconfig Config/Secrets.xcconfig
    echo "⚠️  Please edit Config/Secrets.xcconfig and add your Deepgram API key"
    echo "   Get your key at: https://console.deepgram.com"
else
    echo "✅ Secrets.xcconfig already exists"
fi

# Check if DEEPGRAM_API_KEY is set
if grep -q "your_deepgram_api_key_here" Config/Secrets.xcconfig; then
    echo ""
    echo "⚠️  WARNING: DEEPGRAM_API_KEY not configured!"
    echo "   Transcription services will not work until you:"
    echo "   1. Sign up at https://console.deepgram.com"
    echo "   2. Copy your API key"
    echo "   3. Replace 'your_deepgram_api_key_here' in Config/Secrets.xcconfig"
    echo ""
else
    echo "✅ API key appears to be configured"
fi

# Verify .gitignore is working
if git check-ignore -q Config/Secrets.xcconfig 2>/dev/null; then
    echo "✅ Secrets.xcconfig is properly gitignored"
else
    echo "⚠️  Warning: Secrets.xcconfig may not be in .gitignore"
fi

echo ""
echo "🚀 Setup complete! Open Gotm.xcodeproj to build."
echo ""
echo "📖 Next steps:"
echo "   1. Open Gotm.xcodeproj in Xcode"
echo "   2. Select your development team"
echo "   3. Build and run (Cmd+R)"
