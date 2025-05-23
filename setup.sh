#!/bin/bash

echo "🚀 Setting up Live Call Feedback Application"
echo "============================================="

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This application requires macOS 13+ (for ScreenCaptureKit)"
    exit 1
fi

# Check if Deno is installed
if ! command -v deno &> /dev/null; then
    echo "❌ Deno is not installed. Please install it first:"
    echo "   curl -fsSL https://deno.land/install.sh | sh"
    exit 1
fi

# Check if SoX is installed
if ! command -v sox &> /dev/null; then
    echo "📦 Installing SoX for audio processing..."
    if command -v brew &> /dev/null; then
        brew install sox
    else
        echo "❌ Homebrew not found. Please install SoX manually:"
        echo "   brew install sox"
        exit 1
    fi
fi

# Check if Swift is available
if ! command -v swift &> /dev/null; then
    echo "❌ Swift not found. Please install Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
fi

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    echo "📝 Creating .env file..."
    cat > .env << 'EOF'
# OpenRouter API Key
OPENROUTER_API_KEY=your_openrouter_api_key_here
EOF
    echo "⚠️  Please edit .env file and add your OpenRouter API key"
fi

# Create data directory
mkdir -p data

# Build Swift package
echo "🔨 Building Swift system audio capture..."
swift build

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit .env file and add your OpenRouter API key"
echo "2. Start Whisper server: "
echo "   cd whisper.cpp && ./server -m models/ggml-base.en.bin --port 8080"
echo "3. Run the application: ./main.ts"
echo ""
echo "📖 See README.md for detailed instructions" 