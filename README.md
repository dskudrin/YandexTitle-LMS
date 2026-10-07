# YandexTitle for Lyrion Music Server

YandexTitle is an LMS plugin for Yandex Station streams routed from Home Assistant to Squeezebox/Lyrion players.

It replaces long technical Home Assistant stream URLs with compact metadata and accepts real track information from Home Assistant:

- artist
- title
- artwork

For older RTI Squeezebox drivers, `current_title` is kept compact:

```
Alice - Artist - Track
```

If metadata has not arrived yet, the plugin uses a short fallback such as `Z1`, `Z2`, `Z3`, `Z4`, or `DHC`.

## Current version

**0.2.0**

Tested with Lyrion Music Server 9.x.

## Installation

In LMS open **Settings → Plugins → Additional Repositories** and add:

```
https://raw.githubusercontent.com/dskudrin/YandexTitle-LMS/main/repo.xml
```

Refresh the plugin list, install **YandexTitle**, and restart LMS when requested.

## Home Assistant

The plugin exposes an LMS CLI command:

```
yandextitle metadata <artist> <title> <cover>
```

The Home Assistant automation in `home-assistant/automation.yaml` forwards `media_artist`, `media_title`, and `entity_picture` from Yandex Station to the currently selected LMS player.

## Files

- `Plugin.pm` — LMS plugin code
- `install.xml` — plugin manifest
- `repo.xml` — LMS Additional Repository index
- `dist/YandexTitle-0.2.0.zip` — installable package
- `home-assistant/automation.yaml` — Home Assistant metadata forwarding automation
- `CHANGELOG.md` — version history
