package com.ipvio.stream

import java.net.URLDecoder
import java.net.URLEncoder

/**
 * Emby server as a playlist source. The app stores a source like any other playlist address:
 * "emby:SERVER#user=NAME#pass=PASSWORD" (values URL-encoded). When the playlist is loaded, [EmbyApi] signs in,
 * reads movies, series (with episodes) and Live TV channels and writes them as an M3U list, so the rest of the app
 * (parser, cache, search, player) works unchanged.
 *
 * Addresses written into the list:
 * - movies and episodes: "SERVER/Videos/ID/stream.EXT?static=true&api_key=TOKEN" (direct play of the original file;
 *   the extension makes [M3uParser] classify them as video files)
 * - live channels: "SERVER/Videos/ID/master.m3u8?…&ipvio_live=1" (HLS from the server; the marker makes them live)
 * - episodes are named "Series S01E02 Title" so the parser groups them into their series.
 * Jellyfin speaks the same API; the client tries "SERVER/emby/…" first and then "SERVER/…".
 * Core logic without Android, testable.
 */
object EmbyLogic {
    data class Source(val server: String, val user: String, val pass: String) {
        fun encode(): String = "emby:" + server + "#user=" + enc(user) + "#pass=" + enc(pass)
        /** Stable key for caches and for the source of downloaded items. */
        val key: String get() = (server.lowercase() + "|" + user.lowercase()).hashCode().toUInt().toString(16)
    }

    /** Marker in a live address (ignored by the server). */
    const val LIVE_MARK = "ipvio_live=1"

    fun isSource(url: String): Boolean = url.trim().startsWith("emby:", true)

    /** Source from the add form; null when server or user is missing. Password may be empty (Emby allows that). */
    fun source(serverRaw: String, userRaw: String, passRaw: String): Source? {
        var s = serverRaw.trim().trimEnd('/')
        val u = userRaw.trim()
        if (s.isEmpty() || u.isEmpty()) return null
        if (!s.startsWith("http://", true) && !s.startsWith("https://", true)) s = "http://$s"
        // The client adds "/emby" itself; an entered "/emby" or "/web/index.html" is removed
        s = s.replace(Regex("""/web(/.*)?$""", RegexOption.IGNORE_CASE), "").replace(Regex("""/emby$""", RegexOption.IGNORE_CASE), "")
        if (!Regex("""^https?://[^\s/?#]+(:\d+)?(/[^\s?#]*)?$""", RegexOption.IGNORE_CASE).matches(s)) return null
        return Source(s, u, passRaw)
    }

    fun parse(url: String): Source? {
        val u = url.trim()
        if (!isSource(u)) return null
        val parts = u.substring("emby:".length).split('#')
        var user = ""; var pass = ""
        for (p in parts.drop(1)) {
            val kv = p.split('=', limit = 2)
            if (kv.size != 2) continue
            when (kv[0]) { "user" -> user = dec(kv[1]); "pass" -> pass = dec(kv[1]) }
        }
        return source(parts[0], user, pass)
    }

    /** Value for the X-Emby-Authorization header (Emby and Jellyfin). */
    fun authHeader(deviceId: String, version: String, token: String? = null): String =
        "MediaBrowser Client=\"IPVIO Stream\", Device=\"Android TV\", DeviceId=\"" + clean(deviceId) + "\", Version=\"" + clean(version) + "\"" +
            (if (token != null) ", Token=\"" + clean(token) + "\"" else "")

    /** Extensions [M3uParser.isVideoFile] recognises. */
    private val VIDEO_EXT = setOf("mp4", "mkv", "avi")

    /** Direct-play address of a movie or episode. [container] from the server ("mkv", "mp4,m4a" …). */
    fun videoUrl(base: String, id: String, token: String, container: String?): String {
        val c = container?.substringBefore(',')?.trim()?.lowercase()
        // The parser recognises three-letter video extensions; static=true streams the original file whatever the extension
        val ext = if (c != null && c in VIDEO_EXT) c else "mkv"
        return "$base/Videos/${enc(id)}/stream.$ext?static=true&api_key=${enc(token)}"
    }

    fun liveUrl(base: String, id: String, token: String, deviceId: String): String =
        "$base/Videos/${enc(id)}/master.m3u8?api_key=${enc(token)}&DeviceId=${enc(deviceId)}" +
            "&VideoCodec=h264,hevc&AudioCodec=aac,ac3,eac3,mp3&SegmentContainer=ts&TranscodingMaxAudioChannels=6&$LIVE_MARK"

    fun imageUrl(base: String, id: String?, tag: String?): String? {
        if (id.isNullOrBlank() || tag.isNullOrBlank()) return null
        return "$base/Items/${enc(id)}/Images/Primary?maxHeight=450&quality=90&tag=${enc(tag)}"
    }

    /** One entry of the generated list. */
    fun m3uEntry(name: String, group: String, logo: String?, url: String): String {
        val sb = StringBuilder(160)
        sb.append("#EXTINF:-1")
        if (!logo.isNullOrBlank()) sb.append(" tvg-logo=\"").append(attr(logo)).append('"')
        sb.append(" group-title=\"").append(attr(group)).append("\",").append(title(name)).append('\n')
        sb.append(url.replace("\n", "")).append('\n')
        return sb.toString()
    }

    fun movieName(title: String, year: String?): String =
        if (!year.isNullOrBlank() && year.length == 4 && !title.contains("($year)")) "$title ($year)" else title

    /** "Series S01E02 Title" (title left out when it is just "Episode 2"). null = no episode number. */
    fun episodeName(series: String, season: Int?, num: Int?, title: String?): String? {
        if (num == null || num < 0) return null
        val s = (season ?: 1).coerceIn(0, 99)
        val base = series.ifBlank { "Serie" } + " S" + s.toString().padStart(2, '0') + "E" + num.toString().padStart(2, '0')
        val t = title?.trim().orEmpty()
        return if (t.isEmpty() || Regex("""^(Episode|Folge|Épisode|Episodio|Bölüm|Aflevering)\s*\d+$""", RegexOption.IGNORE_CASE).matches(t)) base else "$base $t"
    }

    fun liveName(number: String?, name: String): String = if (number.isNullOrBlank()) name else "$number $name"

    /** The name ends after the last comma of #EXTINF: commas in titles become a look-alike, line breaks spaces. */
    private fun title(s: String) = s.replace('\n', ' ').replace('\r', ' ').replace(',', '‚').trim()
    private fun attr(s: String) = s.replace("\"", "'").replace('\n', ' ').replace('\r', ' ').trim()
    private fun clean(s: String) = s.replace("\"", "").replace('\n', ' ').replace('\r', ' ')
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
    private fun dec(s: String) = runCatching { URLDecoder.decode(s, "UTF-8") }.getOrDefault(s)
}
