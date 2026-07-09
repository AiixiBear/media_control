# 大便媒體控制

Android Flutter app with a local Web UI for inspecting and controlling active media sessions on the phone.

## What it does

- Serves a browser-friendly dashboard from the phone itself.
- Shows the active media session name, artist, album, progress, and state.
- Sends play, pause, next, previous, and seek commands through Android media sessions.

## Setup

1. Install the app on an Android device.
1. Open the app and tap the notification access button.
1. Enable notification access for Media Control in Android settings.
1. Start playback in another media app.
1. Open the local Web UI URL from another device on the same Wi-Fi network.

## Notes

- The phone must stay reachable on the local network for other devices to connect.
- Android notification access is required so the app can discover active media sessions.
- The Web UI updates once per second while it is open.

## Home Assistant API

The local server also exposes Home Assistant-style REST endpoints:

- `GET /api/home-assistant/config` returns entity metadata.
- `GET /api/home-assistant/media-player` returns the current media_player state and attributes.
- `POST /api/home-assistant/media-player/command` sends control actions.

Example command body:

```json
{
	"action": "media_play_pause",
	"packageName": "com.example.music"
}
```

Supported actions include `media_play`, `media_pause`, `media_play_pause`, `media_next_track`, `media_previous_track`, and `media_seek`.


## 關於本App語言

本App是繁體中文為主，但是你可能會看不懂使用者介面裡面的語法，那是因為我採用了狗屎語法，我開心就好