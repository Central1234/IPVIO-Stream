import Foundation
import SwiftUI

/// App state: the saved sources, the loaded catalog of the active source, favourites and resume positions.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var sources: [Source] = []
    @Published var activeId: UUID?
    @Published private(set) var catalog = Catalog()
    @Published private(set) var loading = false
    @Published var error: String?
    @Published private(set) var favorites: Set<String> = []

    private let defaults = UserDefaults.standard
    private var resume: [String: Double] = [:]

    init() {
        if let d = defaults.data(forKey: "sources"), let s = try? JSONDecoder().decode([Source].self, from: d) { sources = s }
        if let a = defaults.string(forKey: "active"), let id = UUID(uuidString: a) { activeId = id }
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        resume = defaults.dictionary(forKey: "resume") as? [String: Double] ?? [:]
        if activeId == nil { activeId = sources.first?.id }
    }

    var active: Source? { sources.first { $0.id == activeId } }

    // MARK: Sources

    func add(_ s: Source, password: String) async {
        s.password = password
        sources.append(s)
        activeId = s.id
        persist()
        await reload()
        // A source that does not load is not kept, so the user can correct the details
        if catalog.isEmpty, error != nil {
            remove(s)
        }
    }

    func remove(_ s: Source) {
        Keychain.delete(account: s.id.uuidString)
        sources.removeAll { $0.id == s.id }
        if activeId == s.id { activeId = sources.first?.id; catalog = Catalog() }
        persist()
    }

    func activate(_ s: Source) async {
        activeId = s.id
        persist()
        await reload()
    }

    func reload() async {
        guard let s = active else { catalog = Catalog(); return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            switch s.kind {
            case .xtream:
                catalog = try await loadXtream(s)
            case .emby:
                catalog = try await EmbyClient(server: s.server, user: s.user, pass: s.password).load()
            case .m3u:
                guard let url = URL(string: s.server.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else { throw SourceError.badAddress }
                var req = URLRequest(url: url, timeoutInterval: 120)
                req.setValue("VLC/3.0.21 LibVLC/3.0.21", forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
                if code == 401 || code == 403 { throw SourceError.accessDenied(code) }
                guard (200..<300).contains(code) else { throw SourceError.http(code) }
                let text = String(decoding: data, as: UTF8.self)
                let parsed = await Task.detached(priority: .userInitiated) { M3UParser.parse(text) }.value
                if parsed.isEmpty { throw SourceError.empty }
                catalog = parsed
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Could not load the playlist. Check the connection and the details."
        }
    }

    /// Xtream with the same fallback as the Android app (#90): on 403 try once with the app's own identifier.
    private func loadXtream(_ s: Source) async throws -> Catalog {
        let key = "ua_native_" + s.id.uuidString
        var client = XtreamClient(server: s.server, user: s.user, pass: s.password)
        if defaults.bool(forKey: key) { client.userAgent = "IPVIOStream-iOS/0.1" }
        do {
            return try await client.load()
        } catch SourceError.accessDenied(let code) where !defaults.bool(forKey: key) {
            client.userAgent = "IPVIOStream-iOS/0.1"
            do {
                let c = try await client.load()
                defaults.set(true, forKey: key)
                return c
            } catch {
                throw SourceError.accessDenied(code)
            }
        }
    }

    func episodes(for item: MediaItem) async throws -> [Episode] {
        if let e = item.episodes { return e }
        guard let s = active, let ref = item.seriesRef else { return [] }
        switch s.kind {
        case .xtream:
            var c = XtreamClient(server: s.server, user: s.user, pass: s.password)
            if defaults.bool(forKey: "ua_native_" + s.id.uuidString) { c.userAgent = "IPVIOStream-iOS/0.1" }
            return try await c.episodes(seriesId: ref)
        case .emby:
            return try await EmbyClient(server: s.server, user: s.user, pass: s.password).episodes(seriesId: ref)
        case .m3u:
            return []
        }
    }

    // MARK: Favourites and resume

    func isFavorite(_ i: MediaItem) -> Bool { favorites.contains(i.id) }

    func toggleFavorite(_ i: MediaItem) {
        if favorites.contains(i.id) { favorites.remove(i.id) } else { favorites.insert(i.id) }
        defaults.set(Array(favorites), forKey: "favorites")
    }

    func position(for key: String) -> Double { resume[key] ?? 0 }

    func savePosition(_ seconds: Double, duration: Double, for key: String) {
        // Near the end counts as watched: start from the beginning next time
        if duration > 0, seconds > duration - 60 { resume[key] = nil } else if seconds > 30 { resume[key] = seconds }
        defaults.set(resume, forKey: "resume")
    }

    var continueWatching: [MediaItem] {
        catalog.movies.filter { resume[$0.id] != nil }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(sources) { defaults.set(d, forKey: "sources") }
        defaults.set(activeId?.uuidString, forKey: "active")
    }
}
