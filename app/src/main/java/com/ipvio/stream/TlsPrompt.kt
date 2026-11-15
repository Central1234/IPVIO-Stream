package com.ipvio.stream

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.delay

/**
 * Asks once per host before the app talks to a provider without encryption because its certificate does not match
 * the address (#69). The answer is stored in its own preferences file `ipvio_tls_allow` (key "hosts"), so no existing
 * key changes. "No" is remembered for this app session only: the next start asks again.
 */
object TlsPrompt {
    private const val PREFS = "ipvio_tls_allow"
    private const val KEY = "hosts"

    /** Host waiting for an answer (null = no question open). */
    var asking by mutableStateOf<String?>(null)
        private set
    private val refused = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    fun init(c: Context) {
        val app = c.applicationContext
        val hosts = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(KEY, emptySet()).orEmpty()
        TlsFallback.setAllowed(hosts)
        TlsFallback.onBlocked = { host -> if (host !in refused && asking == null) asking = host }
    }

    fun answer(c: Context, yes: Boolean) {
        val host = asking ?: return
        asking = null
        if (yes) {
            TlsFallback.allow(host)
            c.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putStringSet(KEY, TlsFallback.allowedHosts()).apply()
        } else refused.add(host)
    }

    /** Settings: forget every allowed host (they are asked again). */
    fun forgetAll(c: Context) {
        TlsFallback.allowedHosts().forEach { TlsFallback.disallow(it) }
        refused.clear()
        c.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY).apply()
    }
}

@Composable
fun TlsPromptHost() {
    val host = TlsPrompt.asking ?: return
    val ctx = LocalContext.current
    val focus = remember { FocusRequester() }
    LaunchedEffect(host) { delay(150); runCatching { focus.requestFocus() } }
    Dialog(onDismissRequest = { TlsPrompt.answer(ctx, false) }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color(0xE6000000)), contentAlignment = Alignment.Center) {
            Column(
                Modifier.widthIn(max = 720.dp).clip(RoundedCornerShape(20.dp)).background(Tok.GlassStrong).padding(28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("Zertifikat passt nicht zur Adresse", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                Text(host, color = Accent2, fontSize = 18.sp, raw = true)
                Text(
                    "Das Zertifikat dieses Servers gehört nicht zu seiner Adresse. Ohne Verschlüsselung verbinden? Benutzername und Passwort werden dann lesbar übertragen. Mach das nur, wenn du dem Anbieter und deinem Netzwerk vertraust.",
                    color = Color.White, fontSize = 16.sp, lineHeight = 22.sp
                )
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    PillButton("Nicht verbinden", modifier = Modifier.focusRequester(focus)) { TlsPrompt.answer(ctx, false) }
                    PillButton("Ohne Verschlüsselung verbinden") { TlsPrompt.answer(ctx, true) }
                }
                Text("Danach das Laden erneut starten. Die Entscheidung lässt sich unter Einstellungen > Playlists zurücksetzen.", color = Muted, fontSize = 14.sp)
            }
        }
    }
}
