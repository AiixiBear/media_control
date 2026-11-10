# 大便媒體控制

Android Flutter app with a local Web UI for inspecting and controlling active media sessions on the phone.

## 功能

- 從手機本身提供一個瀏覽器可開的 Web UI，即時顯示正在播放的媒體（標題、演出者、專輯、封面、進度、狀態）。
- Web UI 可播放 / 暫停 / 上一首 / 下一首，點進度條可跳轉播放位置。
- 提供 Home Assistant 風格的 REST API（見下方）。
- 支援密碼保護：Web UI 與 API 都需要同一組密碼（見「密碼與安全」）。

## 使用方式

1. 在 Android 裝置上安裝 App。
1. 打開 App，點「通知存取權限」卡片裡的「開啟設定」，在系統設定中找到「大便媒體控制」並開啟「通知存取」——沒有這個權限，App 看不到其他 App 在播什麼。
1. 在其他媒體 App 開始播放音樂或影片。
1. 在 App 主畫面確認伺服器「正在跑」，把顯示的 Web UI 網址（例如 `http://192.168.0.2:8080/`）在同一區網的其他裝置瀏覽器打開。

## 設定（主畫面右上「設定」）

- **密碼保護**：設定 Web UI 與 API 共用的密碼。至少 8 個字元，不可含空白與 `/ ? # \ < >`。也可以點「產生隨機密碼」產生一組 16 字元的隨機密碼。留空代表不設密碼，但區網內任何裝置都可控制播放，主畫面會顯示警告。
- **伺服器**：連接埠（預設 8080）、監聽介面（預設全部 IPv4）、Web UI 更新方式（即時推送 SSE 或每秒輪詢）。
- **Web UI 網址**：顯示目前的完整網址（含密碼前綴），可一鍵複製。
- **主題**：跟隨系統 / 深色 / 淺色，立即套用。

密碼、連接埠或更新方式變更後，需要重新啟動伺服器才會生效（儲存時 App 會詢問是否重啟）。

## 密碼與安全

- 密碼只存在手機的 SharedPreferences 裡，程式碼中沒有寫死的密碼。
- 呼叫 API 時請用標頭帶密碼（建議，密碼不會出現在網址裡）：
  `Authorization: Bearer <密碼>` 或 `X-Api-Key: <密碼>`
- 也可以用網址前綴：`http://<手機 IP>:<連接埠>/<密碼>/`，例如 `http://192.168.0.2:8080/你的密碼/`。Web UI 在需要密碼時會顯示登入框，輸入後會自動跳到帶密碼前綴的網址。
- 更換密碼後，Home Assistant 也要同步更新（標頭或網址前綴擇一），舊密碼會立即失效。
- 注意：這是區網內的 HTTP 服務，沒有 TLS 加密，請勿把連接埠暴露到網際網路。

## Web UI

- 即時更新預設用 SSE（`/api/events`）推送，連線中斷時自動改為每秒輪詢；也可以在設定裡強制改用每秒輪詢。
- 進度條點一下可跳轉播放位置；有封面時會顯示專輯封面。
- 響應式版面：手機與桌機瀏覽器都可使用。
- 音量控制目前不支援：Android 媒體進程沒有提供統一的音量 API，所以 Web UI 沒有音量滑桿。

## 架構

`lib/main.dart` 只是進入點，程式碼已拆成模組：

```
lib/
  main.dart                  # 進入點 + re-export（保持舊 import 可用）
  device_util.dart           # 裝置名稱
  api/media_control_api.dart # MediaControlApi 抽象 + MethodChannel 實作
  models/media.dart          # MediaSnapshot / MediaSessionInfo / HA JSON
  server/
    server_settings.dart     # 密碼、連接埠、更新方式、授權檢查
    media_control_server.dart# HttpServer、路由、SSE 推送
    home_assistant.dart      # HA 指令解析（可單獨測試）
    web_ui.dart              # Web UI 的 HTML / CSS / JS
  ui/
    app.dart                 # 主畫面狀態、伺服器啟停、設定讀寫
    settings_page.dart       # 設定頁
    app_settings.dart        # 主題設定
    app_colors.dart          # 深色 / 淺色共用的顏色
    widgets.dart             # 主畫面各卡片
test/
  auth_test.dart             # 密碼驗證、隨機密碼、HA 指令解析
  server_test.dart           # 伺服器黑盒測試（401 / Bearer / SSE / seek）
  app_settings_test.dart     # 主題設定解析
  widget_test.dart           # 主畫面渲染 + 密碼路由
```

## 開發：建置與測試

```sh
flutter pub get
flutter analyze
flutter test
```

建置 Android APK（或用 GitHub Actions 的 `build-android.yml` 手動觸發）：

```sh
flutter build apk --release
flutter build apk --release --split-per-abi
```

> 注意：`flutter_launcher_icons` 已由 `^0.13.1` 升級到 `^0.14.4`，因為 0.13.1 要求 Dart 2，在目前的 Dart 3 / Flutter stable 上 `flutter pub get` 無法解析依賴。

## Home Assistant API

Here is a simple Home Assistant Integration:

[Home Assistant Integration](https://github.com/AiixiBear/media_control_ha)

OR You can build one yourself:

The local server also exposes Home Assistant-style REST endpoints:

- `GET /api/home-assistant/config` returns entity metadata (includes `requires_auth` and how to present the token — never the token itself).
- `GET /api/home-assistant/media-player` returns the current media_player state and attributes.
- `POST /api/home-assistant/media-player/command` sends control actions.
- `GET /api/state` returns the raw snapshot JSON.
- `GET /api/events` is the SSE stream of snapshots.
- `GET /api/auth/check` returns `{authenticated, auth_required}`.

Example command body (with a password set, send `Authorization: Bearer <密碼>`):

```json
{
	"action": "media_play_pause",
	"packageName": "com.example.music"
}
```

Supported actions include `media_play`, `media_pause`, `media_play_pause`, `media_next_track`, `media_previous_track`, and `media_seek`.

## Notes

- The phone must stay reachable on the local network for other devices to connect.
- Android notification access is required so the app can discover active media sessions.
- The Web UI updates live via SSE by default, falling back to once-per-second polling.

## 關於本App語言

本App是繁體中文為主

## License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

### ⚠️ App Icon Exception
Please note that the **App Icon** (`assets/images/`) is **NOT** covered by the MIT License.
