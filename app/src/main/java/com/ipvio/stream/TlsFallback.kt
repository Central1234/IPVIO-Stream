package com.ipvio.stream

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.SSLPeerUnverifiedException

/**
 * Some providers deliver a certificate that does not belong to their address (wrong or expired domain, shared default
 * certificate: "Hostname x not verified, certificate is for y"). Playlist, live TV and movies then fail although the
 * server itself works. For exactly this error – and only for provider streams – the app can use the same address over
 * plain http. Since #69 this never happens silently: the first mismatch is reported through [onBlocked] (the app asks
 * the user once, see TlsPrompt.kt) and the request fails. Only a host the user allowed ([allow]) is downgraded.
 * Every other TLS error (expired, untrusted CA …) is still refused.
 * Core logic without Android, testable.
 */
object TlsFallback {
    private val broken: MutableSet<String> = ConcurrentHashMap.newKeySet()
    /** Hosts the user explicitly allowed to use without encryption (persisted by TlsPrompt). */
    private val allowed: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /** Called with the host name when a downgrade was refused because the user has not decided yet. */
    @Volatile var onBlocked: ((String) -> Unit)? = null

    fun allow(host: String) { allowed.add(host.lowercase()) }
    fun disallow(host: String) { allowed.remove(host.lowercase()); broken.remove(host.lowercase()) }
    fun isAllowed(host: String): Boolean = allowed.contains(host.lowercase())
    fun allowedHosts(): Set<String> = allowed.toSet()
    fun setAllowed(hosts: Collection<String>) { allowed.clear(); hosts.forEach { allowed.add(it.lowercase()) } }

    /**
     * A host mismatch was seen for [host]: true = downgrade now (the user allowed this host), false = refuse and ask.
     */
    fun mayDowngrade(host: String): Boolean {
        if (isAllowed(host)) { markBroken(host); return true }
        onBlocked?.invoke(host.lowercase())
        return false
    }

    /** Host name is in [url] (null = unparsable). */
    private fun hostOf(url: String): String? = url.toHttpUrlOrNull()?.host?.lowercase()

    /** Is the error (or one of its causes) "certificate does not match the host name"? */
    fun isHostMismatch(e: Throwable?): Boolean {
        var t = e
        var depth = 0
        while (t != null && depth < 8) {
            if (t is SSLPeerUnverifiedException) return true
            t = t.cause
            depth++
        }
        return false
    }

    fun markBroken(host: String) { broken.add(host.lowercase()) }
    fun isBroken(host: String): Boolean = broken.contains(host.lowercase())
    fun isBrokenUrl(url: String): Boolean = hostOf(url)?.let { broken.contains(it) && allowed.contains(it) } ?: false

    /** https address -> same address over http (default port 443 becomes 80, a special port stays). null = not applicable. */
    fun downgradeUrl(url: String): String? {
        val u = url.toHttpUrlOrNull() ?: return null
        if (!u.isHttps) return null
        val port = if (u.port == 443) 80 else u.port
        return u.newBuilder().scheme("http").port(port).build().toString()
    }

    /** For OkHttp clients that talk to the provider (playlist, Xtream/Stalker login, live buffer). */
    fun interceptor(): Interceptor = Interceptor { chain ->
        val req = chain.request()
        val url = req.url
        if (!url.isHttps) return@Interceptor chain.proceed(req)
        val host = url.host
        if (isBroken(host) && isAllowed(host)) {
            val low = downgradeUrl(url.toString())?.toHttpUrlOrNull()
            if (low != null) return@Interceptor chain.proceed(req.newBuilder().url(low).build())
        }
        try {
            chain.proceed(req)
        } catch (e: IOException) {
            val low = if (isHostMismatch(e)) downgradeUrl(url.toString())?.toHttpUrlOrNull() else null
            if (low == null || !mayDowngrade(host)) throw e
            Diag.report("Zertifikat passt nicht zur Adresse – Verbindung ohne Verschlüsselung")
            chain.proceed(req.newBuilder().url(low).build())
        }
    }
}
