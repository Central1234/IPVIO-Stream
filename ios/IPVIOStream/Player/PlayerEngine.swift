import AVFoundation
import AVKit
import Combine
import MediaPlayer
import SwiftUI

/// One entry the player can play: a channel, a movie or an episode.
struct PlayItem: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String? = nil
    var url: URL?
    /// Key for the saved position; nil for live TV.
    var resumeKey: String? = nil
    var artwork: URL? = nil
    var live = false
}

/// The playback engine behind [PlayerScreen]: AVPlayer with state the custom controls observe.
@MainActor
final class PlayerEngine: NSObject, ObservableObject {
    let player = AVPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = true
    @Published private(set) var current: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var ended = false
    @Published var error: String?

    @Published private(set) var audioOptions: [AVMediaSelectionOption] = []
    @Published private(set) var subtitleOptions: [AVMediaSelectionOption] = []
    @Published private(set) var selectedAudio: AVMediaSelectionOption?
    @Published private(set) var selectedSubtitle: AVMediaSelectionOption?
    @Published var rate: Float = 1 { didSet { if isPlaying { player.rate = rate } } }
    @Published var gravity: AVLayerVideoGravity = .resizeAspect

    @Published private(set) var pipPossible = false
    var pip: AVPictureInPictureController? {
        didSet {
            pipObs = pip?.publisher(for: \.isPictureInPicturePossible).receive(on: RunLoop.main).sink { [weak self] in self?.pipPossible = $0 }
        }
    }

    /// Live streams and streams without a known length.
    var isLive: Bool { duration <= 0 || !duration.isFinite }

    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var timeObs: Any?
    private var bag = Set<AnyCancellable>()
    private var itemBag = Set<AnyCancellable>()
    private var pipObs: AnyCancellable?

    override init() {
        super.init()
        player.allowsExternalPlayback = true
        player.publisher(for: \.timeControlStatus).receive(on: RunLoop.main).sink { [weak self] s in
            self?.isPlaying = s == .playing
            self?.isBuffering = s == .waitingToPlayAtSpecifiedRate
        }.store(in: &bag)
        timeObs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                if t.seconds.isFinite { self.current = t.seconds }
                if let d = self.player.currentItem?.duration.seconds, d.isFinite { self.duration = d }
            }
        }
        setupRemoteCommands()
    }

    func load(_ item: PlayItem, at seconds: Double) {
        error = nil
        ended = false
        current = seconds
        duration = 0
        audioOptions = []; subtitleOptions = []
        selectedAudio = nil; selectedSubtitle = nil
        itemBag.removeAll()
        guard let url = item.url else { error = "This entry has no playable address."; return }
        // Same identifier as the Android app; many providers throttle unknown players
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "VLC/3.0.21 LibVLC/3.0.21"]])
        let pi = AVPlayerItem(asset: asset)
        pi.preferredForwardBufferDuration = item.live ? 8 : 30
        pi.publisher(for: \.status).receive(on: RunLoop.main).sink { [weak self] s in
            guard let self else { return }
            switch s {
            case .readyToPlay:
                Task { await self.loadTracks(asset) }
            case .failed:
                let ext = url.pathExtension.lowercased()
                self.error = ["mkv", "avi", "ts"].contains(ext)
                    ? "iOS cannot play .\(ext) files directly. Use an HLS (.m3u8) or MP4 source, or an Emby/Jellyfin server, which converts them."
                    : "The stream could not be played. Check the connection or try again later."
            default: break
            }
        }.store(in: &itemBag)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: pi).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.ended = true }.store(in: &itemBag)
        player.replaceCurrentItem(with: pi)
        if seconds > 0 { player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
        play()
        updateNowPlaying(item)
    }

    private func loadTracks(_ asset: AVURLAsset) async {
        audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
        subtitleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
        audioOptions = audioGroup?.options ?? []
        subtitleOptions = (subtitleGroup?.options ?? []).filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
        if let item = player.currentItem {
            selectedAudio = audioGroup.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) }
            selectedSubtitle = subtitleGroup.flatMap { item.currentMediaSelection.selectedMediaOption(in: $0) }
        }
    }

    func selectAudio(_ o: AVMediaSelectionOption) {
        guard let g = audioGroup else { return }
        player.currentItem?.select(o, in: g)
        selectedAudio = o
    }

    /// nil = subtitles off
    func selectSubtitle(_ o: AVMediaSelectionOption?) {
        guard let g = subtitleGroup else { return }
        player.currentItem?.select(o, in: g)
        selectedSubtitle = o
    }

    func play() { player.playImmediately(atRate: rate) }
    func pause() { player.pause() }
    func toggle() { isPlaying ? pause() : play() }

    func seek(to s: Double) {
        let t = max(0, duration > 0 ? min(s, duration - 1) : s)
        current = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
    }

    func skip(_ d: Double) { seek(to: current + d) }

    func cycleGravity() {
        gravity = gravity == .resizeAspect ? .resizeAspectFill : (gravity == .resizeAspectFill ? .resize : .resizeAspect)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Lock screen / Control Center

    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { [weak self] _ in self?.skip(10); return .success }
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(-10); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.onNext?(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.onPrevious?(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying(_ item: PlayItem) {
        var info: [String: Any] = [MPMediaItemPropertyTitle: item.title]
        if let s = item.subtitle { info[MPMediaItemPropertyArtist] = s }
        info[MPNowPlayingInfoPropertyIsLiveStream] = item.live
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
