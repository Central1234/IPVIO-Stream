import Foundation

/// Parses an M3U / M3U Plus playlist into live channels, movies and series (same rules as the Android app's parser).
enum M3UParser {
    private static let episodeRegex = try! NSRegularExpression(pattern: #"^(.*?)[\s._-]*[Ss](\d{1,2})[\s._-]*[Ee](\d{1,4})\s*(.*)$"#)
    private static let videoExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "m4v"]

    static func parse(_ text: String) -> Catalog {
        var cat = Catalog()
        var seriesIndex: [String: Int] = [:]
        var info: String?
        var name = ""
        var group = "Other"
        var logo: URL?

        text.enumerateLines { raw, _ in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                info = line
                name = line.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""
                group = attribute(line, "group-title").flatMap { $0.isEmpty ? nil : $0 } ?? "Other"
                logo = attribute(line, "tvg-logo").flatMap { URL(string: $0) }
                return
            }
            guard !line.isEmpty, !line.hasPrefix("#"), info != nil, let url = URL(string: line) else { return }
            info = nil
            // The address is the stable id (hashValue changes on every launch; resume positions need a fixed key)
            let id = line

            if let ep = episode(name) {
                let key = ep.series.lowercased() + "|" + group
                let e = Episode(id: id, season: ep.season, number: ep.number, title: ep.title.isEmpty ? "Episode \(ep.number)" : ep.title, url: url)
                if let i = seriesIndex[key] {
                    cat.series[i].episodes?.append(e)
                } else {
                    seriesIndex[key] = cat.series.count
                    cat.series.append(MediaItem(id: "series|" + key, kind: .series, title: ep.series, group: group, logo: logo, url: nil, episodes: [e]))
                }
                return
            }
            let isLive = line.contains("/live/") || line.contains("ipvio_live=1")
            let isMovie = !isLive && (line.contains("/movie/") || videoExtensions.contains(url.pathExtension.lowercased()))
            let (title, year) = splitYear(name)
            cat.append(MediaItem(id: id, kind: isMovie ? .movie : .live, title: isMovie ? title : name, group: group, logo: logo, url: url, year: isMovie ? year : nil))
        }
        for i in cat.series.indices {
            cat.series[i].episodes?.sort { ($0.season, $0.number) < ($1.season, $1.number) }
        }
        return cat
    }

    static func attribute(_ line: String, _ key: String) -> String? {
        guard let r = line.range(of: key + "=\"") else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    static func episode(_ name: String) -> (series: String, season: Int, number: Int, title: String)? {
        let ns = name as NSString
        guard let m = episodeRegex.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let series = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        guard !series.isEmpty, let s = Int(ns.substring(with: m.range(at: 2))), let e = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        let title = m.range(at: 4).location != NSNotFound ? ns.substring(with: m.range(at: 4)).trimmingCharacters(in: CharacterSet(charactersIn: " -–")) : ""
        return (series, s, e, title)
    }

    /// "Alien (1979)" -> ("Alien", "1979")
    static func splitYear(_ name: String) -> (String, String?) {
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "(") else { return (name, nil) }
        let inner = name[name.index(after: open)..<name.index(before: name.endIndex)]
        guard inner.count == 4, Int(inner) != nil else { return (name, nil) }
        return (name[..<open].trimmingCharacters(in: .whitespaces), String(inner))
    }
}

private extension Catalog {
    mutating func append(_ i: MediaItem) {
        switch i.kind {
        case .live: live.append(i)
        case .movie: movies.append(i)
        case .series: series.append(i)
        }
    }
}
