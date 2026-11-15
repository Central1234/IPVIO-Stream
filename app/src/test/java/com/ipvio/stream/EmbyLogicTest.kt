package com.ipvio.stream

import org.junit.Assert.*
import org.junit.Test

class EmbyLogicTest {
    @Test fun sourceRoundTripKeepsSpecialCharacters() {
        val s = EmbyLogic.source("192.168.1.20:8096/", "Ryan B", "p#ss=w&rd")!!
        assertEquals("http://192.168.1.20:8096", s.server)
        val back = EmbyLogic.parse(s.encode())!!
        assertEquals(s, back)
        assertEquals(s.encode(), PlaylistLogic.normalizeUrl(s.encode()))
    }

    @Test fun webAndEmbySuffixesAreRemoved() {
        assertEquals("https://media.example.com", EmbyLogic.source("https://media.example.com/web/index.html", "a", "")!!.server)
        assertEquals("https://media.example.com", EmbyLogic.source("https://media.example.com/emby", "a", "")!!.server)
    }

    @Test fun missingServerOrUserIsRejected() {
        assertNull(EmbyLogic.source("", "a", "b"))
        assertNull(EmbyLogic.source("http://x", "", "b"))
        assertNull(EmbyLogic.parse("http://x/get.php"))
    }

    @Test fun moviesAreVideoFilesAndLiveChannelsAreLive() {
        val movie = EmbyLogic.videoUrl("http://h/emby", "abc", "tok", "mkv")
        assertTrue(M3uParser.isVideoFile(movie))
        assertFalse(M3uParser.isLiveUrl(movie))
        val odd = EmbyLogic.videoUrl("http://h/emby", "abc", "tok", "mov,mp4")
        assertTrue(M3uParser.isVideoFile(odd))
        val live = EmbyLogic.liveUrl("http://h/emby", "ch1", "tok", "dev")
        assertTrue(M3uParser.isLiveUrl(live))
    }

    @Test fun episodeNamesMatchTheSeriesPattern() {
        assertEquals("Dark S01E02 Lies", EmbyLogic.episodeName("Dark", 1, 2, "Lies"))
        assertEquals("Dark S02E10", EmbyLogic.episodeName("Dark", 2, 10, "Episode 10"))
        assertNull(EmbyLogic.episodeName("Dark", 1, null, "x"))
        assertTrue(M3uParser.mayBeEpisode(EmbyLogic.episodeName("Dark", 1, 2, null)!!))
    }

    @Test fun entryEscapesCommasAndQuotes() {
        val e = EmbyLogic.m3uEntry("Hello, World (2020)", "Drama \"x\"", null, "http://h/v")
        val info = e.lineSequence().first()
        assertEquals("Hello‚ World (2020)", info.substringAfterLast(','))
        assertTrue(info.contains("group-title=\"Drama 'x'\""))
    }

    @Test fun movieNameAddsYearOnce() {
        assertEquals("Alien (1979)", EmbyLogic.movieName("Alien", "1979"))
        assertEquals("Alien (1979)", EmbyLogic.movieName("Alien (1979)", "1979"))
        assertEquals("Alien", EmbyLogic.movieName("Alien", null))
    }
}
