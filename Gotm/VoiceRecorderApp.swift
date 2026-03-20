import SwiftUI

@main
struct VoiceRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    RecordingService.shared.prewarmAudioSession()
                    await TranscriptionService.shared.warmUp()
                }
        }
    }
}
