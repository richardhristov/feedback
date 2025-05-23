#!/bin/bash

echo "🔊 Testing System Audio Capture"
echo "==============================="
echo ""
echo "This will test the Swift system audio capture for 10 seconds."
echo "Make sure to:"
echo "1. Grant Screen Recording permission when prompted"
echo "2. Play some audio (music, video, etc.) during the test"
echo ""
read -p "Press Enter to start the test..."

echo ""
echo "🎵 Starting system audio capture for 10 seconds..."
echo "   Play some audio now!"

# Run the system audio capture and save raw PCM data
swift run SystemAudioCapture > data/system_audio_raw.pcm 2>data/capture.log &
CAPTURE_PID=$!

# Wait for 5 seconds
sleep 5

# Stop the capture process
kill $CAPTURE_PID 2>/dev/null
wait $CAPTURE_PID 2>/dev/null

echo ""
echo "✅ Capture complete!"
echo ""

# Check if we got any data
FILESIZE=$(wc -c < data/system_audio_raw.pcm)
echo "📊 Captured data size: $FILESIZE bytes"

if [ $FILESIZE -eq 0 ]; then
    echo "❌ No audio data captured. Check the log:"
    cat data/capture.log
    exit 1
fi

echo "📈 Data rate: $(($FILESIZE / 10)) bytes/second"
echo ""

# Convert raw PCM to WAV for verification (if sox is available)
if command -v sox &> /dev/null; then
    echo "🔄 Converting to WAV for playback verification..."
    sox -t raw -r 48000 -e floating-point -b 32 -c 2 -L data/system_audio_raw.pcm data/system_audio.wav
    
    echo "🎧 Audio file created: data/system_audio.wav"
    echo "   You can play it with: afplay data/system_audio.wav"
    echo ""
    
    # Show some basic info about the audio
    soxi data/system_audio.wav 2>/dev/null || echo "Could not analyze audio file"
else
    echo "⚠️  SoX not installed - cannot convert to playable format"
    echo "   Install with: brew install sox"
fi

echo ""
echo "📝 Raw PCM file: data/system_audio_raw.pcm"
echo "   Format: 48kHz, 2 channels (stereo), 32-bit floating-point, little-endian"

# Show a hex dump of the first few bytes to verify we have real data
echo ""
echo "🔍 First 32 bytes of raw data (should not be all zeros):"
hexdump -C data/system_audio_raw.pcm | head -2

echo ""
echo "✨ Test complete! Check the files in data/" 