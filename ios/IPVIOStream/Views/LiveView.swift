import SwiftUI

@MainActor
struct LiveView: View {
    @EnvironmentObject var library: Library
    @State private var group: String?
    @State private var favoritesOnly = false
    @State private var playing: MediaItem?

    private var channels: [MediaItem] {
        library.catalog.live.filter { ch in
            (group == nil || ch.group == group) && (!favoritesOnly || library.isFavorite(ch))
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            GroupChips(groups: Catalog.groups(library.catalog.live), selected: $group)
            if channels.isEmpty {
                EmptyStateView(text: favoritesOnly ? "No favourite channels yet. Swipe a channel to add it." : "No live channels in this playlist.")
            } else {
                List(channels) { ch in
                    Button { playing = ch } label: { ChannelRow(item: ch, favorite: library.isFavorite(ch)) }
                        .swipeActions {
                            Button { library.toggleFavorite(ch) } label: {
                                Label(library.isFavorite(ch) ? "Remove" : "Favourite", systemImage: library.isFavorite(ch) ? "star.slash" : "star")
                            }
                            .tint(Theme.green)
                        }
                }
                .listStyle(.plain)
                .refreshable { await library.reload() }
            }
        }
        .navigationTitle("Live TV")
        .toolbar {
            Button { favoritesOnly.toggle() } label: { Image(systemName: favoritesOnly ? "star.fill" : "star") }
        }
        .fullScreenCover(item: $playing) { ch in
            PlayerView(title: ch.title, url: ch.url, resumeKey: nil, zapList: channels, current: ch)
        }
    }
}
