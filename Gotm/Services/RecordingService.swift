import AVFoundation
import Foundation
import Observation
import os

@MainActor
@Observable
final class RecordingService: NSObject {
    static let shared = RecordingService()

    private(set) var isRecording: Bool = false
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var currentRecordingURL: URL?
    private(set) var recordingLevel: Double = 0
    private(set) var inputSampleRate: Double = 44100

    private(set) var isPlaying: Bool = false
    private(set) var playbackProgress: TimeInterval = 0
    private(set) var playbackDuration: TimeInterval = 0
    private(set) var playingURL: URL?

    // Called from the audio tap (background thread) with Int16 mono PCM chunks for Deepgram streaming.
    nonisolated(unsafe) var onAudioBuffer: ((Data) -> Void)?
    // Called from the audio tap with the converted 16kHz mono PCM buffer for SFSpeechRecognizer.
    nonisolated(unsafe) var onAudioPCMBuffer: ((AVAudioPCMBuffer) -> Void)?

    private var engine: AVAudioEngine?
    // Written on audio tap thread, released on main actor after tap is removed.
    nonisolated(unsafe) private var audioFile: AVAudioFile?
    nonisolated(unsafe) private var converter: AVAudioConverter?
    nonisolated(unsafe) private var targetFormat: AVAudioFormat?
    // Latest RMS level from tap — thread-safe using lock
    private let levelLock = OSAllocatedUnfairLock<Double>(initialState: 0)

    private var player: AVAudioPlayer?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?

    private override init() { super.init() }

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func prewarmAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {}
    }

    // MARK: - Recording

    func startRecording() throws {
        if isPlaying { stopPlayback() }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        try? session.setPreferredSampleRate(16_000)

        let directory = RecordingStore.recordingsDirectory()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let fileURL = directory.appending(path: UUID().uuidString + ".wav")

        let eng = AVAudioEngine()
        self.engine = eng

        let inputNode = eng.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        let targetSampleRate: Double = 16_000
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1) ?? hwFormat
        converter = AVAudioConverter(from: hwFormat, to: targetFormat)
        self.targetFormat = targetFormat
        inputSampleRate = targetFormat.sampleRate

        // Write 16-bit PCM WAV — universally supported by Deepgram and other ASR services.
        // AVAudioFile converts Float32 hardware buffers to Int16 on write automatically.
        let wavSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: targetFormat.sampleRate,
            AVNumberOfChannelsKey: targetFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        audioFile = try AVAudioFile(forWriting: fileURL, settings: wavSettings)
        currentRecordingURL = fileURL

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let converted = self.convertBuffer(buffer, from: hwFormat)

            // Write to file
            if let converted {
                try? self.audioFile?.write(from: converted)
            }

            // Update level meter (use original for responsiveness) - thread-safe
            let level = Self.computeLevel(buffer)
            self.levelLock.withLock { $0 = level }

            // Stream converted buffer to SFSpeechRecognizer (primary)
            if let pcmCallback = self.onAudioPCMBuffer, let converted {
                pcmCallback(converted)
            }
            // Stream Int16 data to Deepgram WebSocket (if active)
            if let dataCallback = self.onAudioBuffer, let converted {
                let data = Self.toInt16MonoData(converted)
                if !data.isEmpty { dataCallback(data) }
            }
        }

        eng.prepare()
        try eng.start()

        recordingStartTime = Date()
        elapsedTime = 0
        recordingLevel = 0
        isRecording = true
        startRecordingTimer()
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let eng = engine, let fileURL = currentRecordingURL else { return nil }

        eng.inputNode.removeTap(onBus: 0)
        eng.stop()

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? elapsedTime

        engine = nil
        audioFile = nil          // closes and finalises the .caf file
        converter = nil
        targetFormat = nil
        recordingStartTime = nil
        currentRecordingURL = nil
        elapsedTime = 0
        recordingLevel = 0
        isRecording = false
        stopRecordingTimer()
        deactivateAudioSessionIfPossible()

        return (url: fileURL, duration: duration)
    }

    // MARK: - Playback

    func play(url: URL) {
        if isPlaying && playingURL == url { stopPlayback(); return }
        stopPlayback()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()

            playingURL = url
            playbackProgress = 0
            playbackDuration = player?.duration ?? 0
            isPlaying = true
            startPlaybackTimer()
        } catch {
            print("❌ [Play] Error: \(error)")
            stopPlayback()
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playbackProgress = 0
        playbackDuration = 0
        playingURL = nil
        stopPlaybackTimer()
        deactivateAudioSessionIfPossible()
    }

    // MARK: - Timers

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let start = self.recordingStartTime {
                self.elapsedTime = Date().timeIntervalSince(start)
            }
            // Thread-safe level reading
            let latest = self.levelLock.withLock { $0 }
            self.recordingLevel = (self.recordingLevel * 0.7) + (latest * 0.3)
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player else { return }
            self.playbackProgress = player.currentTime
            if !player.isPlaying { self.stopPlayback() }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func deactivateAudioSessionIfPossible() {
        guard !isRecording && !isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio helpers (nonisolated, called from background thread)

    private static func computeLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let floatData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sumOfSquares: Float = 0
        for i in 0..<frameLength { sumOfSquares += floatData[0][i] * floatData[0][i] }
        let rms = sqrt(sumOfSquares / Float(frameLength))
        let dB = 20 * log10(max(rms, 1e-9))
        let clamped = max(-60, min(0, dB))
        return Double((clamped + 60) / 60)
    }

    private static func toInt16MonoData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatData = buffer.floatChannelData else { return Data() }
        let frameLength = Int(buffer.frameLength)
        var samples = [Int16](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            let clamped = max(-1.0, min(1.0, floatData[0][i]))
            samples[i] = Int16(clamped * 32767)
        }
        return samples.withUnsafeBytes { Data($0) }
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter, let targetFormat else { return nil }
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        if let error {
            print("⚠️ [Record] Audio conversion failed: \(error)")
            return nil
        }
        return converted
    }
}

extension RecordingService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlayback()
    }
}
