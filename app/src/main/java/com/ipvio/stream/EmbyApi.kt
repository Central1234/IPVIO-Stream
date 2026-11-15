package com.ipvio.stream

import android.util.JsonReader
import android.util.JsonToken
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.io.Writer

/**
 * Reads an Emby (or Jellyfin) server and writes its movies, series and Live TV channels as an M3U list (see [EmbyLogic]).
 * Item lists are read page by page with a streaming reader, so large libraries never sit in memory as JSON.
 * Errors reach the user as [PlaylistError] with a German UI text (translated like every other text); messages of
 * third-party libraries are never passed on (they can contain the server address).
 */
class EmbyApi(private val client: OkHttpClient, private val deviceId: String, private val version: String) {
    var onPhase: (String) -> Unit = {}
    var check: () -> Unit = {}

    private class Session(val base: String, val userId: String, val token: String)
    private class Row(val f: Map<String, String>, val imageTag: String?, val genre: String?)

    /** Writes the whole list; returns the number of entries. */
    fun write(src: EmbyLogic.Source, w: Writer): Int {
        onPhase("Zugang wird geprüft …")
        val s = signIn(src)
        w.write("#EXTM3U\n")
        var n = 0
        onPhase("Sender werden geladen …")
        // Servers without a tuner answer with an error or an empty list: Live TV is optional
        n += try { writeLive(s, w) } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { 0 }
        check()
        onPhase("Filme werden geladen …")
        n += writeMovies(s, w)
        check()
        onPhase("Serien werden geladen …")
        n += writeEpisodes(s, w)
        return n
    }

    // ---------------------------------------------------------------- Sign in

    private fun signIn(src: EmbyLogic.Source): Session {
        // Emby answers under /emby, Jellyfin (and Emby behind some proxies) without it
        var last: PlaylistError? = null
        for (prefix in listOf("/emby", "")) {
            val base = src.server + prefix
            val body = JSONObject().put("Username", src.user).put("Pw", src.pass).toString()
            val req = Request.Builder().url("$base/Users/AuthenticateByName")
                .header("X-Emby-Authorization", EmbyLogic.authHeader(deviceId, version))
                .header("Accept", "application/json")
                .post(body.toRequestBody("application/json".toMediaType()))
                .build()
            try {
                client.newCall(req).execute().use { r ->
                    when {
                        r.code == 401 || r.code == 403 -> throw PlaylistError("Emby: Benutzername oder Passwort falsch.")
                        r.code == 404 -> { last = PlaylistError("Emby-Server nicht gefunden (404). Adresse prüfen."); return@use }
                        !r.isSuccessful -> throw PlaylistError(PlaylistLogic.httpError(r.code))
                    }
                    val j = JSONObject(r.body?.string().orEmpty())
                    val token = j.optString("AccessToken")
                    val uid = j.optJSONObject("User")?.optString("Id").orEmpty()
                    if (token.isEmpty() || uid.isEmpty()) throw PlaylistError("Emby: unerwartete Antwort bei der Anmeldung.")
                    return Session(base, uid, token)
                }
            } catch (e: PlaylistError) {
                throw e
            } catch (e: IOException) {
                throw e
            } catch (e: Exception) {
                last = PlaylistError("Emby: unerwartete Antwort bei der Anmeldung.")
            }
        }
        throw last ?: PlaylistError("Emby-Server nicht gefunden (404). Adresse prüfen.")
    }

    private fun get(s: Session, pathAndQuery: String): Request = Request.Builder().url(s.base + pathAndQuery)
        .header("X-Emby-Authorization", EmbyLogic.authHeader(deviceId, version, s.token))
        .header("X-Emby-Token", s.token)
        .header("Accept", "application/json")
        .build()

    // ---------------------------------------------------------------- Lists

    private fun writeLive(s: Session, w: Writer): Int {
        var n = 0
        pages(s, "/LiveTv/Channels?UserId=${s.userId}&EnableImages=true&SortBy=SortName") { r ->
            val id = r.f["Id"] ?: return@pages
            val name = r.f["Name"] ?: return@pages
            w.write(EmbyLogic.m3uEntry(EmbyLogic.liveName(r.f["ChannelNumber"] ?: r.f["Number"], name), "Emby Live TV",
                EmbyLogic.imageUrl(s.base, id, r.imageTag), EmbyLogic.liveUrl(s.base, id, s.token, deviceId)))
            n++
        }
        return n
    }

    private fun writeMovies(s: Session, w: Writer): Int {
        var n = 0
        pages(s, "/Users/${s.userId}/Items?Recursive=true&IncludeItemTypes=Movie&Fields=Genres,ProductionYear,DateCreated&SortBy=DateCreated&SortOrder=Ascending") { r ->
            val id = r.f["Id"] ?: return@pages
            val name = r.f["Name"] ?: return@pages
            w.write(EmbyLogic.m3uEntry(EmbyLogic.movieName(name, r.f["ProductionYear"]), r.genre ?: "Emby Filme",
                EmbyLogic.imageUrl(s.base, id, r.imageTag), EmbyLogic.videoUrl(s.base, id, s.token, r.f["Container"])))
            n++
        }
        return n
    }

