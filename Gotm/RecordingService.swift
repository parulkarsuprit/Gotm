import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class RecordingService: NSObject {
    static let shared = RecordingService()

    private(set) var isRecording: Bool = false
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var currentRecordingURL: URL?
    private(set) var recordingLevel: Double = 0

    private(set) var isPlaying: Bool = false
    private(set) var playbackProgress: TimeInterval = 0
    private(set) var playbackDuration: TimeInterval = 0
    private(set) var playingURL: URL?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?

    private override init() {
        super.init()
    }

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
        } catch {
            return
        }
    }

    func startRecording() throws {
        if isPlaying {
            stopPlayback()
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let directory = RecordingStore.recordingsDirectory()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let fileURL = directory.appending(path: UUID().uuidString + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.prepareToRecord()
        recorder?.record()

        currentRecordingURL = fileURL
        elapsedTime = 0
        recordingLevel = 0
        isRecording = true
        startRecordingTimer()
    }

    func stopRecording() -> RecordingEntry? {
        guard let recorder, let fileURL = currentRecordingURL else {
            return nil
        }

        recorder.stop()
        stopRecordingTimer()

        let assetDuration = AVURLAsset(url: fileURL).duration.seconds
        let duration = assetDuration.isFinite && assetDuration > 0 ? assetDuration : recorder.currentTime
        let date = Date()
        let name = defaultRecordingName(for: date)

        self.recorder = nil
        currentRecordingURL = nil
        elapsedTime = 0
        recordingLevel = 0
        isRecording = false

        deactivateAudioSessionIfPossible()

        return RecordingEntry(id: UUID(), name: name, date: date, duration: duration, fileURL: fileURL, transcript: nil)
    }

    func play(url: URL) {
        if isPlaying && playingURL == url {
            stopPlayback()
            return
        }

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

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self else { return }
            elapsedTime = recorder?.currentTime ?? 0

            recorder?.updateMeters()
            let average = recorder?.averagePower(forChannel: 0) ?? -80
            let peak = recorder?.peakPower(forChannel: 0) ?? average
            let power = max(average, peak)
            let normalized = normalizedPowerLevel(power)
            recordingLevel = (recordingLevel * 0.7) + (normalized * 0.3)
        }
    }

    private func normalizedPowerLevel(_ power: Float) -> Double {
        let clamped = max(-80, min(0, power))
        return Double((clamped + 80) / 80)
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player else { return }
            playbackProgress = player.currentTime
            if !player.isPlaying {
                stopPlayback()
            }
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

    private func defaultRecordingName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "Recording \(formatter.string(from: date))"
    }
}

extension RecordingService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlayback()
    }
}
