import SwiftUI

@MainActor
struct SearchView: View {
    @EnvironmentObject var library: Library
    @State private var query = ""
    @State private var playing: PlayerLaunch?

    private func matches(_ items: [MediaItem]) -> [MediaItem] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard q.count >= 2 else { return [] }
        return Array(items.lazy.filter { $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q) }.prefix(60))
    }

    var body: some View {
        List {
            let live = matches(library.catalog.live)
            let movies = matches(library.catalog.movies)
            let series = matches(library.catalog.series)
            if !live.isEmpty {
                Section("Live TV") {
                    ForEach(live) { ch in Button { playing = PlayerLaunch(items: live.map { $0.playItem() }, index: live.firstIndex(of: ch) ?? 0) } label: { ChannelRow(item: ch) }.foregroundStyle(.white) }
                }
            }
            if !movies.isEmpty {
                Section("Movies") { ForEach(movies) { m in NavigationLink(value: m) { Text(m.title) } } }
            }
            if !series.isEmpty {
                Section("Series") { ForEach(series) { m in NavigationLink(value: m) { Text(m.title) } } }
            }
            if query.count >= 2 && live.isEmpty && movies.isEmpty && series.isEmpty {
                Text("No results").foregroundStyle(Theme.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.navy)
        .searchable(text: $query, prompt: "Channels, movies, series")
        .navigationTitle("Search")
        .navigationDestination(for: MediaItem.self) { m in
            if m.kind == .series { SeriesDetailView(series: m) } else { MovieDetailView(movie: m) }
        }
        .fullScreenCover(item: $playing) { p in PlayerScreen(items: p.items, index: p.index) }
    }
}
