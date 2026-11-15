import SwiftUI

/// Poster with title for movies and series.
struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: item.logo) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    ZStack {
                        Theme.surface
                        Image(systemName: item.kind == .series ? "square.stack" : "film").font(.largeTitle).foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(item.title).font(.footnote.weight(.semibold)).lineLimit(2)
            if let y = item.year { Text(y).font(.caption2).foregroundStyle(Theme.muted) }
        }
    }
}

/// Row for a live channel.
struct ChannelRow: View {
    let item: MediaItem
    var favorite = false
    /// Bigger logo and text on wide screens.
    var large = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.logo) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "tv").foregroundStyle(Theme.muted)
            }
            .frame(width: large ? 80 : 56, height: large ? 50 : 36)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(large ? .title3.weight(.medium) : .body).lineLimit(1)
                if large { Text(item.group).font(.caption).foregroundStyle(Theme.muted).lineLimit(1) }
            }
            Spacer()
            if favorite { Image(systemName: "star.fill").foregroundStyle(Theme.green) }
        }
    }
}

/// Horizontal category chips.
struct GroupChips: View {
    let groups: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected == nil) { selected = nil }
                ForEach(groups, id: \.self) { g in chip(g, selected == g) { selected = g } }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ t: String, _ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(t).font(.subheadline.weight(on ? .bold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? Theme.green : Theme.surface, in: Capsule())
                .foregroundStyle(on ? Theme.navy : .white)
        }
        .buttonStyle(.plain)
    }
}
