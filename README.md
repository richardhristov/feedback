# Live Call Feedback

A macOS application that provides real-time, AI-powered feedback during phone calls by capturing system and microphone audio locally, transcribing speech with Whisper, and analyzing conversation dynamics.

## Features

- **Invisible to other party**: Captures system audio and microphone separately without interference.
- **Real-time transcription**: Processes audio every interval (default 15s) via a local Whisper server.
- **AI feedback**: Generates concise, actionable feedback (1-2 sentences) on tone, clarity, and engagement.
- **Conversation summary**: Automatically generates a summary at the end of the call.
- **Transcript logging**: Saves timestamped JSON transcripts in `data/`.
- **Customizable**: Adjust interval, prompts, model selection, and data directory via CLI flags.
- **Multiple AI providers**: Supports OpenRouter, OpenAI, Anthropic, Google, and local Ollama.

## Prerequisites

- **macOS 13+** (for ScreenCaptureKit)
- **Deno** (https://deno.land)
- **Swift 5.9+** (Xcode Command Line Tools)
- **SoX** (`brew install sox`)
- **whisper.cpp** (local STT server)
- **API keys / endpoints configured in `.env`**:
  - `OPENROUTER_API_KEY` (OpenRouter)
  - `OPENAI_API_KEY` (OpenAI)
  - `ANTHROPIC_API_KEY` (Anthropic)
  - `GOOGLE_GENERATIVE_AI_API_KEY` (Google)
  - `OLLAMA_BASE_URL` (for local Ollama server, default `http://127.0.0.1:11434/api`)
  - `WHISPER_CPP_URL` (URL for the local whisper.cpp server, default `http://127.0.0.1:8080/inference`)

## Installation

Clone the repository and run the setup script:

```bash
git clone https://github.com/richardhristov/feedback
cd feedback
./setup.sh
```

The setup script will:

- Verify macOS and tool installations (Deno, SoX, Swift).
- Create a `.env` file template.
- Build the Swift `SystemAudioCapture` executable.
- Create the `data/` directory.

Edit `.env` and populate your API keys.

Start your local Whisper server:

```bash
cd whisper.cpp
./server -m models/ggml-base.en.bin --port 8080
```

## Usage

### Real-Time Feedback

Run the application with default settings (using the executable script):

```bash
chmod +x main.ts    # only needed once
./main.ts
```

Custom options (using the script):

```bash
./main.ts --interval 30000 \
  --data-dir ./my-transcripts \
  --max-transcriptions 50 \
  --prompt "Custom feedback prompt with {context}" \
  --summary-prompt "Custom summary prompt with {context}" \
  --model "anthropic:claude-3-sonnet-20240229"
```

#### CLI Options

- `-i, --interval <ms>`: Feedback interval in milliseconds (default: 15000).
- `-d, --data-dir <path>`: Path to save transcripts (default: `./data`).
- `-m, --max-transcriptions <n>`: Maximum recent transcripts for feedback (default: 100).
- `-p, --prompt <text>`: Feedback prompt template.
- `-s, --summary-prompt <text>`: Summary prompt template.
- `-o, --model <provider:model>`: AI model (e.g., `openrouter:google/gemini-2.0-flash-001`).

### Stopping and Summary

Press `Ctrl+C` to stop recording. The application will process any remaining audio, save transcripts, and display a conversation summary:

```
🛑 Stopping recording...
📝 Generating conversation summary...

📋 CONVERSATION SUMMARY:
- Main topics discussed
- Key decisions or action items
- Overall tone and outcome
────────────────────────────────────────────
✅ Session saved to: data/transcript_2025-05-24T10-30-00-000Z.json
```

### Testing System Audio Capture

Use the provided script to verify system audio capture:

```bash
./test_system_audio.sh
```

This script records 5 seconds of system audio, checks the raw PCM output, and converts it to WAV for playback.

## Architecture

- **main.ts**: Orchestrates audio capture, transcription, feedback, and summary.
- **registry.ts**: Manages AI provider integrations.
- **SystemAudioCapture** (Swift): Captures system audio via ScreenCaptureKit.
- **test_system_audio.sh**: Validates system audio pipeline.
- **setup.sh**: Simplifies initial setup.

### Audio Pipeline

```
Microphone → SoX → Raw PCM → main.ts → Whisper → AI Feedback
System Audio → Swift → Raw PCM → main.ts → Whisper → AI Feedback
```

## Contributing

Contributions welcome! Please:

1. Fork the repository.
2. Create a new branch (`git checkout -b feature/my-feature`).
3. Commit changes (`git commit -m 'Add feature'`).
4. Push to branch (`git push origin feature/my-feature`).
5. Open a Pull Request.

Ensure code is formatted and documented.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details. 