import Foundation

/// Emby (and Jellyfin) server: sign in, then movies, series with episodes and Live TV.
/// Everything is played as HLS from the server (master.m3u8), so AVPlayer can play any file the server can remux or
/// transcode (MKV, AVI, DTS audio …), which iOS could not play directly.
struct EmbyClient {
    let server: String
    let user: String
    let pass: String

    static let deviceId: String = {
        let k = "emby_device_id"
        if let v = UserDefaults.standard.string(forKey: k) { return v }
        let v = "ipvio-ios-" + UUID().uuidString
        UserDefaults.standard.set(v, forKey: k)
        return v
    }()

    struct Session { let base: String; let userId: String; let token: String }

    static func normalized(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        if let r = s.range(of: "/web", options: [.caseInsensitive, .backwards]), s[r.upperBound...].isEmpty || s[r.upperBound...].hasPrefix("/") {
            s = String(s[..<r.lowerBound])
        }
        if s.lowercased().hasSuffix("/emby") { s = String(s.dropLast(5)) }
        return URL(string: s) != nil ? s : nil
    }

    private func authHeader(_ token: String? = nil) -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        var h = "MediaBrowser Client=\"IPVIO Stream\", Device=\"iOS\", DeviceId=\"\(Self.deviceId)\", Version=\"\(v)\""
        if let t = token { h += ", Token=\"\(t)\"" }
        return h
    }

    func signIn() async throws -> Session {
        guard let root = Self.normalized(server) else { throw SourceError.badAddress }
        var lastError: Error = SourceError.http(404)
        // Emby answers under /emby, Jellyfin without it
        for prefix in ["/emby", ""] {
            let base = root + prefix
            guard let url = URL(string: base + "/Users/AuthenticateByName") else { throw SourceError.badAddress }
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(authHeader(), forHTTPHeaderField: "X-Emby-Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["Username": user, "Pw": pass])
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { throw SourceError.wrongLogin }
            if code == 404 { lastError = SourceError.http(404); continue }
            guard (200..<300).contains(code) else { throw SourceError.http(code) }
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = j["AccessToken"] as? String,
                  let uid = (j["User"] as? [String: Any])?["Id"] as? String else { throw SourceError.invalidResponse }
            return Session(base: base, userId: uid, token: token)
        }
        throw lastError
    }

    func load() async throws -> Catalog {
        let s = try await signIn()
        var cat = Catalog()
        // Live TV is optional (servers without a tuner answer with an error)
        cat.live = (try? await items(s, "/LiveTv/Channels?UserId=\(s.userId)&EnableImages=true&SortBy=SortName").compactMap { d -> MediaItem? in
            guard let id = d["Id"] as? String, let name = d["Name"] as? String else { return nil }
            let num = d["ChannelNumber"] as? String
            return MediaItem(id: "emby-live-\(id)", kind: .live, title: num.map { "\($0) \(name)" } ?? name, group: "Emby Live TV",
                             logo: image(s, id, d), url: hls(s, id, live: true))
        }) ?? []
        cat.movies = try await items(s, "/Users/\(s.userId)/Items?Recursive=true&IncludeItemTypes=Movie&Fields=Genres,ProductionYear,Overview,DateCreated&SortBy=DateCreated&SortOrder=Descending").compactMap { d -> MediaItem? in
            guard let id = d["Id"] as? String, let name = d["Name"] as? String else { return nil }
            return MediaItem(id: "emby-movie-\(id)", kind: .movie, title: name, group: (d["Genres"] as? [String])?.first ?? "Movies",
                             logo: image(s, id, d), url: hls(s, id, live: false), year: (d["ProductionYear"] as? Int).map(String.init),
                             plot: d["Overview"] as? String, rating: (d["CommunityRating"] as? Double).map { String(format: "%.1f", $0) })
        }
        cat.series = try await items(s, "/Users/\(s.userId)/Items?Recursive=true&IncludeItemTypes=Series&Fields=Genres,ProductionYear,Overview&SortBy=SortName").compactMap { d -> MediaItem? in
            guard let id = d["Id"] as? String, let name = d["Name"] as? String else { return nil }
            return MediaItem(id: "emby-series-\(id)", kind: .series, title: name, group: (d["Genres"] as? [String])?.first ?? "Series",
                             logo: image(s, id, d), url: nil, year: (d["ProductionYear"] as? Int).map(String.init),
                             plot: d["Overview"] as? String, seriesRef: id)
        }
        if cat.isEmpty { throw SourceError.empty }
        return cat
    }

    /// Episodes of one series (loaded when it is opened).
    func episodes(seriesId: String) async throws -> [Episode] {
        let s = try await signIn()
        return try await items(s, "/Shows/\(seriesId)/Episodes?UserId=\(s.userId)&Fields=Overview").compactMap { d -> Episode? in
            guard let id = d["Id"] as? String, let n = d["IndexNumber"] as? Int, let u = hls(s, id, live: false) else { return nil }
            return Episode(id: "emby-ep-\(id)", season: d["ParentIndexNumber"] as? Int ?? 1, number: n,
                           title: d["Name"] as? String ?? "Episode \(n)", url: u, plot: d["Overview"] as? String, still: image(s, id, d))
        }
    }

    private func items(_ s: Session, _ path: String) async throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var start = 0
        while true {
            guard let url = URL(string: s.base + path + "&StartIndex=\(start)&Limit=1000") else { throw SourceError.badAddress }
            var req = URLRequest(url: url, timeoutInterval: 60)
            req.setValue(authHeader(s.token), forHTTPHeaderField: "X-Emby-Authorization")
            req.setValue(s.token, forHTTPHeaderField: "X-Emby-Token")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw code == 401 ? SourceError.wrongLogin : SourceError.http(code) }
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SourceError.invalidResponse }
            let page = j["Items"] as? [[String: Any]] ?? []
            out += page
            start += page.count
            let total = j["TotalRecordCount"] as? Int ?? start
            if page.isEmpty || start >= total { return out }
        }
    }

    private func image(_ s: Session, _ id: String, _ d: [String: Any]) -> URL? {
        guard let tag = (d["ImageTags"] as? [String: Any])?["Primary"] as? String else { return nil }
        return URL(string: "\(s.base)/Items/\(id)/Images/Primary?maxHeight=450&quality=90&tag=\(tag)")
    }

    private func hls(_ s: Session, _ id: String, live: Bool) -> URL? {
        var u = "\(s.base)/Videos/\(id)/master.m3u8?api_key=\(s.token)&DeviceId=\(Self.deviceId)" +
            "&VideoCodec=h264,hevc&AudioCodec=aac,ac3,eac3&SegmentContainer=ts&TranscodingMaxAudioChannels=6&PlaySessionId=\(UUID().uuidString)"
        if !live { u += "&MediaSourceId=\(id)" }
        return URL(string: u)
    }
}
