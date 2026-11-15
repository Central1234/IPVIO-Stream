import SwiftUI
import AVFoundation

@main
struct IPVIOStreamApp: App {
    @StateObject private var library = Library()

    init() {
        // Sound keeps playing with the silent switch on, and in the background / Picture in Picture
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(Theme.green)
        }
    }
}

enum Theme {
    static let green = Color(hex: 0x4ADE80)
    static let navy = Color(hex: 0x0B0F19)
    static let surface = Color(hex: 0x151B2A)
    static let muted = Color(hex: 0xA0A6B8)
}

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
