import SwiftUI

@MainActor
struct AddSourceView: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    var firstRun = false

    @State private var kind: Source.Kind = .xtream
    @State private var name = ""
    @State private var server = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var busy = false

    private var canAdd: Bool {
        switch kind {
        case .m3u: return !server.isEmpty
        case .xtream: return !server.isEmpty && !user.isEmpty && !pass.isEmpty
        case .emby: return !server.isEmpty && !user.isEmpty
        }
    }

    var body: some View {
        Form {
            Section {
                Text("IPVIO Stream is only a player. It brings no channels, movies, series or playlists of its own. You get the link or login from your IPTV provider or your own server.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            Section("Type") {
                Picker("Type", selection: $kind) {
                    ForEach(Source.Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Details") {
                TextField("Name (optional)", text: $name)
                switch kind {
                case .m3u:
                    TextField("http://…/playlist.m3u", text: $server).keyboardType(.URL)
                case .xtream:
                    TextField("Server (e.g. http://server.tld:8080)", text: $server).keyboardType(.URL)
                    TextField("User name", text: $user)
                    SecureField("Password", text: $pass)
                case .emby:
                    TextField("Server address (e.g. http://192.168.1.20:8096)", text: $server).keyboardType(.URL)
                    TextField("User name", text: $user)
                    SecureField("Password", text: $pass)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            if kind == .emby {
                Section { Text("Movies, series and Live TV from your Emby server appear just like a playlist. Also works with Jellyfin.").font(.footnote).foregroundStyle(Theme.muted) }
            }
            if let e = library.error, !busy {
                Section { Text(e).foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task { await add() }
                } label: {
                    HStack { Spacer(); if busy { ProgressView() } else { Text("Add").bold() }; Spacer() }
                }
                .disabled(!canAdd || busy)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.navy)
        .navigationTitle(firstRun ? "Welcome to IPVIO" : "Add playlist")
    }

    private func add() async {
        busy = true
        defer { busy = false }
        let host = URL(string: server.contains("://") ? server : "http://" + server)?.host ?? "Playlist"
        let s = Source(name: name.isEmpty ? host : name, kind: kind, server: server.trimmingCharacters(in: .whitespaces), user: user.trimmingCharacters(in: .whitespaces))
        await library.add(s, password: kind == .m3u ? "" : pass)
        if library.error == nil && !firstRun { dismiss() }
    }
}
