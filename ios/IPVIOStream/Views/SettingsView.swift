import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject var library: Library
    @State private var adding = false

    var body: some View {
        List {
            Section("Playlists") {
                ForEach(library.sources) { s in
                    Button {
                        Task { await library.activate(s) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s.name)
                                Text(s.kind.label).font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if s.id == library.activeId { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green) }
                        }
                    }
                    .foregroundStyle(.white)
                }
                .onDelete { idx in idx.map { library.sources[$0] }.forEach(library.remove) }
                Button { adding = true } label: { Label("Add playlist", systemImage: "plus") }
                Button { Task { await library.reload() } } label: { Label("Reload active playlist", systemImage: "arrow.clockwise") }
                    .disabled(library.loading)
            }
            if let e = library.error { Section { Text(e).foregroundStyle(.red) } }
            Section("Content") {
                LabeledContent("Live channels", value: "\(library.catalog.live.count)")
                LabeledContent("Movies", value: "\(library.catalog.movies.count)")
                LabeledContent("Series", value: "\(library.catalog.series.count)")
            }
            Section("About") {
                Text("IPVIO Stream is a player and provides no content. Only use sources you are allowed to use.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                Text("Free software under the GNU GPL v3.").font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.navy)
        .navigationTitle("Settings")
        .sheet(isPresented: $adding) { NavigationStack { AddSourceView() } }
    }
}
