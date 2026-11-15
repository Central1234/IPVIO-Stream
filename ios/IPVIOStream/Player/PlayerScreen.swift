import AVKit
import Combine
import SwiftUI

/// Full-screen player with IPVIO's own controls:
/// tap = show/hide controls, double tap left/right = 10 s back/forward, pinch = fill/fit, drag on the timeline = seek,
/// audio and subtitle tracks, speed, picture format, AirPlay, Picture in Picture, next episode with countdown,
/// and for live TV a channel list next to the picture (beside it on wide screens such as the iPhone Duo inner display).
@MainActor
struct PlayerScreen: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

    let items: [PlayItem]
    @State var index: Int
    var startFromBeginning = false

    @StateObject private var engine = PlayerEngine()
    @State private var showControls = true
    @State private var showChannels = false
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing: Double?
    @State private var flash: String?
    @State private var countdown: Int?
    @State private var saveTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var item: PlayItem { items[min(max(index, 0), items.count - 1)] }
    private var isLive: Bool { item.live }
    private var hasNext: Bool { !isLive && index + 1 < items.count }
    private var wide: Bool { hSize == .regular }

    init(items: [PlayItem], index: Int = 0, startFromBeginning: Bool = false) {
        self.items = items
        self._index = State(initialValue: index)
        self.startFromBeginning = startFromBeginning
    }

    var body: some View {
        HStack(spacing: 0) {
            videoArea
            if isLive && showChannels && wide {
                ChannelPanel(items: items, current: index) { i in zap(to: i) }
                    .frame(width: 340)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(.hidden)
        .onAppear { start(index, from: startFromBeginning ? 0 : nil); poke() }
        .onDisappear { save(); engine.stop() }
        .onReceive(saveTimer) { _ in save() }
        .onChange(of: engine.ended) { _, ended in if ended { finished() } }
        .onChange(of: engine.isPlaying) { _, _ in poke() }
    }

    // MARK: Video and gestures

    private var videoArea: some View {
        ZStack {
            Color.black
            PlayerSurface(engine: engine).ignoresSafeArea()

            // Gesture layer: left and right halves for double tap seeking
            HStack(spacing: 0) {
                tapZone(seconds: -10)
                tapZone(seconds: 10)
            }
            .gesture(MagnifyGesture().onEnded { v in
                withAnimation { engine.gravity = v.magnification > 1 ? .resizeAspectFill : .resizeAspect }
                showFlash(engine.gravity == .resizeAspect ? "Fit" : "Fill")
            })

            if engine.isBuffering && engine.error == nil {
                ProgressView().controlSize(.large).tint(.white).allowsHitTesting(false)
            }
            if let f = flash {
                Text(f).font(.headline).padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule()).transition(.opacity).allowsHitTesting(false)
            }
            if let e = engine.error { errorCard(e) }
            if showControls { controls.transition(.opacity) }
            if let c = countdown, hasNext { nextCard(c) }
            if isLive && showChannels && !wide {
                HStack {
                    Spacer()
                    ChannelPanel(items: items, current: index) { i in zap(to: i) }
                        .frame(maxWidth: 360)
                        .transition(.move(edge: .trailing))
                }
            }
        }
    }

    private func tapZone(seconds: Double) -> some View {
        Color.clear.contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !isLive else { return }
                engine.skip(seconds)
                showFlash(seconds < 0 ? "−10 s" : "+10 s")
                poke()
            }
            .onTapGesture {
                if showChannels && !wide { withAnimation { showChannels = false }; return }
                withAnimation(.easeOut(duration: 0.2)) { showControls.toggle() }
                if showControls { poke() }
            }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 30)
                .background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
            Spacer()
            centerButtons
            Spacer()
            bottomBar
                .padding(.horizontal).padding(.top, 30).padding(.bottom, 10)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
        }
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            CircleButton(icon: "chevron.down") { close() }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).lineLimit(1)
                if let s = item.subtitle { Text(s).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if isLive && items.count > 1 {
                CircleButton(icon: "list.bullet", active: showChannels) { withAnimation(.easeInOut) { showChannels.toggle() }; poke() }
            }
            settingsMenu
            CircleButton(icon: gravityIcon) { withAnimation { engine.cycleGravity() }; showFlash(gravityName); poke() }
            if engine.pipPossible {
                CircleButton(icon: "pip.enter") { engine.pip?.startPictureInPicture() }
            }
            RoutePicker().frame(width: 40, height: 40).background(.black.opacity(0.35), in: Circle())
        }
    }

    private var centerButtons: some View {
        HStack(spacing: wide ? 70 : 48) {
            if isLive {
                if items.count > 1 { BigButton(icon: "chevron.up", size: 26) { zap(by: -1) } }
            } else {
                BigButton(icon: "gobackward.10", size: 30) { engine.skip(-10); poke() }
            }
            BigButton(icon: engine.isPlaying ? "pause.fill" : "play.fill", size: 44) { engine.toggle(); poke() }
                .contentTransition(.symbolEffect(.replace))
            if isLive {
                if items.count > 1 { BigButton(icon: "chevron.down", size: 26) { zap(by: 1) } }
            } else {
                BigButton(icon: "goforward.10", size: 30) { engine.skip(10); poke() }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if isLive {
                HStack {
                    Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.red, in: Capsule())
                    Spacer()
                }
            } else {
                Scrubber(value: scrubbing ?? engine.current, duration: engine.duration) { v in
                    scrubbing = v
                    poke()
                } onEnd: { v in
                    engine.seek(to: v)
                    scrubbing = nil
                    poke()
                }
                HStack {
                    Text(timeText(scrubbing ?? engine.current)).monospacedDigit()
                    Spacer()
                    if hasNext {
                        Button { playNext() } label: {
                            Label("Next episode", systemImage: "forward.end.fill").font(.subheadline.weight(.semibold))
                        }
                    }
                    Spacer()
                    Text("−" + timeText(max(0, engine.duration - (scrubbing ?? engine.current)))).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            if !engine.audioOptions.isEmpty {
                Section("Audio") {
                    ForEach(engine.audioOptions, id: \.self) { o in
                        Button { engine.selectAudio(o) } label: {
                            if o == engine.selectedAudio { Label(o.displayName, systemImage: "checkmark") } else { Text(o.displayName) }
                        }
                    }
                }
            }
            if !engine.subtitleOptions.isEmpty {
                Section("Subtitles") {
                    Button { engine.selectSubtitle(nil) } label: {
                        if engine.selectedSubtitle == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
                    }
                    ForEach(engine.subtitleOptions, id: \.self) { o in
                        Button { engine.selectSubtitle(o) } label: {
                            if o == engine.selectedSubtitle { Label(o.displayName, systemImage: "checkmark") } else { Text(o.displayName) }
                        }
                    }
                }
            }
            if !isLive {
                Section("Speed") {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { (r: Double) in
                        Button { engine.rate = Float(r) } label: {
                            let t = r == 1 ? "Normal" : String(format: "%gx", r)
                            if Float(r) == engine.rate { Label(t, systemImage: "checkmark") } else { Text(t) }
                        }
                    }
                }
            }
            Section("Picture") {
                Button("Fit") { engine.gravity = .resizeAspect }
                Button("Fill (crop)") { engine.gravity = .resizeAspectFill }
                Button("Stretch") { engine.gravity = .resize }
            }
        } label: {
            Image(systemName: "gearshape.fill").font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40).background(.black.opacity(0.35), in: Circle())
        }
        .simultaneousGesture(TapGesture().onEnded { poke() })
    }

    private var gravityIcon: String {
        switch engine.gravity {
        case .resizeAspectFill: return "arrow.down.right.and.arrow.up.left"
        case .resize: return "arrow.left.and.right"
        default: return "arrow.up.left.and.arrow.down.right"
        }
    }

    private var gravityName: String {
        switch engine.gravity {
        case .resizeAspectFill: return "Fill"
        case .resize: return "Stretch"
        default: return "Fit"
        }
    }

    private func errorCard(_ e: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.yellow)
            Text(e).multilineTextAlignment(.center)
            HStack {
                Button("Try again") { start(index, from: engine.current) }.buttonStyle(.borderedProminent)
                if isLive && items.count > 1 { Button("Next channel") { zap(by: 1) }.buttonStyle(.bordered) }
            }
        }
        .padding(24).frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }

    private func nextCard(_ c: Int) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Up next in \(c)").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Text(items[index + 1].title).font(.headline).lineLimit(2)
                    HStack {
                        Button("Play now") { playNext() }.buttonStyle(.borderedProminent)
                        Button("Cancel") { countdown = nil }.buttonStyle(.bordered)
                    }
                }
                .padding(18).frame(maxWidth: 320, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(24)
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: Actions

    private func start(_ i: Int, from: Double?) {
        save()
        index = i
        countdown = nil
        let it = item
        let pos = from ?? it.resumeKey.map { library.position(for: $0) } ?? 0
        engine.onNext = { [self] in if isLive { zap(by: 1) } else if hasNext { playNext() } }
        engine.onPrevious = { [self] in if isLive { zap(by: -1) } else if index > 0 { start(index - 1, from: nil) } }
        engine.load(it, at: pos)
    }

    private func zap(by d: Int) {
        guard !items.isEmpty else { return }
        zap(to: (index + d + items.count) % items.count)
        showFlash(item.title)
    }

    private func zap(to i: Int) { start(i, from: 0); poke() }

    private func playNext() {
        guard hasNext else { return }
        start(index + 1, from: nil)
        poke()
    }

    private func finished() {
        save()
        guard hasNext else { withAnimation { showControls = true }; return }
        countdown = 8
        Task {
            while let c = countdown, c > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard countdown != nil else { return }
                countdown = c - 1
            }
            if countdown == 0 { playNext() }
        }
    }

    private func save() {
        guard let k = item.resumeKey else { return }
        let t = engine.player.currentTime().seconds
        let d = engine.player.currentItem?.duration.seconds ?? 0
        if t.isFinite && t > 0 { library.savePosition(t, duration: d.isFinite ? d : 0, for: k) }
    }

    private func close() { save(); engine.stop(); dismiss() }

    /// Show the controls and hide them again after 4 s while playing.
    private func poke() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, engine.isPlaying, scrubbing == nil, engine.error == nil else { return }
            withAnimation(.easeOut(duration: 0.3)) { showControls = false }
        }
    }

    private func showFlash(_ t: String) {
        withAnimation { flash = t }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if flash == t { withAnimation { flash = nil } }
        }
    }
}

