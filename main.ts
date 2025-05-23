#!/usr/bin/env -S deno run --allow-env --allow-net --allow-read --allow-write --allow-run --env-file=.env

import { openrouter } from "npm:@openrouter/ai-sdk-provider@0.4.6";
import { generateText } from "npm:ai@4.3.16";
import { spawn, ChildProcess } from "node:child_process";
import { mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { Buffer } from "node:buffer";

// Configuration
const FEEDBACK_INTERVAL_MS = 15000;
const WHISPER_SERVER_URL = "http://127.0.0.1:8080/inference";
const DATA_DIR = "./data";

// Microphone audio configuration (for SoX and Whisper)
const MIC_SAMPLE_RATE = 16000; // 16kHz for Whisper
const MIC_CHANNELS = 1; // Mono for simplicity
const MIC_BIT_DEPTH = 16; // Signed integer

// System audio configuration (from Swift executable)
const SYSTEM_AUDIO_SAMPLE_RATE = 48000;
const SYSTEM_AUDIO_CHANNELS = 2;
const SYSTEM_AUDIO_BIT_DEPTH = 32; // Floating-point

interface TranscriptEntry {
  timestamp: string;
  speaker: "microphone" | "system";
  text: string;
}

// Module-level state variables
const sessionId: string = new Date().toISOString().replace(/[:.]/g, "-");
const transcriptLog: TranscriptEntry[] = [];
let micBuffer = Buffer.alloc(0);
let systemBuffer = Buffer.alloc(0);
let isRecording = false;
let micProcess: ChildProcess | undefined;
let systemAudioProcess: ChildProcess | undefined;
let feedbackTimer: number | undefined;

function startMicrophoneRecording() {
  console.log("🎤 Starting microphone recording...");
  micProcess = spawn("sox", [
    "-t",
    "coreaudio",
    "default",
    "-t",
    "raw",
    "-r",
    MIC_SAMPLE_RATE.toString(),
    "-c",
    MIC_CHANNELS.toString(),
    "-e",
    "signed-integer",
    "-b",
    MIC_BIT_DEPTH.toString(),
    "-",
  ]);

  // Drain stderr from the sox process to prevent pipe buffer blocking
  if (micProcess.stderr) {
    micProcess.stderr.on("data", () => {});
  }

  if (!micProcess.stdout) {
    throw new Error("Microphone process stdout is null");
  }

  micProcess.stdout.on("data", (chunk: Buffer) => {
    micBuffer = Buffer.concat([micBuffer, chunk]);
  });

  micProcess.on("error", (error: Error) => {
    console.error("❌ Microphone recording error:", error);
  });
}

function startSystemAudioRecording() {
  console.log("🔊 Starting system audio recording...");
  systemAudioProcess = spawn("swift", ["run", "SystemAudioCapture"], {
    cwd: Deno.cwd(),
  });

  // Drain stderr from the Swift process to prevent pipe buffer blocking
  if (systemAudioProcess.stderr) {
    systemAudioProcess.stderr.on("data", () => {});
  }

  if (!systemAudioProcess.stdout) {
    throw new Error("System audio process stdout is null");
  }

  systemAudioProcess.stdout.on("data", (chunk: Buffer) => {
    systemBuffer = Buffer.concat([systemBuffer, chunk]);
  });

  systemAudioProcess.on("error", (error: Error) => {
    console.error("❌ System audio recording error:", error);
  });
}

async function saveTranscriptLog() {
  try {
    const logPath = join(DATA_DIR, `transcript_${sessionId}.json`);
    await Deno.writeTextFile(logPath, JSON.stringify(transcriptLog, null, 2));
  } catch (error) {
    console.error("❌ Failed to save transcript:", error);
  }
}

async function transcribeAudio(
  audioBuffer: Buffer,
  inputSpeaker: "microphone" | "system"
) {
  try {
    const tempWavPath = `/tmp/audio_${Date.now()}.wav`;
    let soxInputArgs: string[];
    if (inputSpeaker === "microphone") {
      soxInputArgs = [
        "-t",
        "raw",
        "-r",
        MIC_SAMPLE_RATE.toString(),
        "-c",
        MIC_CHANNELS.toString(),
        "-e",
        "signed-integer",
        "-b",
        MIC_BIT_DEPTH.toString(),
        "-",
      ];
    } else {
      soxInputArgs = [
        "-t",
        "raw",
        "-r",
        SYSTEM_AUDIO_SAMPLE_RATE.toString(),
        "-c",
        SYSTEM_AUDIO_CHANNELS.toString(),
        "-e",
        "floating-point",
        "-b",
        SYSTEM_AUDIO_BIT_DEPTH.toString(),
        "-L",
        "-",
      ];
    }
    const soxOutputArgs = [
      "-t",
      "wav",
      "-r",
      MIC_SAMPLE_RATE.toString(),
      "-c",
      "1",
      "-e",
      "signed-integer",
      "-b",
      "16",
      tempWavPath,
    ];
    const soxProcess = spawn("sox", [...soxInputArgs, ...soxOutputArgs]);

    soxProcess.stdin?.write(audioBuffer);
    soxProcess.stdin?.end();

    await new Promise<void>((resolve, reject) => {
      soxProcess.on("close", resolve);
      soxProcess.on("error", reject);
    });

    const formData = new FormData();
    const wavData = await Deno.readFile(tempWavPath);
    formData.append("file", new Blob([wavData]), "audio.wav");
    formData.append("response_format", "json");

    const response = await fetch(WHISPER_SERVER_URL, {
      method: "POST",
      body: formData,
    });

    if (!response.ok) {
      throw new Error(`Whisper server error: ${response.statusText}`);
    }
    const result = await response.json();
    await Deno.remove(tempWavPath);
    const out = result.text || "";
    if (typeof out !== "string") {
      throw new Error("Transcription returned non-string value");
    }
    return out;
  } catch (error) {
    console.error("Transcription failed:", error);
    return "";
  }
}

async function generateFeedback(transcriptions: TranscriptEntry[]) {
  try {
    const conversationContext = transcriptions
      .map((entry) => `[${entry.speaker}]: ${entry.text}`)
      .join("\n");
    const prompt = `You are an AI assistant providing real-time feedback during a phone call. 

Recent conversation:
${conversationContext}

Provide brief, actionable feedback for the user (microphone speaker) on their communication. Focus on:
- Tone and clarity
- Listening vs. talking balance
- Key points they should address
- Engagement level

Keep feedback concise (1-2 sentences max) and supportive.`;
    const { text: feedback } = await generateText({
      model: openrouter("anthropic/claude-sonnet-4"),
      prompt: prompt,
    });
    return feedback;
  } catch (error) {
    console.error("❌ Failed to generate feedback:", error);
    return "";
  }
}

async function processAudioAndProvideFeedback() {
  console.log("🔄 Processing audio for feedback...");

  const transcriptions: TranscriptEntry[] = [];
  const timestamp = new Date().toISOString();

  // Process microphone audio if we have any
  if (micBuffer.length > 0) {
    try {
      const transcription = await transcribeAudio(micBuffer, "microphone");
      if (transcription.trim()) {
        transcriptions.push({
          timestamp,
          speaker: "microphone",
          text: transcription,
        });
      }
    } catch (error) {
      console.error("❌ Microphone transcription error:", error);
    }
    micBuffer = Buffer.alloc(0); // Clear the buffer after processing
  }

  // Process system audio if we have any
  if (systemBuffer.length > 0) {
    try {
      const transcription = await transcribeAudio(systemBuffer, "system");
      if (transcription.trim()) {
        transcriptions.push({
          timestamp,
          speaker: "system",
          text: transcription,
        });
      }
    } catch (error) {
      console.error("❌ System audio transcription error:", error);
    }
    systemBuffer = Buffer.alloc(0); // Clear the buffer after processing
  }

  if (transcriptions.length === 0) {
    console.log("ℹ️  No speech detected in recent audio");
    return;
  }

  // Add transcriptions to the log
  transcriptLog.push(...transcriptions);

  const feedback = await generateFeedback(transcriptLog);
  console.log("\n💡 FEEDBACK:", feedback);
  console.log("─".repeat(60));
  await saveTranscriptLog();
}

function startFeedbackTimer() {
  feedbackTimer = setInterval(async () => {
    await processAudioAndProvideFeedback();
  }, FEEDBACK_INTERVAL_MS);
}

function startRecording() {
  if (isRecording) {
    console.log("Already recording...");
    return;
  }

  console.log("🎙️  Starting live call feedback session...");
  isRecording = true;

  startMicrophoneRecording();
  startSystemAudioRecording();
  startFeedbackTimer();

  console.log("✅ Recording started. Press Ctrl+C to stop.");
}

async function stopRecording() {
  if (!isRecording) {
    return;
  }
  console.log("🛑 Stopping recording...");
  isRecording = false;

  micProcess?.kill();
  systemAudioProcess?.kill();
  if (feedbackTimer) {
    clearInterval(feedbackTimer);
    feedbackTimer = undefined;
  }

  // Process any remaining audio before stopping
  await processAudioAndProvideFeedback();
  await saveTranscriptLog();
  console.log(`✅ Session saved to: transcript_${sessionId}.json`);
}

// Main execution
if (!existsSync(DATA_DIR)) {
  mkdirSync(DATA_DIR, { recursive: true });
}

Deno.addSignalListener("SIGINT", async () => {
  console.log("\n🛑 Received interrupt signal...");
  await stopRecording();
  Deno.exit(0);
});

startRecording();
