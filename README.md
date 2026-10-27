# YandexTitle for Lyrion Music Server

YandexTitle is an LMS plugin for Yandex Station streams routed from Home Assistant to Squeezebox/Lyrion players.

It provides two-way integration:

- Home Assistant → LMS: artist, title and artwork metadata.
- LMS/RTI → Home Assistant: next/previous commands for the Yandex Station currently routed to an LMS Zone.

For older RTI Squeezebox drivers, `current_title` is kept compact:

```
Alice - Artist - Track
```

If metadata has not arrived yet, the plugin uses a short fallback such as `Z1`, `Z2`, `Z3`, `Z4`, or `DHC`.

## Current version

**0.3.3**

Tested with Lyrion Music Server 9.x.

## Installation

In LMS open **Settings → Plugins → Additional Repositories** and add:

```
https://raw.githubusercontent.com/dskudrin/YandexTitle-LMS/main/repo.xml
```

Refresh the plugin list, install **YandexTitle**, and restart LMS when requested.

## Metadata: Home Assistant → LMS

The plugin exposes an LMS CLI command:

```
yandextitle metadata <artist> <title> <cover>
```

The example in `home-assistant/automation.yaml` forwards `media_artist`, `media_title`, and `entity_picture` from Yandex Station to the currently selected LMS player.

## Transport: LMS/RTI → Home Assistant

When an LMS player is currently playing a URL containing `/api/yandex_station/`, YandexTitle intercepts both transport forms used by our controllers:

```
playlist index +1
playlist index -1
playlist jump +1
playlist jump -1
```

Astrion uses `playlist index`. The legacy RTI Squeezebox driver emits `button fwd/rew`; YandexTitle 0.3.3 intercepts those button commands directly before LMS converts them to playlist jumps.

and sends a JSON webhook to Home Assistant:

```json
{"player_id":"b8:27:eb:6d:75:2c","zone":"Z1","command":"next"}
```

For all other LMS playback, the original `playlist index` or `playlist jump` handler is called unchanged.

Configure the Home Assistant webhook URL once through the LMS CLI. URL-encode the URL when sending it over the LMS CLI, for example:

```
yandextitle webhook http%3A%2F%2F192.168.3.14%3A8123%2Fapi%2Fwebhook%2Flms_yandex_control_CHANGE_ME
```

The URL is stored in local LMS preferences; no Home Assistant long-lived access token is required.

The Home Assistant webhook automation dynamically finds the Yandex Station whose `source` currently points to the relevant Zone and calls `media_next_track` or `media_previous_track`.

## Files

- `Plugin.pm` — LMS plugin code
- `install.xml` — plugin manifest
- `repo.xml` — LMS Additional Repository index
- `dist/YandexTitle-0.3.3.zip` — installable package
- `home-assistant/automation.yaml` — Home Assistant metadata and reverse-control automations
- `CHANGELOG.md` — version history
