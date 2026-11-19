# Changelog

## 0.3.12

- Replaces `OpmlFavorites->findUrl()` with a direct scan of `OpmlFavorites->all()` when handling `playlist play`.
- Compares the actual played `_item` URL against each Favorite URL verbatim.
- Uses the matching Favorite's title for `LMS - <Favorite name>`.
- This bypasses the internal Favorites URL index, which did not resolve the observed Yandex Music Favorite URL even though the URL in `favorites.opml` was identical.

## 0.3.11

- Removes the passive `favorites playlist` subscription because native Favorite playback does not emit that notification.
- Detects Favorites inside the existing `playlist play` handler by matching the played URL with `OpmlFavorites->findUrl()`.
- Resolves the matched Favorite entry and queues `LMS - <Favorite name>` through the existing delayed `current_title` path.
- Adds a warning log line when a `playlist play` URL is matched to a Favorite, making the detection path directly observable.
- Keeps `yandextitle source` as a fallback.

## 0.3.10

- Observes native `favorites playlist play item_id:...` requests through `Slim::Control::Request::subscribe` instead of replacing the Favorites dispatch handler.
- Resolves the selected Favorite title from `Slim::Plugin::Favorites::OpmlFavorites->entry(item_id)`.
- Queues `LMS - <Favorite name>` into `current_title` using the existing delayed source-label path, preserving the cold-start retry behavior.
- Keeps `yandextitle source` as a Home Assistant fallback and normalizes that fallback to the same `LMS - <name>` format.
- Unsubscribes the passive listener on plugin shutdown.

## 0.3.9

- Declares `Plugin.pm` source as UTF-8 with `use utf8;`.
- Fixes hard-coded Cyrillic Station/Playlist labels such as `Алиса` being stored as UTF-8 bytes interpreted as Latin-1, which produced mojibake like `ÐÐ»Ð¸ÑÐ°`.
- No playback/source-selection logic changes in this release.


## 0.3.8

- Station/Playlist Name for Yandex Station is now always `Алиса`; artist and track remain in their dedicated metadata fields.
- LMS Favorites now use the Favorite name exactly as received from Home Assistant, without an `LMS - ` or other prefix.
- Alice fallback before metadata arrives is also `Алиса`, replacing the previous zone label.
- Keeps the delayed Favorite label application from 0.3.7 for reliable Off → LMS startup.



## 0.3.7

- Applies queued LMS Favorite source labels after playback has switched to the new non-Alice URL.
- Uses a short delayed retry loop instead of injecting the title into the initial `playlist play` request.
- Prevents LMS from immediately clearing `LMS - <favorite>` during stream initialization.


## 0.3.6

- Changed `yandextitle source <name>` to queue the LMS Favorite source label instead of applying it immediately to the current URL.
- The next non-Alice `playlist play` consumes the queued label and injects `LMS - <name>` as the playlist title.
- This removes the race where Home Assistant could set the label on the previous Alice URL before LMS switched to the Favorite.


## 0.3.5

- Added `yandextitle source <name>` CLI command for Home Assistant.
- Sets LMS `current_title` to `LMS - <name>` for the selected player so RTI exposes it through Station/Playlist Name.
- Keeps Alice metadata behavior unchanged; the next `yandextitle metadata` update can replace the source label with `Alice - Artist - Track`.


## 0.3.4

- Fixed UTF-8 decoding for the compact `current_title` used as Station/Playlist Name by RTI.
- Cyrillic artist/title text in strings such as `Alice - Artist - Track` is now decoded before calling `setCurrentTitle`.
- Kept RemoteMetadata artist/title values unchanged to avoid affecting already-correct Now Playing metadata.


## 0.3.3

- Intercepts legacy RTI `button fwd` and `button rew` directly while a Yandex Station stream is active.
- Maps RTI `fwd` to Home Assistant `next` and `rew` to `previous` before LMS runs its normal button logic.
- Keeps Astrion support through `playlist index +1/-1`.
- Preserves native button behavior for non-Yandex playback.

## 0.3.2

- Rebuilt the installable ZIP from the clean repository sources.
- Fixed package corruption that could leave an invalid `Plugin.pm` after installation.
- No functional transport changes versus 0.3.1: RTI uses `playlist jump ±1`, Astrion uses `playlist index ±1`.

## 0.3.1

- Added interception of `playlist jump +1/-1` used by the legacy RTI Squeezebox driver.
- RTI `button fwd` / `button rew` now forward Alice NEXT/PREV through the same Home Assistant webhook bridge.
- Kept `playlist index +1/-1` support for Astrion/other LMS clients.
- Normal LMS playback still delegates both `playlist jump` and `playlist index` to their original handlers.

## 0.3.0

- Added reverse LMS → Home Assistant transport bridge for Yandex Station streams.
- Intercepts `playlist index +1` and `playlist index -1` only while the current LMS URL is a Home Assistant Yandex Station stream.
- Sends asynchronous JSON webhooks to Home Assistant for `next` / `previous`.
- Added `yandextitle webhook <url>` CLI command; the webhook URL is stored locally in LMS preferences and is not kept in the public repository.
- Keeps normal LMS next/previous behavior unchanged for non-Yandex playback.
- Verified with legacy RTI Squeezebox controls and normal LMS playlists.

## 0.2.0

- Added Home Assistant → LMS metadata command: `yandextitle metadata`.
- Added separate artist, title, and artwork metadata.
- Added LMS RemoteMetadata provider for Yandex Station stream URLs.
- Kept compact `current_title` for older RTI Squeezebox drivers.
- Added short Z1/Z2/Z3/Z4/DHC fallback when metadata has not arrived yet.
- Added cleanup for recent URL-bound and pending metadata.

## 0.1.1

- Replaced oversized Yandex Station stream URLs in LMS `current_title` / `title` with short player labels.
