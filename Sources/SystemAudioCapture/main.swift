import AVFoundation
import Foundation
import ScreenCaptureKit

class SystemAudioRecorder: NSObject {
  private var stream: SCStream?

  func startRecording() async throws {
    // Request permission for screen recording (needed for system audio)
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: false)

    guard let display = content.displays.first else {
      throw NSError(
        domain: "SystemAudioRecorder", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No displays found"])
    }

    // Create stream configuration
    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.queueDepth = 6

    // Create content filter with the main display
    let filter = SCContentFilter(display: display, excludingWindows: [])

    // Create and start the stream
    stream = SCStream(filter: filter, configuration: config, delegate: self)

    guard let stream = stream else {
      throw NSError(
        domain: "SystemAudioRecorder", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create stream"])
    }

    // Add audio output
    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))

    // Start capture
    try await stream.startCapture()
  }

  func stopRecording() async throws {
    guard let stream = stream else { return }
    try await stream.stopCapture()
    self.stream = nil
  }
}

extension SystemAudioRecorder: SCStreamDelegate {
  func stream(_ stream: SCStream, didStopWithError error: Error) {
    fputs("Stream stopped with error: \(error.localizedDescription)\n", stderr)
    exit(1)
  }
}

extension SystemAudioRecorder: SCStreamOutput {
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    fputs("SystemAudioCapture: Entered stream didOutputSampleBuffer. Type: \(type)\n", stderr)
    guard type == .audio else {
      fputs(
        "SystemAudioCapture: Received non-audio sample buffer. Type: \(type). Skipping.\n", stderr)
      return
    }

    guard sampleBuffer.isValid else {
      fputs("SystemAudioCapture: Received an invalid sample buffer. Skipping.\n", stderr)
      return
    }

    guard let formatDescription = sampleBuffer.formatDescription else {
      fputs(
        "SystemAudioCapture: Audio sample buffer has no format description. Skipping.\n", stderr)
      return
    }
    fputs(
      "SystemAudioCapture: Audio sample buffer format description found: \(formatDescription)\n",
      stderr)

