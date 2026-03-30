import SwiftUI

@main
struct VoiceRecorderApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    RecordingService.shared.prewarmAudioSession()
                    await TranscriptionService.shared.warmUp()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await TranscriptionService.shared.warmUp() }
                    }
                }
        }
    }
}
