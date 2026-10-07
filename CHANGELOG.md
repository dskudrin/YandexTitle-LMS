# Changelog

## 0.2.0

- Added Home Assistant → LMS metadata command: `yandextitle metadata`.
- Added separate artist, title, and artwork metadata.
- Added LMS RemoteMetadata provider for Yandex Station stream URLs.
- Kept compact `current_title` for older RTI Squeezebox drivers.
- Added short Z1/Z2/Z3/Z4/DHC fallback when metadata has not arrived yet.
- Added cleanup for recent URL-bound and pending metadata.

## 0.1.1

- Replaced oversized Yandex Station stream URLs in LMS `current_title` / `title` with short player labels.