    if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
      let asbd = asbdPtr.pointee
      fputs(
        "SystemAudioCapture: ASBD - mSampleRate: \(asbd.mSampleRate), mFormatID: \(String(formatID: asbd.mFormatID)), mFormatFlags: \(asbd.mFormatFlags), mBytesPerPacket: \(asbd.mBytesPerPacket), mFramesPerPacket: \(asbd.mFramesPerPacket), mBytesPerFrame: \(asbd.mBytesPerFrame), mChannelsPerFrame: \(asbd.mChannelsPerFrame), mBitsPerChannel: \(asbd.mBitsPerChannel)\n",
        stderr)
    } else {
      fputs("SystemAudioCapture: Could not get ASBD from format description.\n", stderr)
    }

    fputs(
      "SystemAudioCapture: Received audio sample buffer. Proceeding to extract audio data.\n",
      stderr)

    // Step 1: Get the required size for the AudioBufferList.
    var requiredAudioBufferListSize: Int = 0
    var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: &requiredAudioBufferListSize,
      bufferListOut: nil,
      bufferListSize: 0,
      blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault,
      flags: 0,
      blockBufferOut: nil
    )

    guard status == noErr else {
      fputs("SystemAudioCapture: Error \(status) getting AudioBufferList size. Skipping.\n", stderr)
      return
    }
    fputs(
      "SystemAudioCapture: Required AudioBufferList size: \(requiredAudioBufferListSize).\n", stderr
    )

    guard requiredAudioBufferListSize > 0 else {
      fputs("SystemAudioCapture: Required AudioBufferList size is 0. Skipping.\n", stderr)
      return
    }

    // Step 2: Allocate memory and get the AudioBufferList.
    // Allocate raw memory for the AudioBufferList structure based on the required size.
    let audioBufferListMemory = UnsafeMutableRawPointer.allocate(
      byteCount: requiredAudioBufferListSize,
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    // Initialize the memory to zeros, good practice for some C APIs.
    audioBufferListMemory.initializeMemory(
      as: UInt8.self, repeating: 0, count: requiredAudioBufferListSize)

    // Cast the raw pointer to an UnsafeMutablePointer<AudioBufferList> to pass to the function.
    let ablPointer = audioBufferListMemory.assumingMemoryBound(to: AudioBufferList.self)

    var blockBuffer: CMBlockBuffer?  // This is important to retain for the lifetime of the data

    status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: ablPointer,  // Pass pointer to allocated ABL
      bufferListSize: requiredAudioBufferListSize,  // Pass the allocated size
      blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &blockBuffer
    )

    // Ensure blockBuffer is released eventually if not nil, typically when done with audioData.
    // For this example, if we successfully process, it's implicitly managed by the Data object's lifetime later on, or needs manual release if we don't copy out.
    // Since we copy to `Data` and then `write`, `blockBuffer`'s direct management here is subtle.
    // The samples are valid as long as `blockBuffer` is retained. Let's make sure it's captured or released.
    // For now, the original code didn't explicitly release blockBuffer so let's keep it similar and focus on getting data.

    fputs(
      "SystemAudioCapture: CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer status: \(status == noErr ? "noErr" : String(status))\n",
      stderr)

    guard status == noErr else {
      fputs("SystemAudioCapture: Error \(status) getting AudioBufferList. Skipping.\n", stderr)
      audioBufferListMemory.deallocate()
      return
    }

    // The number of buffers should now be populated in ablPointer.pointee.mNumberBuffers
    let numBuffers = Int(ablPointer.pointee.mNumberBuffers)
    fputs(
      "SystemAudioCapture: Audio buffer list obtained. Number of buffers: \(numBuffers).\n", stderr)

    guard numBuffers > 0 else {
      fputs("SystemAudioCapture: No buffers found in AudioBufferList. Skipping.\n", stderr)
      audioBufferListMemory.deallocate()
      return
    }

    // Write each audio buffer to stdout
    // UnsafeMutableAudioBufferListPointer makes it easier to iterate
    let buffers = UnsafeMutableAudioBufferListPointer(ablPointer)

    // Assuming 2 channels (stereo) and non-interleaved data based on ASBD and buffer count
    if buffers.count == 2 && ablPointer.pointee.mNumberBuffers == 2 {
      let leftBuffer = buffers[0]
      let rightBuffer = buffers[1]

      guard let leftDataBytes = leftBuffer.mData, let rightDataBytes = rightBuffer.mData else {
        fputs("SystemAudioCapture: One or both channel buffers have nil mData. Skipping.\n", stderr)
        audioBufferListMemory.deallocate()
        return
      }

      let leftDataSize = Int(leftBuffer.mDataByteSize)
      let rightDataSize = Int(rightBuffer.mDataByteSize)

      // Assuming 32-bit float samples (4 bytes per sample)
      let bytesPerSample = MemoryLayout<Float32>.size
      guard bytesPerSample > 0 else {  // Should not happen for Float32
        fputs("SystemAudioCapture: Invalid bytesPerSample. Skipping.\n", stderr)
        audioBufferListMemory.deallocate()
        return
      }

      // Ensure both buffers have the same size and it's a multiple of bytesPerSample
      guard leftDataSize == rightDataSize && leftDataSize % bytesPerSample == 0 else {
        fputs(
          "SystemAudioCapture: Channel buffer sizes mismatch or not multiple of sample size. Left: \(leftDataSize), Right: \(rightDataSize). Skipping.\n",
          stderr)
        audioBufferListMemory.deallocate()
        return
      }

      let numSamplesPerChannel = leftDataSize / bytesPerSample
      fputs(
        "SystemAudioCapture: Interleaving \(numSamplesPerChannel) samples per channel.\n", stderr)

      var interleavedData = Data(capacity: numSamplesPerChannel * bytesPerSample * 2)  // 2 channels

      let leftSamples = leftDataBytes.bindMemory(to: Float32.self, capacity: numSamplesPerChannel)
      let rightSamples = rightDataBytes.bindMemory(to: Float32.self, capacity: numSamplesPerChannel)

      for i in 0..<numSamplesPerChannel {
        var leftSample = leftSamples[i]
        var rightSample = rightSamples[i]
        withUnsafeBytes(of: &leftSample) { interleavedData.append(contentsOf: $0) }
        withUnsafeBytes(of: &rightSample) { interleavedData.append(contentsOf: $0) }
      }

      if !interleavedData.isEmpty {
        interleavedData.withUnsafeBytes { bytesToWrite in
          _ = write(STDOUT_FILENO, bytesToWrite.baseAddress, bytesToWrite.count)
        }
        fflush(stdout)
        fputs(
          "SystemAudioCapture: Wrote \(interleavedData.count) interleaved bytes to stdout.\n",
          stderr)
      }

    } else {
      // Fallback for unexpected buffer count (e.g. mono, or more than 2 buffers)
      // This just writes buffers sequentially as before - might be incorrect for >1 buffer non-interleaved
      fputs(
        "SystemAudioCapture: Buffer count is not 2 (was \(buffers.count)). Writing sequentially (may be incorrect for non-interleaved multi-channel).\n",
        stderr)
      for i in 0..<buffers.count {
        let buffer = buffers[i]
        guard let audioData = buffer.mData else {
          fputs("SystemAudioCapture: Buffer \(i) mData is nil. Skipping.\n", stderr)
          continue
        }
        let dataSize = Int(buffer.mDataByteSize)
        fputs("SystemAudioCapture: Processing buffer \(i). Data size: \(dataSize)\n", stderr)
        if dataSize > 0 {
          let data = Data(bytes: audioData, count: dataSize)
          data.withUnsafeBytes { bytes in
            _ = write(STDOUT_FILENO, bytes.baseAddress, data.count)
          }
          fflush(stdout)  // Ensure data is written immediately
          fputs("SystemAudioCapture: Wrote \(dataSize) bytes from buffer \(i) to stdout.\n", stderr)
        }
      }
    }
    audioBufferListMemory.deallocate()
  }
}

// Helper to convert FourCharCode to String for mFormatID
func String(formatID: FourCharCode) -> String {
  return String(describing: چهار(formatID))
}

struct چهار: CustomStringConvertible {
  let value: FourCharCode
  init(_ value: FourCharCode) {
    self.value = value
  }
  var description: String {
    var s = ""
    s.append(Character(UnicodeScalar((value >> 24) & 0xFF)!))
    s.append(Character(UnicodeScalar((value >> 16) & 0xFF)!))
    s.append(Character(UnicodeScalar((value >> 8) & 0xFF)!))
    s.append(Character(UnicodeScalar(value & 0xFF)!))
    return s.trimmingCharacters(in: .whitespacesAndNewlines).reversed().reduce(
      "", { String($1) + $0 }
    ).replacingOccurrences(of: "\\0", with: " ")  // handle potential nulls and reverse for readability
  }
}

// Main execution
let recorder = SystemAudioRecorder()

// Set up signal handling for graceful shutdown
signal(SIGINT) { _ in
  exit(0)
}

Task {
  do {
    try await recorder.startRecording()
    fputs(
      "SystemAudioCapture: recorder.startRecording() completed. Waiting for audio samples.\n",
      stderr)

    // Keep running until interrupted
    while true {
      try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
    }
  } catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
  }
}

// Keep the main thread alive
RunLoop.main.run()
