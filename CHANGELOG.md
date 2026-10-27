# Changelog

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
