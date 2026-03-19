import AVFoundation
import Foundation

#if canImport(WhisperFramework)
import WhisperFramework
#endif

@MainActor
final class TranscriptionService {
    static let shared = TranscriptionService()

    private let modelFileName = "ggml-base.bin"
    private let modelDownloadURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!
    private let fileManager = FileManager.default

    func transcribe(fileURL: URL) async throws -> String {
        let modelURL = try await ensureModelIsAvailable()
        let samples = try await loadAudioSamples(from: fileURL)

        return try await Task.detached(priority: .userInitiated) {
            #if canImport(WhisperFramework)
            return try Self.runWhisper(modelURL: modelURL, samples: samples)
            #else
            throw TranscriptionError.frameworkUnavailable
            #endif
        }.value
    }

    private func ensureModelIsAvailable() async throws -> URL {
        let modelsDirectory = recordingsModelsDirectory()
        if !fileManager.fileExists(atPath: modelsDirectory.path) {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }

        let modelURL = modelsDirectory.appending(path: modelFileName)
        if fileManager.fileExists(atPath: modelURL.path) {
            return modelURL
        }

        let (tempURL, response) = try await URLSession.shared.download(from: modelDownloadURL)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw TranscriptionError.downloadFailed
        }

        if fileManager.fileExists(atPath: modelURL.path) {
            try fileManager.removeItem(at: modelURL)
        }

        try fileManager.moveItem(at: tempURL, to: modelURL)
        return modelURL
    }

    private func recordingsModelsDirectory() -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "Models", directoryHint: .isDirectory)
    }

    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            let inputFormat = file.processingFormat
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw TranscriptionError.audioConversionFailed
            }

            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let estimatedFrameCapacity = AVAudioFrameCount(Double(file.length) * ratio)
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(1, estimatedFrameCapacity))!

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inNumPackets)!
                do {
                    try file.read(into: buffer)
                } catch {
                    outStatus.pointee = .noDataNow
                    return nil
                }

                if buffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

            if error != nil {
                throw TranscriptionError.audioConversionFailed
            }

            guard let channelData = outputBuffer.floatChannelData?[0] else {
                throw TranscriptionError.audioConversionFailed
            }

            let frames = Int(outputBuffer.frameLength)
            return Array(UnsafeBufferPointer(start: channelData, count: frames))
        }.value
    }

    #if canImport(WhisperFramework)
    private static func runWhisper(modelURL: URL, samples: [Float]) throws -> String {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true

        guard let ctx = whisper_init_from_file_with_params(modelURL.path, cparams) else {
            throw TranscriptionError.modelLoadFailed
        }
        defer { whisper_free(ctx) }

        var wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        wparams.print_progress = false
        wparams.print_realtime = false
        wparams.print_timestamps = false
        wparams.print_special = false
        wparams.translate = false
        wparams.language = strdup("auto")
        defer { free(wparams.language) }

        let result = whisper_full(ctx, wparams, samples, Int32(samples.count))
        if result != 0 {
            throw TranscriptionError.inferenceFailed
        }

        let nSegments = whisper_full_n_segments(ctx)
        var output = ""
        for i in 0..<nSegments {
            let text = whisper_full_get_segment_text(ctx, i)
            output.append(String(cString: text))
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}

enum TranscriptionError: Error {
    case frameworkUnavailable
    case downloadFailed
    case modelLoadFailed
    case audioConversionFailed
    case inferenceFailed
}
