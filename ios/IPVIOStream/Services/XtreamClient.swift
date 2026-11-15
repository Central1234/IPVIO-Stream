import Foundation

/// Xtream Codes login via player_api.php. Live channels are played as HLS (.m3u8), which AVPlayer supports;
/// movies and episodes keep the provider's container (MP4 plays natively, MKV needs a different player, see README).
struct XtreamClient {
    let server: String
    let user: String
    let pass: String
    /// Same fallback as the Android app (#90): some providers refuse the VLC identifier.
    var userAgent: String = "VLC/3.0.21 LibVLC/3.0.21"

    private var base: String {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        return s
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    private func api(_ action: String?, _ extra: String = "") -> URL? {
        var s = "\(base)/player_api.php?username=\(enc(user))&password=\(enc(pass))"
        if let a = action { s += "&action=\(a)" }
        return URL(string: s + extra)
    }

    private func json(_ action: String?, _ extra: String = "") async throws -> Any {
        guard let url = api(action, extra) else { throw SourceError.badAddress }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw SourceError.accessDenied(code) }
        guard (200..<300).contains(code) else { throw SourceError.http(code) }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    func load() async throws -> Catalog {
        // Check the login first so a wrong password gives a clear message
        let info = try await json(nil) as? [String: Any]
        if let auth = (info?["user_info"] as? [String: Any])?["auth"], "\(auth)" == "0" { throw SourceError.wrongLogin }

        async let liveCats = categories("get_live_categories")
        async let vodCats = categories("get_vod_categories")
        async let seriesCats = categories("get_series_categories")
        async let liveRaw = list("get_live_streams")
        async let vodRaw = list("get_vod_streams")
        async let seriesRaw = list("get_series")

        let lc = try await liveCats, vc = try await vodCats, sc = try await seriesCats
        var cat = Catalog()
        cat.live = try await liveRaw.compactMap { (d: [String: Any]) -> MediaItem? in
            guard let id = str(d["stream_id"]), let name = str(d["name"]) else { return nil }
            return MediaItem(id: "x-live-\(id)", kind: .live, title: name, group: lc[str(d["category_id"]) ?? ""] ?? "Live TV",
                             logo: url(d["stream_icon"]), url: URL(string: "\(base)/live/\(enc(user))/\(enc(pass))/\(id).m3u8"))
        }
        cat.movies = try await vodRaw.compactMap { (d: [String: Any]) -> MediaItem? in
            guard let id = str(d["stream_id"]), let name = str(d["name"]) else { return nil }
            let ext = str(d["container_extension"]) ?? "mp4"
            let (title, year) = M3UParser.splitYear(name)
            return MediaItem(id: "x-movie-\(id)", kind: .movie, title: title, group: vc[str(d["category_id"]) ?? ""] ?? "Movies",
                             logo: url(d["stream_icon"]), url: URL(string: "\(base)/movie/\(enc(user))/\(enc(pass))/\(id).\(ext)"),
                             year: year ?? str(d["year"]), rating: str(d["rating"]), added: date(d["added"]))
        }
        // Newest first, like the Android app's "Recently added" (#22)
        cat.movies.sort { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
        cat.series = try await seriesRaw.compactMap { (d: [String: Any]) -> MediaItem? in
            guard let id = str(d["series_id"]), let name = str(d["name"]) else { return nil }
            return MediaItem(id: "x-series-\(id)", kind: .series, title: name, group: sc[str(d["category_id"]) ?? ""] ?? "Series",
                             logo: url(d["cover"]), url: nil, year: str(d["year"]) ?? str(d["releaseDate"]).map { String($0.prefix(4)) },
                             plot: str(d["plot"]), rating: str(d["rating"]), added: date(d["last_modified"]), seriesRef: id)
        }
        if cat.isEmpty { throw SourceError.empty }
        return cat
    }

    /// Episodes of one series (loaded when it is opened). "episodes" is a season map or a list depending on the provider.
    func episodes(seriesId: String) async throws -> [Episode] {
        let root = try await json("get_series_info", "&series_id=\(seriesId)") as? [String: Any]
        var raw: [([String: Any], Int?)] = []
        func collect(_ v: Any?, _ season: Int?) {
            if let arr = v as? [Any] { arr.forEach { collect($0, season) } }
            else if let d = v as? [String: Any] {
                if d["id"] != nil && (d["episode_num"] != nil || d["container_extension"] != nil) { raw.append((d, season)) }
                else { for (k, x) in d { collect(x, Int(k) ?? season) } }
            }
        }
        collect(root?["episodes"], nil)
        let eps: [Episode] = raw.compactMap { (pair: ([String: Any], Int?)) -> Episode? in
            let (d, season) = pair
            guard let id = str(d["id"]) else { return nil }
            let ext = str(d["container_extension"]) ?? "mp4"
            let s = Int(str(d["season"]) ?? "") ?? season ?? 1
            let n = Int(str(d["episode_num"]) ?? "") ?? 0
            let info = d["info"] as? [String: Any]
            guard let u = URL(string: "\(base)/series/\(enc(user))/\(enc(pass))/\(id).\(ext)") else { return nil }
            return Episode(id: "x-ep-\(id)", season: s, number: n, title: str(d["title"]) ?? "Episode \(n)", url: u,
                           plot: str(info?["plot"]), still: url(info?["movie_image"]))
        }
        return eps.sorted { ($0.season, $0.number) < ($1.season, $1.number) }
    }

    private func categories(_ action: String) async throws -> [String: String] {
        var out: [String: String] = [:]
        for d in try await list(action) {
            if let id = str(d["category_id"]), let n = str(d["category_name"]) { out[id] = n }
        }
        return out
    }

    private func list(_ action: String) async throws -> [[String: Any]] {
        (try await json(action) as? [[String: Any]]) ?? []
    }

    private func str(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    private func url(_ v: Any?) -> URL? { str(v).flatMap { URL(string: $0) } }

    private func date(_ v: Any?) -> Date? { str(v).flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) } }
}