// MARK: - Pieces

private struct CircleButton: View {
    let icon: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(active ? Theme.green.opacity(0.9) : .black.opacity(0.35), in: Circle())
                .foregroundStyle(active ? Theme.navy : .white)
        }
        .buttonStyle(.plain)
    }
}

private struct BigButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .semibold))
                .frame(width: size * 2, height: size * 2)
                .background(.black.opacity(0.3), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Timeline with a large touch area; the thumb grows while dragging.
struct Scrubber: View {
    let value: Double
    let duration: Double
    let onChange: (Double) -> Void
    let onEnd: (Double) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let frac = duration > 0 ? min(max(value / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: dragging ? 8 : 4)
                Capsule().fill(Theme.green).frame(width: g.size.width * frac, height: dragging ? 8 : 4)
                Circle().fill(.white).frame(width: dragging ? 22 : 14, height: dragging ? 22 : 14)
                    .offset(x: g.size.width * frac - (dragging ? 11 : 7))
                    .shadow(radius: 3)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    withAnimation(.easeOut(duration: 0.1)) { dragging = true }
                    onChange(position(v.location.x, g.size.width))
                }
                .onEnded { v in
                    withAnimation(.easeOut(duration: 0.15)) { dragging = false }
                    onEnd(position(v.location.x, g.size.width))
                })
        }
        .frame(height: 28)
        .animation(.easeOut(duration: 0.15), value: dragging)
    }

    private func position(_ x: CGFloat, _ w: CGFloat) -> Double {
        guard w > 0, duration > 0 else { return 0 }
        return Double(min(max(x / w, 0), 1)) * duration
    }
}

/// Channel list in the player (live TV).
struct ChannelPanel: View {
    let items: [PlayItem]
    let current: Int
    let pick: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, ch in
                    Button { pick(i) } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: ch.artwork) { img in img.resizable().scaledToFit() } placeholder: {
                                Image(systemName: "tv").foregroundStyle(Theme.muted)
                            }
                            .frame(width: 48, height: 30)
                            Text(ch.title).lineLimit(1)
                            Spacer()
                            if i == current { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.green) }
                        }
                    }
                    .listRowBackground(i == current ? Theme.green.opacity(0.18) : Color.clear)
                    .foregroundStyle(.white)
                    .id(i)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .onAppear { proxy.scrollTo(current, anchor: .center) }
        }
    }
}
