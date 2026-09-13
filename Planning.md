# IDLIX-App: Architecture, Technical Specification & Project Plan

## 1. Project Vision & Executive Summary

**IDLIX-App** is a dedicated, high-performance streaming client built with Flutter and engineered specifically for the **IDLIX** streaming platform. It delivers an ad-free, secure, and native-feeling experience across two distinct hardware environments:
1. **Android TV & Android Box (STB):** A 10-foot user experience designed for living room televisions, powered by a virtual mouse cursor navigated via physical remote D-Pad controls, custom TV zoom presets, and an automated Leanback launcher integration.
2. **Android Smartphones & Tablets:** A sleek, touch-first, immersive interface devoid of redundant navigation bars, equipped with a circular draggable cast button.

The application eliminates the friction of traditional web streaming on Android:
- **No Manual Configuration:** The active IDLIX domain is fetched dynamically from GitHub raw JSON (`config.json`), ensuring zero-friction setup and instant domain rotation.
- **Aggressive Ad & Popup Neutralization:** Eliminates malicious popunders, trap tabs, and phishing redirects with real-time **"Popup Ads Blocked"** shield feedback.
- **Cinematic Experience:** Features a Netflix-inspired ribbon splash screen during cold starts.
- **Direct In-App Updates:** Seamlessly checks for newer releases from GitHub Releases and conducts direct in-app downloading and native package installation.
- **Smart TV Casting:** Automatically captures video streams (HLS `.m3u8`, MP4) and subtitles (Indonesian & English `.vtt`/`.srt`) for direct playback on Google Cast / Chromecast and DLNA / UPnP devices.

---

## 2. Technology Stack & Dependencies

- **Framework:** Flutter 3 (Dart 3.x)
- **Target Platform:** Android (API Level 21+ / Android 5.0 Lollipop through Android 14+)
- **Core Modules:**
  - `webview_flutter` & `webview_flutter_android`: High-performance WebKit/Chromium web engine with hardware acceleration.
  - `dart_cast`: Multi-protocol casting supporting Google Cast and DLNA / UPnP Smart TVs.
  - `shared_preferences`: Encrypted local persistence for cached remote configs and application state.
  - Native Kotlin MethodChannel (`com.idlix.app/installer`): Android `FileProvider` and native `ACTION_VIEW` intent dispatch for in-app APK installations.

---

## 3. High-Level System Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                               IDLIX-App                                │
├──────────────────────────────────┬─────────────────────────────────────┤
│      Mobile Flavor (IDLIX)       │      TV Flavor (IDLIX TV)           │
│  - Fullscreen Touch UI           │  - Leanback TV Launcher & Banner    │
│  - Draggable Circular Cast FAB   │  - Remote D-Pad Virtual Cursor      │
│  - Auto-Detect Video Streams     │  - TV Quick Menu & Couch Zoom (125%)│
└──────────────────────────────────┴─────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│                             Core Layer                                 │
├──────────────────────────┬─────────────────────────┬───────────────────┤
│  RemoteConfigService     │  WebViewNavigation      │  AppUpdateService │
│  - GitHub Raw config.json│  - Domain Allowlist     │  - Version Check  │
│  - jsDelivr CDN fallback │  - Ad & Popup Blocking  │  - Direct In-App  │
│  - SharedPreferences     │  - "Popup Ads Blocked"  │    APK Download   │
└──────────────────────────┴─────────────────────────┴───────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Presentation & Features                         │
├──────────────────────────┬─────────────────────────┬───────────────────┤
│    IdlixSplashScreen     │  VideoDetectorService   │    CastManager    │
│  - Netflix ribbon glow   │  - HLS / MP4 Sniffer    │  - Google Cast    │
│  - Radial pulsating bloom│  - VTT / SRT Subtitles  │  - DLNA / UPnP    │
│  - Smooth zoom & fade    │  - Player iframe bridge │  - Full Controls  │
└──────────────────────────┴─────────────────────────┴───────────────────┘
```

---

## 4. Application Flow & Lifecycle

```
[Application Startup]
        │
        ├──► Render [IdlixSplashScreen] (Netflix-style ribbon animation & radial glow)
        │
        ├──► Query [RemoteConfigService] (Fetch GitHub raw config.json / local cache)
        │         │
        │         ├── Success: Configure WebViewController with active IDLIX domain
        │         └── Failure: Fallback to cached or hardcoded fallback mirror
        │
        ├──► Trigger [AppUpdateService.checkForUpdate()]
        │         │
        │         ├── Newer Version Found: Present [AppUpdateDialog] (In-App Update)
        │         └── Up to Date: Silent continuation
        │
        ├──► Load Web Page in WebView
        │         │
        │         ├── Intercept Navigation: Block external schemes & ad domains
        │         ├── Neutralize Popups: Block window.open & redirect target=_blank
        │         ├── Inject Stream Sniffer: VideoDetectorService JS bridge
        │         └── On Finished: Trigger splash screen fade-out transition
        │
        └──► User Interaction Mode
                  │
                  ├── Mobile: Direct touch gestures + Draggable Cast FAB
                  └── TV: Remote D-Pad Virtual Mouse + TV Quick Menu
