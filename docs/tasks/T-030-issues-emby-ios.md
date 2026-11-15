# T-030: open issues, Emby source, iOS starter app

Status: **implemented, not built, not device tested** (no Android SDK or Mac in the assistant's environment).

## Goal
1. Fix the open bug reports in the issues tab (feature requests out of scope).
2. Add Emby (and Jellyfin) as a playlist source.
3. Provide a starting point for an iOS app.

## Issues
| Issue | Result |
| --- | --- |
| #10 #15 #18 #20 #22 #25 (seek) #26 #28 #65 #67 | merged from PR #40 / #70 (browanoncoder) |
| #78 #79 #80 #81 #82 #83 | already fixed in 1.4.2 (`WhatsNew.kt` notes, code checked) |
| #90 | `PlaylistStore.download`: one retry with `IPVIOStream/<version>` on 403, remembered per host (`pl_ua_native_hosts` in prefs `ipvio`) |
| #69 | `TlsFallback`: downgrade only for hosts the user allowed; `TlsPrompt.kt` dialog + `ipvio_tls_allow`; reset in Settings > Playlists |
| #77 | `PlaylistStore.switchDetached` (app scope) + `loading = true` before the list is cleared |
| #27 | `BrowseReq.pool` / `catName`; Genre pill replaces the category |
| #84 | `XtreamApi.epList` reads season objects; `LazySeries` uses `PlaylistStore.xtreamApi(ctx, base)` |
| #73 | `guard()` empties caches (`Mem.trim`) before `ParseStop`; root cause not confirmed (needs `adb logcat -s IPVIO-PL`) |
| #23, #25 (other touch points) | not changed: need maintainer decision / concrete screens |

## Emby
New files `EmbyLogic.kt` (pure, tested in `EmbyLogicTest.kt`) and `EmbyApi.kt`. Source string `emby:SERVER#user=…#pass=…`
(same storage path as Xtream credentials). `PlaylistStore.downloadEmby` writes an M3U; `M3uParser.isLiveUrl` also accepts
the marker `ipvio_live=1`. New prefs key `emby_device_id`. No EPG for Emby yet.

## Protected areas touched (need maintainer approval before merge)
- Player/IPTV core: `PlaylistStore.kt`, `Models.kt` (`isLiveUrl`), `XtreamApi.kt`, `TlsFallback.kt`, `LiveTimeshift.kt`.
- Security behaviour: TLS downgrade now requires consent (#69).
- New UI strings (German keys, 10 languages in `DictJ.kt`); new prefs keys only, no existing key renamed.

## Checks
- Ran: `EmbyLogic` compiled with Kotlin 2.0.21 and checked with a small main (all assertions passed).
- Ran: Kotlin compiler over all main sources before/after; the error diff (without Android/OkHttp jars) showed one real
  error (duplicate `hostOf`), fixed. All remaining differences come from unresolved Android/Compose/OkHttp types.
- Not run: Gradle build, unit tests (`TlsConsentTest`, `EmbyLogicTest`, existing suite), device tests, iOS build.

## Test steps for the maintainer
1. Build debug, run unit tests.
2. #90: provider that returns 403 for VLC → import succeeds; `adb logcat -s IPVIO-PL` shows the `ua` lines.
3. #69: portal with a mismatched certificate → dialog appears; "Don't connect" fails cleanly; "Connect without encryption" + reload works; Settings > Playlists shows the host and "forget" resets it.
4. #77: two playlists, switch from Movies → loading skeleton, then the new list; no "No channels yet".
5. #27: Movies → Categories → OK on a category → Genre pill shows the category; pick a genre → title and list switch.
6. #84: Xtream series that failed before → episodes load.
7. Emby: add server (LAN address), user, password → movies, series (episodes), Live TV appear; a movie, an episode and a channel play; wrong password → clear message. Repeat with Jellyfin if available.
8. iOS: see `ios/README.md`.
