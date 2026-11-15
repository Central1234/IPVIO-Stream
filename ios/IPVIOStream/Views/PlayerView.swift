import SwiftUI
import AVKit
import Combine

/// Full-screen player (AVPlayer): resume position, next episode, channel up/down for live TV, Picture in Picture.
@MainActor
struct PlayerView: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss

    let title: String
    let url: URL?
    /// Key for the saved position; nil for live TV.
    let resumeKey: String?
    var startFromBeginning = false
    var zapList: [MediaItem]? = nil
    var current: MediaItem? = nil
    var next: Episode? = nil

    @StateObject private var model = PlayerModel()
    @State private var channel: MediaItem?
    @State private var showControls = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            PlayerController(player: model.player).ignoresSafeArea()
            if let e = model.error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(e).multilineTextAlignment(.center)
                }
                .padding(24).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 12) {
                Button { close() } label: {
                    Image(systemName: "xmark").font(.headline).padding(12).background(.black.opacity(0.5), in: Circle())
                }
                Text(channel?.title ?? title).font(.headline).lineLimit(1).shadow(radius: 4)
                Spacer()
                if zapList != nil {
                    Button { zap(-1) } label: { Image(systemName: "chevron.up").padding(12).background(.black.opacity(0.5), in: Circle()) }
                    Button { zap(1) } label: { Image(systemName: "chevron.down").padding(12).background(.black.opacity(0.5), in: Circle()) }
                }
                if model.ended, let n = next {
                    Button { start(n.url, key: n.id, from: 0) } label: { Label("Next episode", systemImage: "forward.end.fill").padding(10).background(Theme.green, in: Capsule()).foregroundStyle(Theme.navy) }
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
        .statusBarHidden()
        .onAppear {
            channel = current
            start(url, key: resumeKey, from: resumeKey.map { startFromBeginning ? 0 : library.position(for: $0) } ?? 0)
        }
        .onDisappear { save(); model.player.pause() }
        .onReceive(model.tick) { _ in save() }
    }

    private func start(_ u: URL?, key: String?, from: Double) {
        save()
        model.key = key
        guard let u else { model.error = "This entry has no playable address."; return }
        model.play(u, at: from)
    }

    private func zap(_ d: Int) {
        guard let list = zapList, !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == channel?.id } ?? 0
        let n = list[(i + d + list.count) % list.count]
        channel = n
        start(n.url, key: nil, from: 0)
    }

    private func save() {
        guard let k = model.key else { return }
        let t = model.player.currentTime().seconds
        let d = model.player.currentItem?.duration.seconds ?? 0
        if t.isFinite && t > 0 { library.savePosition(t, duration: d.isFinite ? d : 0, for: k) }
    }

    private func close() { save(); model.player.pause(); dismiss() }
}

@MainActor
final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var error: String?
    @Published var ended = false
    var key: String?
    /// Saves the position every 15 seconds.
    let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private var bag = Set<AnyCancellable>()

    func play(_ url: URL, at seconds: Double) {
        error = nil
        ended = false
        bag.removeAll()
        // Same identifier as the Android app; many providers throttle unknown players
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "VLC/3.0.21 LibVLC/3.0.21"]])
        let item = AVPlayerItem(asset: asset)
        item.publisher(for: \.status).receive(on: RunLoop.main).sink { [weak self] s in
            guard s == .failed else { return }
            let ext = url.pathExtension.lowercased()
            self?.error = ["mkv", "avi", "ts"].contains(ext)
                ? "iOS cannot play .\(ext) files directly. Use an HLS (.m3u8) or MP4 source, or an Emby server, which converts them."
                : "The stream could not be played. Check the connection or try again later."
        }.store(in: &bag)
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.ended = true }.store(in: &bag)
        player.replaceCurrentItem(with: item)
        if seconds > 0 { player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
        player.play()
    }
}

/// AVPlayerViewController for the system controls, AirPlay and Picture in Picture.
struct PlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