```

---

## 5. Detailed Feature Specifications

### 5.1. Dynamic Domain Resolution (No Backend)
- **Objective:** Eliminate hardcoded domains and manual URL entry. When IDLIX changes mirror domains, modifying `config.json` in the GitHub repository dynamically re-routes all user installations.
- **Endpoints:**
  1. Primary: `https://raw.githubusercontent.com/Asadaaaaa/IDLIX-App/main/config.json`
  2. CDN Mirror: `https://cdn.jsdelivr.net/gh/Asadaaaaa/IDLIX-App@main/config.json`
  3. Local Cache: Persistent `SharedPreferences`
- **Schema:**
  ```json
  {
    "url": "https://z2.idlixku.com",
    "allowed_host": "idlixku.com",
    "name": "IDLIX",
    "updated_at": "2026-09-12",
    "latest_version": "1.6.0",
    "latest_version_code": 16,
    "release_notes": "...",
    "mobile_apk_url": "https://github.com/Asadaaaaa/IDLIX-App/releases/download/v1.6.0/IDLIX.apk",
    "tv_apk_url": "https://github.com/Asadaaaaa/IDLIX-App/releases/download/v1.6.0/IDLIX-TV.apk"
  }
  ```

### 5.2. Netflix-Style Cinematic Splash Screen
- **Class:** `IdlixSplashScreen`
- **Visual Design:**
  - Dark background (`#0A0D14` to deep black gradient).
  - Netflix-inspired IDLIX emblem with a red ribbon styled through custom clipping and multiple paint layers.
  - Pulsating radial glow with additive blending.
  - Coordinated animation choreography:
    - Scale: $0.70 \rightarrow 1.06 \rightarrow 1.00$ (`Curves.easeInOut`).
    - Letter-spacing: $2.0 \rightarrow 6.0$ units.
    - Radial bloom opacity: $0.2 \rightarrow 1.0 \rightarrow 0.6$.
- **Dismissal Logic:** Holds for a minimum of 1800ms for cinematic presentation. If the web page finishes loading before 1800ms, it waits for animation completion before fading out. If the web page takes longer, a sleek progress indicator reflects active download percentage until `onPageFinished`.

### 5.3. In-App Update Engine
- **Classes:** `AppUpdateService`, `AppUpdateDialog`, `MainActivity.kt`
- **Workflow:**
  1. `AppUpdateService.checkForUpdate()` compares `latest_version_code` vs installed build version.
  2. If an update exists, `AppUpdateDialog` presents release notes and a **"Update Now"** action.
  3. Clicking "Update Now" downloads the APK directly from GitHub Releases:
     - Handles HTTP 301/302 redirects (e.g. GitHub to AWS S3 CDN).
     - Emits continuous byte-level progress to update the linear progress bar in real time.
     - Saves the payload into the app's secure cache directory (`idlix_update.apk`).
  4. Once downloaded, `MainActivity.kt` executes the native installation intent:
     - Generates a content URI via `androidx.core.content.FileProvider`.
     - Grants `FLAG_GRANT_READ_URI_PERMISSION`.
     - Fires `Intent(Intent.ACTION_VIEW)` with MIME type `application/vnd.android.package-archive`.

### 5.4. Android TV & STB Remote D-Pad Navigation (Netflix Style)
- **Classes:** `TvRemoteController`, `TvSpatialNavigationScript`, `TvQuickMenu`
- **Hardware Profile:**
  - Declares `android.software.leanback` (optional) and `android.hardware.touchscreen` as false.
  - Integrates 16:9 Leanback banner for the Android TV launcher.
- **Netflix-Style Spatial Focus Navigation:**
  - Replaces exhausting virtual mouse pointers with direct, 2D spatial element and button selection.
  - Directional navigation (`KEYCODE_DPAD_UP`, `DOWN`, `LEFT`, `RIGHT`) calculates spatial Euclidean proximity and axis overlap to jump seamlessly between movie posters, episodes, servers, and buttons.
  - Signature TV focus styling: vibrant red outline (`#E50914`), card scale-up animation (`scale(1.05)`), glowing outer shadow, and automated smooth viewport centering (`scrollIntoView`).
  - Center/OK button executes synthetic click sequences with active press visual feedback.
  - Boundary scrolling automatically scrolls the viewport smoothly when navigating past screen bounds.
- **TV Quick Menu:**
  - Activated by remote `KEYCODE_MENU` or context buttons.
  - Provides quick zoom presets (100%, 125%, 150%) for viewing from distance.
  - Reload, history navigation, and domain synchronization actions.

