import SwiftUI

/// Movies or series: category chips, "Continue watching" and a poster grid.
@MainActor
struct VODView: View {
    @EnvironmentObject var library: Library
    let kind: ItemKind
    @State private var group: String?

    private var all: [MediaItem] { kind == .movie ? library.catalog.movies : library.catalog.series }
    private var shown: [MediaItem] { group == nil ? all : all.filter { $0.group == group } }
    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupChips(groups: Catalog.groups(all), selected: $group)
                if kind == .movie && group == nil && !library.continueWatching.isEmpty {
                    Text("Continue watching").font(.headline).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(library.continueWatching) { m in
                                NavigationLink(value: m) { PosterCard(item: m).frame(width: 120) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                if shown.isEmpty {
                    EmptyStateView(text: kind == .movie ? "No movies in this playlist." : "No series in this playlist.")
                        .frame(minHeight: 300)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(shown) { m in
                            NavigationLink(value: m) { PosterCard(item: m) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .refreshable { await library.reload() }
        .navigationTitle(kind == .movie ? "Movies" : "Series")
        .navigationDestination(for: MediaItem.self) { m in
            if m.kind == .series { SeriesDetailView(series: m) } else { MovieDetailView(movie: m) }
        }
    }
}

@MainActor
struct MovieDetailView: View {
    @EnvironmentObject var library: Library
    let movie: MediaItem
    @State private var playing = false
    @State private var fromStart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    PosterCard(item: movie).frame(width: 140)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(movie.title).font(.title2.bold())
                        HStack(spacing: 10) {
                            if let y = movie.year { Text(y) }
                            if let r = movie.rating { Label(r, systemImage: "star.fill") }
                        }
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        Text(movie.group).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                let pos = library.position(for: movie.id)
                HStack {
                    Button { fromStart = false; playing = true } label: {
                        Label(pos > 0 ? "Resume \(timeText(pos))" : "Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    if pos > 0 {
                        Button { fromStart = true; playing = true } label: { Label("From start", systemImage: "backward.end.fill") }
                            .buttonStyle(.bordered)
                    }
                }
                Button { library.toggleFavorite(movie) } label: {
                    Label(library.isFavorite(movie) ? "In my list" : "Add to my list", systemImage: library.isFavorite(movie) ? "checkmark" : "plus")
                }
                if let p = movie.plot { Text(p).foregroundStyle(Theme.muted) }
            }
            .padding()
        }
        .background(Theme.navy)
        .fullScreenCover(isPresented: $playing) {
            PlayerView(title: movie.title, url: movie.url, resumeKey: movie.id, startFromBeginning: fromStart)
        }
    }
}

func timeText(_ s: Double) -> String {
    let t = Int(s)
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}