    private fun writeEpisodes(s: Session, w: Writer): Int {
        // Genre and poster per series first (episodes carry neither reliably)
        val genre = HashMap<String, String>()
        val poster = HashMap<String, String>()
        pages(s, "/Users/${s.userId}/Items?Recursive=true&IncludeItemTypes=Series&Fields=Genres") { r ->
            val id = r.f["Id"] ?: return@pages
            r.genre?.let { genre[id] = it }
            EmbyLogic.imageUrl(s.base, id, r.imageTag)?.let { poster[id] = it }
        }
        var n = 0
        pages(s, "/Users/${s.userId}/Items?Recursive=true&IncludeItemTypes=Episode&Fields=DateCreated&SortBy=SeriesSortName,ParentIndexNumber,IndexNumber") { r ->
            val id = r.f["Id"] ?: return@pages
            val sid = r.f["SeriesId"]
            val name = EmbyLogic.episodeName(r.f["SeriesName"].orEmpty(), r.f["ParentIndexNumber"]?.toIntOrNull(), r.f["IndexNumber"]?.toIntOrNull(), r.f["Name"]) ?: return@pages
            val logo = sid?.let { poster[it] } ?: EmbyLogic.imageUrl(s.base, sid, r.f["SeriesPrimaryImageTag"])
            w.write(EmbyLogic.m3uEntry(name, sid?.let { genre[it] } ?: "Emby Serien", logo, EmbyLogic.videoUrl(s.base, id, s.token, r.f["Container"])))
            n++
        }
        return n
    }

    /** Pages of 500 items; [each] gets the flat fields, the primary image tag and the first genre. */
    private fun pages(s: Session, pathAndQuery: String, each: (Row) -> Unit) {
        var start = 0
        val sep = if (pathAndQuery.contains('?')) "&" else "?"
        while (true) {
            check()
            var got = 0
            var total = -1
            client.newCall(get(s, "$pathAndQuery${sep}StartIndex=$start&Limit=500")).execute().use { r ->
                if (r.code == 401 || r.code == 403) throw PlaylistError("Emby: Zugriff verweigert. Anmeldung prüfen.")
                if (!r.isSuccessful) throw PlaylistError(PlaylistLogic.httpError(r.code))
                val body = r.body ?: throw PlaylistError("Der Server hat keine Daten geliefert.")
                JsonReader(body.charStream()).use { jr ->
                    jr.isLenient = true
                    if (jr.peek() != JsonToken.BEGIN_OBJECT) return@use
                    jr.beginObject()
                    while (jr.hasNext()) {
                        when (jr.nextName()) {
                            "Items" -> {
                                jr.beginArray()
                                while (jr.hasNext()) {
                                    if (jr.peek() == JsonToken.BEGIN_OBJECT) { each(row(jr)); got++ } else jr.skipValue()
                                    if (got % 200 == 0) check()
                                }
                                jr.endArray()
                            }
                            "TotalRecordCount" -> total = if (jr.peek() == JsonToken.NUMBER) jr.nextInt() else { jr.skipValue(); -1 }
                            else -> jr.skipValue()
                        }
                    }
                    jr.endObject()
                }
            }
            start += got
            if (got == 0 || (total in 0..start)) return
        }
    }

    /** One item: plain fields, ImageTags.Primary and the first entry of Genres. */
    private fun row(jr: JsonReader): Row {
        val f = HashMap<String, String>(24)
        var tag: String? = null
        var genre: String? = null
        jr.beginObject()
        while (jr.hasNext()) {
            val n = jr.nextName()
            when {
                n == "ImageTags" && jr.peek() == JsonToken.BEGIN_OBJECT -> {
                    jr.beginObject()
                    while (jr.hasNext()) {
                        val k = jr.nextName()
                        if (k == "Primary" && jr.peek() == JsonToken.STRING) tag = jr.nextString() else jr.skipValue()
                    }
                    jr.endObject()
                }
                n == "Genres" && jr.peek() == JsonToken.BEGIN_ARRAY -> {
                    jr.beginArray()
                    while (jr.hasNext()) {
                        if (genre == null && jr.peek() == JsonToken.STRING) genre = jr.nextString().trim().ifEmpty { null } else jr.skipValue()
                    }
                    jr.endArray()
                }
                else -> when (jr.peek()) {
                    JsonToken.STRING, JsonToken.NUMBER -> f[n] = jr.nextString()
                    JsonToken.BOOLEAN -> f[n] = jr.nextBoolean().toString()
                    else -> jr.skipValue()
                }
            }
        }
        jr.endObject()
        return Row(f, tag, genre)
    }
}
