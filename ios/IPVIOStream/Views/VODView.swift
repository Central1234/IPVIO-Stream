import SwiftUI

/// Movies or series. Narrow screens: category chips, "Continue watching", poster grid.
/// Wide screens (iPhone Duo unfolded, iPad): a category column, a large featured banner and bigger posters.
@MainActor
struct VODView: View {
    @EnvironmentObject var library: Library
    @Environment(\.horizontalSizeClass) private var hSize
    let kind: ItemKind
    @State private var group: String?

    private var wide: Bool { hSize == .regular }
    private var all: [MediaItem] { kind == .movie ? library.catalog.movies : library.catalog.series }
    private var shown: [MediaItem] { group == nil ? all : all.filter { $0.group == group } }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: wide ? 150 : 110, maximum: wide ? 210 : 180), spacing: wide ? 20 : 14)] }

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 0) {
                    categoryColumn.frame(width: 260)
                    Divider()
                    content
                }
            } else {
                content
            }
        }
        .navigationTitle(group ?? (kind == .movie ? "Movies" : "Series"))
        .navigationDestination(for: MediaItem.self) { m in
            if m.kind == .series { SeriesDetailView(series: m) } else { MovieDetailView(movie: m) }
        }
    }

    private var categoryColumn: some View {
        List(selection: Binding<String?>(get: { group ?? "" }, set: { group = ($0 ?? "").isEmpty ? nil : $0 })) {
            Label(kind == .movie ? "All movies" : "All series", systemImage: "square.grid.2x2").tag("")
            Section("Categories") {
                ForEach(Catalog.groups(all), id: \.self) { g in Text(g).lineLimit(1).tag(g) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.surface.opacity(0.5))
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !wide { GroupChips(groups: Catalog.groups(all), selected: $group) }
                if wide && group == nil, let f = featured { FeaturedBanner(item: f) }
                if kind == .movie && group == nil && !library.continueWatching.isEmpty {
                    Text("Continue watching").font(.title3.bold()).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(library.continueWatching) { m in
                                NavigationLink(value: m) { PosterCard(item: m).frame(width: wide ? 150 : 120) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                if shown.isEmpty {
                    EmptyStateView(text: kind == .movie ? "No movies in this playlist." : "No series in this playlist.")
                        .frame(minHeight: 300)
                } else {
                    LazyVGrid(columns: columns, spacing: wide ? 26 : 18) {
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
    }

    /// Newest title with a picture.
    private var featured: MediaItem? { all.first { $0.logo != nil } }
}

/// Large banner for the first title on wide screens.
@MainActor
struct FeaturedBanner: View {
    let item: MediaItem

    var body: some View {
        NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: item.logo) { img in img.resizable().scaledToFill() } placeholder: { Theme.surface }
                    .frame(height: 280).frame(maxWidth: .infinity).clipped()
                    .blur(radius: 18).opacity(0.55)
                HStack(alignment: .bottom, spacing: 20) {
                    AsyncImage(url: item.logo) { img in img.resizable().scaledToFill() } placeholder: { Theme.surface }
                        .frame(width: 150, height: 225).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(radius: 12)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NEW").font(.caption.bold()).foregroundStyle(Theme.green)
                        Text(item.title).font(.largeTitle.bold()).lineLimit(2)
                        HStack(spacing: 10) {
                            if let y = item.year { Text(y) }
                            if let r = item.rating { Label(r, systemImage: "star.fill") }
                            Text(item.group)
                        }
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        if let p = item.plot { Text(p).font(.callout).foregroundStyle(.white.opacity(0.8)).lineLimit(3) }
                    }
                    Spacer()
                }
                .padding(24)
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
struct MovieDetailView: View {
    @EnvironmentObject var library: Library
    @Environment(\.horizontalSizeClass) private var hSize
    let movie: MediaItem
    @State private var playing: PlayerLaunch?

    var body: some View {
        ScrollView {
            if hSize == .regular {
                HStack(alignment: .top, spacing: 32) {
                    PosterCard(item: movie).frame(width: 260)
                    info
                }
                .padding(32)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        PosterCard(item: movie).frame(width: 140)
                        header
                    }
                    actions
                    if let p = movie.plot { Text(p).foregroundStyle(Theme.muted) }
                }
                .padding()
            }
        }
        .background(Theme.navy)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { p in PlayerScreen(items: p.items, index: 0, startFromBeginning: p.fromStart) }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            actions.frame(maxWidth: 480)
            if let p = movie.plot { Text(p).font(.body).foregroundStyle(.white.opacity(0.8)) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(movie.title).font(hSize == .regular ? .largeTitle.bold() : .title2.bold())
            HStack(spacing: 10) {
                if let y = movie.year { Text(y) }
                if let r = movie.rating { Label(r, systemImage: "star.fill") }
            }
            .font(.subheadline).foregroundStyle(Theme.muted)
            Text(movie.group).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private var actions: some View {
        let pos = library.position(for: movie.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { playing = PlayerLaunch(items: [movie.playItem()], index: 0) } label: {
                    Label(pos > 0 ? "Resume \(timeText(pos))" : "Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                if pos > 0 {
                    Button { playing = PlayerLaunch(items: [movie.playItem()], index: 0, fromStart: true) } label: {
                        Label("From start", systemImage: "backward.end.fill")
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
            }
            Button { library.toggleFavorite(movie) } label: {
                Label(library.isFavorite(movie) ? "In my list" : "Add to my list", systemImage: library.isFavorite(movie) ? "checkmark" : "plus")
            }
        }
    }
}

func timeText(_ s: Double) -> String {
    guard s.isFinite else { return "0:00" }
    let t = Int(s)
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}
