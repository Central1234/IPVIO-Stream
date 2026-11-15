import SwiftUI

/// Series: seasons and episodes. Xtream and Emby load the episodes when the series is opened.
/// Wide screens: poster and description on the left, episodes on the right.
@MainActor
struct SeriesDetailView: View {
    @EnvironmentObject var library: Library
    @Environment(\.horizontalSizeClass) private var hSize
    let series: MediaItem
    @State private var episodes: [Episode] = []
    @State private var season = 1
    @State private var loading = true
    @State private var failed = false
    @State private var playing: PlayerLaunch?

    private var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }
    private var seasonEpisodes: [Episode] { episodes.filter { $0.season == season } }

    var body: some View {
        Group {
            if hSize == .regular {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { info.padding(28) }.frame(width: 340)
                    Divider()
                    episodeList
                }
            } else {
                List {
                    Section { info.listRowBackground(Color.clear) }
                    episodeRows
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.navy)
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $playing) { p in PlayerScreen(items: p.items, index: p.index) }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hSize == .regular {
                PosterCard(item: series).frame(width: 220)
            }
            HStack(alignment: .top, spacing: 14) {
                if hSize != .regular { PosterCard(item: series).frame(width: 110) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(series.title).font(.title2.bold())
                    if let y = series.year { Text(y).foregroundStyle(Theme.muted) }
                    if !episodes.isEmpty { Text("\(seasons.count) seasons · \(episodes.count) episodes").font(.caption).foregroundStyle(Theme.muted) }
                }
            }
            if let next = resumeTarget {
                Button { play(next) } label: {
                    Label(library.position(for: next.id) > 0 ? "Continue \(next.label)" : "Play \(next.label)", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            if let p = series.plot { Text(p).font(.footnote).foregroundStyle(Theme.muted) }
        }
    }

    private var episodeList: some View {
        List { episodeRows }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var episodeRows: some View {
        if loading {
            HStack { Spacer(); ProgressView("Loading episodes …"); Spacer() }.listRowBackground(Color.clear)
        } else if failed || episodes.isEmpty {
            VStack(spacing: 10) {
                Text("The episodes could not be loaded. Check your connection or account.").foregroundStyle(Theme.muted)
                Button("Try again") { Task { await load() } }
            }
            .listRowBackground(Color.clear)
        } else {
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { s in
                            Button { season = s } label: {
                                Text("Season \(s)").font(.subheadline.weight(season == s ? .bold : .regular))
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(season == s ? Theme.green : Theme.surface, in: Capsule())
                                    .foregroundStyle(season == s ? Theme.navy : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            ForEach(seasonEpisodes) { e in
                Button { play(e) } label: { EpisodeRow(episode: e, progress: library.position(for: e.id), large: hSize == .regular) }
                    .foregroundStyle(.white)
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// The episode to continue: the last one with a saved position, otherwise the first.
    private var resumeTarget: Episode? {
        episodes.last { library.position(for: $0.id) > 0 } ?? episodes.first
    }

    private func play(_ e: Episode) {
        guard let i = episodes.firstIndex(of: e) else { return }
        playing = PlayerLaunch(items: episodes.map { $0.playItem(series: series) }, index: i)
    }

    private func load() async {
        loading = true
        failed = false
        do {
            episodes = try await library.episodes(for: series)
            season = resumeTarget?.season ?? seasons.first ?? 1
        } catch {
            failed = true
        }
        loading = false
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let progress: Double
    let large: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                AsyncImage(url: episode.still) { img in img.resizable().scaledToFill() } placeholder: {
                    ZStack { Theme.surface; Image(systemName: "play.fill").foregroundStyle(Theme.muted) }
                }
            }
            .frame(width: large ? 200 : 128, height: large ? 112 : 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomLeading) {
                if progress > 0 { Rectangle().fill(Theme.green).frame(height: 3) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.label).font(.caption.monospacedDigit()).foregroundStyle(Theme.green)
                Text(episode.title).font(large ? .headline : .subheadline.weight(.semibold)).lineLimit(2)
                if let p = episode.plot { Text(p).font(.caption).foregroundStyle(Theme.muted).lineLimit(large ? 3 : 2) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