### 5.5. Video Stream & Subtitle Sniffer with Smart TV Casting
- **Classes:** `VideoDetectorService`, `CastManager`, `DraggableCastButton`, `CastControlBar`
- **JavaScript Injection Sniffer & Ad Filter:**
  - Monitors HTML5 `<video>`, `<source>`, and third-party web player wrappers (JWPlayer, Video.js, Plyr).
  - Intercepts `XMLHttpRequest.prototype.open` and `window.fetch` to detect `.m3u8` and `.mp4` URLs.
  - **Pre-Roll Ad Defense:** Filters out video ads (duration <= 65s, ad domains, ad containers, and ad keywords like `vast`, `preroll`).
  - **Skip-Ad Lifecycle Tracking:** Detects skip buttons, `adComplete`/`adSkipped` player events, and `durationchange`/`ended` events on `<video>` elements to immediately capture and prioritize the real movie stream as soon as the ad is skipped or finishes.
  - **Movie Stream Prioritization:** Automatically sorts streams by `priorityScore` (HLS master playlists, duration > 5m, attached subtitles) so the main movie is always selected first.
  - **Auto-Upgrade During Active Cast:** If casting begins during an ad or preview, `CastManager` automatically switches the cast stream to the true movie stream as soon as it begins playing.
  - Intercepts `<track>` elements and WebVTT/SRT network payloads for Indonesian and English subtitles.
- **Casting Protocol Support:**
  - **Google Cast:** Google Cast V2 channel support for Chromecast dongles, Android TV, and Google TV.
  - **DLNA / UPnP:** M-SEARCH SSDP discovery and SOAP AVTransport control for Samsung Tizen, LG webOS, Sony, and Roku TVs.
- **Playback Control Bar:**
  - Full transport control: Play, Pause, Seek slider, Volume adjustment, and live subtitle track selection.

### 5.6. Domain Lock & Popup Defense
- **Class:** `WebViewNavigationService`
- **Priority 1 (Schemes):** Blocks external schemes (`intent://`, `market://`, `whatsapp://`, etc.) from opening external applications.
- **Priority 2 (Ad Domains):** Filters known malicious ad and popunder domains (`*.doubleclick.net`, `*.popads.net`, `*.adsterra.com`, etc.).
- **Priority 3 (Domain Allowlist):** Enforces strict suffix domain checking to prevent subdomain bypass vulnerabilities (e.g. `idlixku.com.evil.com` is strictly rejected).
- **Popup Neutralization:** JavaScript overrides `window.open` and replaces `target="_blank"` attributes with `target="_self"`. Blocked attempts display an intuitive **"Popup Ads Blocked"** shield alert.

---

## 6. Project Directory Layout

```
.
├── config.json                          # Central dynamic configuration & update schema
├── IDLIX.apk                            # Precompiled Mobile/Tablet release APK
├── IDLIX-TV.apk                         # Precompiled Android TV/STB release APK
├── android/                             # Android native layer
│   └── app/src/main/
│       ├── AndroidManifest.xml          # TV Leanback, FileProvider, Permissions
│       ├── res/xml/file_paths.xml       # Cache path mapping for APK installation
│       └── kotlin/.../MainActivity.kt   # Native installer MethodChannel
├── lib/
│   ├── main_mobile.dart                 # Entry point: Mobile flavor (IDLIX)
│   ├── main_tv.dart                     # Entry point: Android TV flavor (IDLIX TV)
│   ├── app/app.dart                     # Root MaterialApp widget
│   ├── core/
│   │   ├── services/
│   │   │   ├── remote_config_service.dart
│   │   │   └── storage_service.dart
│   │   └── utils/
│   │       ├── domain_utils.dart
│   │       └── url_utils.dart
│   └── features/
│       ├── cast/                        # Video stream & subtitle sniffer, casting
│       ├── tv/                          # Android TV remote controller & virtual mouse
│       ├── update/                      # In-app update detection, downloader, modal
│       └── webview/                     # WebView core & Netflix-style splash screen
└── test/                                # Automated unit test suites
```

---

## 7. Quality Assurance & Test Verification

All critical modules are backed by automated tests:
1. `test/domain_utils_test.dart`: Validates domain allowlist matching, evil-domain bypass prevention, scheme blocking, and navigation priorities.
2. `test/remote_config_service_test.dart`: Validates local fallback caching, CDN endpoints, and JSON deserialization.
3. `test/video_detector_test.dart`: Tests HLS/MP4 regex sniffer, WebVTT/SRT subtitle matching, deduplication, and iframe player embed allowances.
4. `test/tv_remote_test.dart`: Tests cursor boundary clamping, acceleration rates, zoom scale updates, and remote key handling.
5. `test/app_update_test.dart`: Tests update schema deserialization, version comparison logic, and fallback URLs.

---

## 8. Build & Release Deployment

Build artifacts are separated into two distinct application flavors:

```bash
# Mobile Release Build (Smartphone & Tablet)
flutter build apk --release --flavor mobile -t lib/main_mobile.dart
# Output: build/app/outputs/flutter-apk/app-mobile-release.apk -> IDLIX.apk

# Android TV / STB Release Build
flutter build apk --release --flavor tv -t lib/main_tv.dart
# Output: build/app/outputs/flutter-apk/app-tv-release.apk -> IDLIX-TV.apk
```

Releases are published directly to GitHub Releases with matching tags (e.g. `v1.6.0`), and metadata is updated synchronously in `config.json` on the `main` branch to guarantee seamless in-app update delivery.
