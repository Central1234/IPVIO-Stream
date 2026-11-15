import Foundation

/// A playlist source the user added. Credentials live in the Keychain; only the id and public fields are in UserDefaults.
struct Source: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case xtream, m3u, emby
        var id: String { rawValue }
        var label: String {
            switch self {
            case .xtream: return "Xtream login"
            case .m3u: return "M3U link"
            case .emby: return "Emby / Jellyfin"
            }
        }
    }

    var id: UUID = UUID()
    var name: String
    var kind: Kind
    /// Xtream / Emby server address, or the M3U link.
    var server: String
    var user: String = ""

    /// Password from the Keychain (empty for M3U).
    var password: String {
        get { Keychain.read(account: id.uuidString) ?? "" }
        nonmutating set { Keychain.write(newValue, account: id.uuidString) }
    }
}

enum ItemKind: String, Codable {
    case live, movie, series
}

/// One channel, movie or series.
struct MediaItem: Identifiable, Hashable, Codable {
    var id: String
    var kind: ItemKind
    var title: String
    var group: String
    var logo: URL?
    /// Playable address (live and movie). Series use [episodes] or are loaded on demand.
    var url: URL?
    var year: String? = nil
    var plot: String? = nil
    var rating: String? = nil
    var added: Date? = nil
    /// Series: episodes already known (M3U, Emby) or nil = load on demand (Xtream).
    var episodes: [Episode]? = nil
    /// Xtream series id for loading episodes on demand.
    var seriesRef: String? = nil
}

struct Episode: Identifiable, Hashable, Codable {
    var id: String
    var season: Int
    var number: Int
    var title: String
    var url: URL
    var plot: String? = nil
    var still: URL? = nil

    var label: String { "S\(String(format: "%02d", season))E\(String(format: "%02d", number))" }
}

/// Everything loaded from one source.
struct Catalog {
    var live: [MediaItem] = []
    var movies: [MediaItem] = []
    var series: [MediaItem] = []

    var isEmpty: Bool { live.isEmpty && movies.isEmpty && series.isEmpty }

    static func groups(_ items: [MediaItem]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for i in items where seen.insert(i.group).inserted { out.append(i.group) }
        return out
    }
}

/// Error texts shown to the user. Never includes server addresses or passwords.
enum SourceError: LocalizedError {
    case badAddress, accessDenied(Int), http(Int), invalidResponse, empty, wrongLogin

    var errorDescription: String? {
        switch self {
        case .badAddress: return "Please check the address (it starts with http:// or https://)."
        case .accessDenied(let c): return "Access denied (\(c)). Check user name, password or subscription."
        case .http(let c): return "The server answered with error \(c)."
        case .invalidResponse: return "The server sent something the app cannot read."
        case .empty: return "No channels, movies or series were found."
        case .wrongLogin: return "Wrong user name or password."
        }
    }
}
