package com.ipvio.stream

import org.junit.After
import org.junit.Assert.*
import org.junit.Test

/** #69: a certificate mismatch must never downgrade to http without the user's consent for that host. */
class TlsConsentTest {
    @After fun reset() {
        TlsFallback.setAllowed(emptyList())
        TlsFallback.onBlocked = null
    }

    @Test fun mismatchWithoutConsentIsRefusedAndReported() {
        var asked: String? = null
        TlsFallback.onBlocked = { asked = it }
        assertFalse(TlsFallback.mayDowngrade("Portal.Example.com"))
        assertEquals("portal.example.com", asked)
        assertFalse(TlsFallback.isBrokenUrl("https://portal.example.com/c/"))
    }

    @Test fun allowedHostIsDowngraded() {
        TlsFallback.allow("portal.example.com")
        assertTrue(TlsFallback.mayDowngrade("portal.example.com"))
        assertTrue(TlsFallback.isBrokenUrl("https://portal.example.com/c/"))
    }

    @Test fun forgettingAHostAsksAgain() {
        TlsFallback.allow("a.example.com")
        TlsFallback.mayDowngrade("a.example.com")
        TlsFallback.disallow("a.example.com")
        assertFalse(TlsFallback.isBrokenUrl("https://a.example.com/"))
        assertFalse(TlsFallback.mayDowngrade("a.example.com"))
    }

    @Test fun downgradeKeepsSpecialPorts() {
        assertEquals("http://h.example.com:8443/x", TlsFallback.downgradeUrl("https://h.example.com:8443/x"))
        assertEquals("http://h.example.com/x", TlsFallback.downgradeUrl("https://h.example.com/x"))
    }
}
