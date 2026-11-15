# IPVIO Stream for iOS (starter app)

A native SwiftUI app for iPhone and iPad that plays the same sources as the Android TV app:

- **Xtream Codes login** (player_api.php, with the same 403 User-Agent fallback as Android, issue #90)
- **M3U link**
- **Emby / Jellyfin server** (movies, series with episodes, Live TV)

**iPhone Duo:** layouts follow size classes. On the outer display (compact width) it looks like any iPhone app; on
the unfolded inner display (regular width) Live TV gets a category column next to the channels, Movies/Series get a
category column, a featured banner and larger posters, detail pages go side by side, the tab bar can become a sidebar,
and the player shows the channel list beside the picture. Built with the Xcode 27 runner image (iOS 27.x SDK), so the
app uses the full inner display. The fold-specific APIs Apple showed (hinge, reserved regions) are not used yet:
their signatures were not published when this was written.

**Player:** IPVIO's own controls instead of the system player: tap to show/hide, double tap left/right for 10 s,
pinch for fill/fit, a large timeline with drag to seek, audio and subtitle track selection, speed (0.5–2×), picture
format (fit, fill, stretch — useful on the Duo's 1.42 display where 16:9 is letterboxed), AirPlay, Picture in Picture,
lock-screen controls, "Up next" countdown into the next episode, and channel up/down plus a channel list for live TV.

Features: Live TV with categories, favourites and channel up/down in the player; Movies and Series with categories,
posters, "Continue watching" and resume positions; series seasons/episodes (loaded on demand for Xtream and Emby)
with "Next episode"; search across everything; several playlists; passwords in the Keychain; AirPlay and Picture in
Picture through the system player.

This is a **starting point, not feature parity** with the Android app. Not ported yet: TV guide (EPG), catch-up,
recording, profiles and parental PIN, sports section, TMDB/OMDb metadata and ratings, intro skipping, subtitle search,
phone-to-TV transfer, translations (the iOS UI is English only).

## Build

Requirements: a Mac with Xcode 15 or newer, iOS 18+ device or simulator.

```bash
brew install xcodegen
cd ios
xcodegen            # creates IPVIOStream.xcodeproj from project.yml
open IPVIOStream.xcodeproj
```

In Xcode: select the `IPVIOStream` target → *Signing & Capabilities* → choose your team. Then run on a simulator or
device. `⌘U` runs the unit tests (parser and Emby address handling).

To install on an iPhone without the App Store you need at least a free Apple ID in Xcode (apps expire after 7 days)
or a paid Apple Developer account (TestFlight / 1 year). App Store review of IPTV players is strict: the app must not
ship or suggest any content source.

## Playback limits on iOS

AVPlayer plays **HLS (.m3u8)**, **MP4/MOV** and their usual codecs. It does **not** play MKV, AVI or raw MPEG-TS files.

- Xtream live channels are requested as `.m3u8`, which Xtream servers provide, so they play.
- Xtream movies/episodes in **MKV** (very common) will show "iOS cannot play .mkv files directly".
- **Emby/Jellyfin** sources are played as HLS from the server (`master.m3u8`), so the server remuxes or transcodes
  anything iOS cannot play. MKV libraries work there.

To play MKV/TS from Xtream and M3U sources directly, the next step is adding a VLC-based player
([MobileVLCKit](https://code.videolan.org/videolan/VLCKit) via CocoaPods/SPM, LGPL) and using it as a fallback when
AVPlayer reports a failure. That is a new dependency and was left out of the starter on purpose.

## Structure

```
IPVIOStream/
  App/        app entry, theme (IPVIO green on navy)
  Models/     Source, MediaItem, Episode, Catalog, errors
  Services/   M3UParser, XtreamClient, EmbyClient, Library (state + persistence), Keychain
  Views/      Root tabs, Add playlist, Live TV, Movies/Series, details, Search, Settings, Player
IPVIOStreamTests/
```

Status: compiles on GitHub Actions (`.github/workflows/ios-unsigned-ipa.yml`, Xcode 27 image, unsigned IPA as artifact).
Not yet run on a device by the author.
