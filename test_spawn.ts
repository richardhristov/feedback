import { spawn } from "node:child_process";
import { Buffer } from "node:buffer";

console.log("ℹ️ Spawning Swift process 'SystemAudioCapture'...");

const swiftApp = spawn(
  "swift",
  ["run", "--package-path", ".", "SystemAudioCapture"],
  {
    cwd: Deno.cwd(), // Run from the project root
    // detached: true, // Optional: experiment if it helps with permissions, though usually not for TCC
  }
);

swiftApp.stdout?.on("data", (data: Buffer) => {
  console.log(`[SWIFT_STDOUT]: ${data.toString().trim()}`);
});

swiftApp.stderr?.on("data", (data: Buffer) => {
  // Trim to avoid excessive newlines from buffered stderr from swift build process
  const strData = data.toString().trim();
  if (strData) {
    // Only log if there's actual content
    console.error(`[SWIFT_STDERR]: ${strData}`);
  }
});

swiftApp.on("error", (err: Error) => {
  console.error(`❌ Failed to start Swift process: ${err.message}`);
});

swiftApp.on("exit", (code: number | null, signal: string | null) => {
  console.log(`🚪 Swift process exited with code: ${code}, signal: ${signal}`);
});

swiftApp.on("close", (code: number | null, signal: string | null) => {
  console.log(
    `🚪 Swift process closed streams with code: ${code}, signal: ${signal}`
  );
});

console.log("ℹ️ Deno script will now wait for Swift process to exit...");
