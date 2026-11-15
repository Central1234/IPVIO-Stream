import SwiftUI

/// Live TV. Narrow screens: category chips above the channel list.
/// Wide screens (iPhone Duo unfolded, iPad): categories in a column on the left, channels on the right.
@MainActor
struct LiveView: View {
    @EnvironmentObject var library: Library
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var group: String?
    @State private var favoritesOnly = false
    @State private var playing: PlayerLaunch?

    private var channels: [MediaItem] {
        library.catalog.live.filter { ch in
            (group == nil || ch.group == group) && (!favoritesOnly || library.isFavorite(ch))
        }
    }

    var body: some View {
        Group {
            if hSize == .regular { wide } else { narrow }
        }
        .navigationTitle(favoritesOnly ? "Favourites" : (group ?? "Live TV"))
        .toolbar {
            ToolbarItem {
                Button { favoritesOnly.toggle() } label: { Image(systemName: favoritesOnly ? "star.fill" : "star") }
            }
        }
        .fullScreenCover(item: $playing) { p in PlayerScreen(items: p.items, index: p.index) }
    }

    private var narrow: some View {
        VStack(spacing: 8) {
            GroupChips(groups: Catalog.groups(library.catalog.live), selected: $group)
            channelList
        }
    }

    private var wide: some View {
        HStack(spacing: 0) {
            List(selection: Binding<String?>(get: { group ?? "" }, set: { group = ($0 ?? "").isEmpty ? nil : $0 })) {
                Label("All channels", systemImage: "square.grid.2x2").tag("")
                Section("Categories") {
                    ForEach(Catalog.groups(library.catalog.live), id: \.self) { g in
                        Text(g).lineLimit(1).tag(g)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Theme.surface.opacity(0.5))
            .frame(width: 300)
            Divider()
            channelList
        }
    }

    @ViewBuilder private var channelList: some View {
        let list = channels
        if list.isEmpty {
            EmptyStateView(text: favoritesOnly ? "No favourite channels yet. Swipe a channel to add it." : "No live channels in this playlist.")
        } else {
            List(Array(list.enumerated()), id: \.element.id) { i, ch in
                Button { playing = PlayerLaunch(items: list.map { $0.playItem() }, index: i) } label: {
                    ChannelRow(item: ch, favorite: library.isFavorite(ch), large: hSize == .regular)
                }
                .foregroundStyle(.white)
                .swipeActions {
                    Button { library.toggleFavorite(ch) } label: {
                        Label(library.isFavorite(ch) ? "Remove" : "Favourite", systemImage: library.isFavorite(ch) ? "star.slash" : "star")
                    }
                    .tint(Theme.green)
                }
                .contextMenu {
                    Button { library.toggleFavorite(ch) } label: {
                        Label(library.isFavorite(ch) ? "Remove from favourites" : "Add to favourites", systemImage: "star")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await library.reload() }
        }
    }
}

/// What the player opens with: the list (channels or episodes) and where to start.
struct PlayerLaunch: Identifiable {
    let id = UUID()
    let items: [PlayItem]
    let index: Int
    var fromStart = false
}
