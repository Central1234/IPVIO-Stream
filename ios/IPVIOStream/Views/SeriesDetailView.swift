import SwiftUI

/// Series: seasons and episodes. Xtream and Emby load the episodes when the series is opened.
@MainActor
struct SeriesDetailView: View {
    @EnvironmentObject var library: Library
    let series: MediaItem
    @State private var episodes: [Episode] = []
    @State private var season = 1
    @State private var loading = true
    @State private var failed = false
    @State private var playing: Episode?

    private var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    PosterCard(item: series).frame(width: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(series.title).font(.title3.bold())
                        if let y = series.year { Text(y).foregroundStyle(Theme.muted) }
                        if let p = series.plot { Text(p).font(.footnote).foregroundStyle(Theme.muted).lineLimit(6) }
                    }
                }
                .listRowBackground(Color.clear)
            }
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
                    Picker("Season", selection: $season) {
                        ForEach(seasons, id: \.self) { Text("Season \($0)").tag($0) }
                    }
                }
                Section {
                    ForEach(episodes.filter { $0.season == season }) { e in
                        Button { playing = e } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(e.label).font(.caption.monospacedDigit()).foregroundStyle(Theme.green)
                                    Text(e.title).lineLimit(1)
                                    Spacer()
                                    if library.position(for: e.id) > 0 { Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.muted) }
                                }
                                if let p = e.plot { Text(p).font(.caption).foregroundStyle(Theme.muted).lineLimit(2) }
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.navy)
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $playing) { e in
            PlayerView(title: "\(series.title) \(e.label)", url: e.url, resumeKey: e.id, next: nextEpisode(after: e))
        }
    }

    private func load() async {
        loading = true
        failed = false
        do {
            episodes = try await library.episodes(for: series)
            season = seasons.first ?? 1
        } catch {
            failed = true
        }
        loading = false
    }

    private func nextEpisode(after e: Episode) -> Episode? {
        guard let i = episodes.firstIndex(of: e), i + 1 < episodes.count else { return nil }
        return episodes[i + 1]
    }
}
