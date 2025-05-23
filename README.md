# Live Call Feedback Application

A macOS application that provides real-time feedback during phone calls by recording system audio and microphone input, transcribing speech using Whisper, and generating AI-powered feedback using OpenRouter.

## Features

- **Invisible to other party**: Records system audio and microphone separately without interfering with the call
- **Real-time transcription**: Uses local Whisper server for speech-to-text
- **AI feedback**: Provides actionable communication feedback every 15 seconds
- **Complete transcript logging**: Saves timestamped transcripts with speaker identification
- **Cross-platform audio**: Uses ScreenCaptureKit for system audio and SoX for microphone
- **Context-aware feedback**: Uses last 100 transcriptions for relevant feedback

## Prerequisites

1. **macOS 13+** (required for ScreenCaptureKit)
2. **Deno** - [Install Deno](https://deno.land/manual/getting_started/installation)
3. **Swift** - Xcode Command Line Tools
4. **SoX** - Audio processing library
   ```bash
   brew install sox
   ```
5. **Whisper.cpp server** - Local STT server
6. **OpenRouter API key** - For AI feedback

## Setup

### 1. Install Dependencies

```bash
# Install SoX for audio processing
brew install sox

# Clone whisper.cpp and build server (if not already done)
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
make server
```

### 2. Environment Configuration

Create a `.env` file in the project root:

```bash
OPENROUTER_API_KEY=your_openrouter_api_key_here
```

### 3. Permissions

The application requires the following macOS permissions:
- **Screen Recording** (for system audio capture via ScreenCaptureKit)
- **Microphone Access** (for recording your voice)

These will be requested automatically when you first run the application.

### 4. Start Whisper Server

Before running the application, start the local Whisper server:

```bash
cd whisper.cpp
./server -m models/ggml-base.en.bin --port 8080
```

You can download Whisper models using:
```bash
./models/download-ggml-model.sh base.en
```

## Usage

### Start Recording

```bash
deno run --allow-env --allow-net --allow-read --allow-write --allow-run --env-file=.env main.ts
```

### During the Call

- The application will start recording both your microphone and system audio
- Every 15 seconds, it processes the accumulated audio for transcription
- AI feedback appears in the terminal with actionable communication tips
- All transcripts are automatically saved to timestamped JSON files in the `data/` directory

### Stop Recording

Press `Ctrl+C` to gracefully stop the recording and save the final transcript.

## Output

### Real-time Feedback
The application provides console output like:
```
🎙️  Starting live call feedback session...
🎤 Starting microphone recording...
🔊 Starting system audio recording...
✅ Recording started. Press Ctrl+C to stop.

🔄 Processing audio for feedback...

💡 FEEDBACK: You're speaking clearly but try to leave more pause for the other person to respond. Consider asking an open-ended question.
────────────────────────────────────────────────────────────────
```

### Transcript Logs
Transcripts are saved as JSON files in the `data/` directory:

```json
[
  {
    "timestamp": "2024-01-15T10:30:15.123Z",
    "speaker": "microphone",
    "text": "Hello, thanks for taking the time to speak with me today."
  },
  {
    "timestamp": "2024-01-15T10:30:18.456Z",
    "speaker": "system",
    "text": "Of course! I'm excited to discuss this opportunity."
  }
]
```

## Architecture

### Components

1. **main.ts** - Main Deno application
   - Orchestrates recording and feedback
   - Handles microphone recording via SoX
   - Processes audio through Whisper
   - Generates AI feedback via OpenRouter

2. **SystemAudioCapture** - Swift wrapper
   - Uses ScreenCaptureKit for system audio
   - Outputs raw PCM audio to stdout
   - Handles audio format conversion

3. **Whisper Server** - Local STT
   - Converts audio to text
   - Runs locally for privacy

4. **OpenRouter** - AI feedback
   - Analyzes conversation context
   - Provides communication insights

### Audio Pipeline

```
Microphone → SoX → Raw PCM → TypeScript Handler → Whisper → AI Analysis
System Audio → Swift → Raw PCM → TypeScript Handler → Whisper → AI Analysis
```

## Configuration

You can modify these constants in `main.ts`:

- `FEEDBACK_INTERVAL_MS`: How often to provide feedback (default: 15000ms)
- `MAX_TRANSCRIPTIONS_FOR_FEEDBACK`: Number of recent transcriptions to use for feedback (default: 100)
- `WHISPER_SERVER_URL`: Local Whisper server endpoint

## Troubleshooting

### Permission Issues
- Grant Screen Recording permission in System Preferences → Security & Privacy → Screen Recording
- Grant Microphone permission when prompted

### Audio Issues
- Ensure SoX is installed: `brew install sox`
- Test microphone: `sox -t coreaudio default test.wav trim 0 5`
- Check system audio devices: `SwitchAudioSource -a`

### Whisper Server Issues
- Ensure server is running on port 8080
- Test with: `curl -X POST -F "file=@test.wav" http://127.0.0.1:8080/inference`

### Swift Build Issues
- Ensure Xcode Command Line Tools are installed
- Check Swift version: `swift --version`

## Privacy

- All audio processing happens locally
- Only transcribed text is sent to OpenRouter for feedback
- Raw audio is never transmitted externally
- Transcripts are saved locally in the `data/` directory

## License

This project is for educational and personal use. Please ensure compliance with local laws regarding call recording and consent. 