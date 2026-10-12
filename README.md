# ZipClip

A fast, modern short-video saver for Android, built with Flutter.

Paste a video link (or share one from any app), tap once, and the video is
saved to your phone — into the public gallery, ready in your video player.
No login, no analytics, no ads. Everything stays on your phone.

## Screens

- **Home** — paste card with clipboard detection, automatic link resolving,
  quality / format / watermark choices, one-tap download with live progress,
  and a "Saved in 1.8 s" done card (real measured time).
- **Downloads** — Video / Audio / Images tabs, "Saving now" card with
  pause/resume, queue, saved files with Play / Share / Copy link / Delete,
  swipe-to-delete with Undo, free-space chip.
- **Paste many links** — one link per line, resolved in parallel (max 4),
  per-link status (Ready / Duplicate / Not supported / Failed), skip
  duplicates, one button to queue them all.
- **Settings** — save folder, default quality/format, watermark default,
  Wi-Fi only, max parallel downloads (1–5), file name template, clipboard
  detection, optional quick-save bubble, notifications, privacy controls.

## The LinkResolver seam

All link-to-media extraction lives behind one clean interface:

```dart
// lib/core/resolver/link_resolver.dart
abstract class LinkResolver {
  bool supports(String url);
  Future<ResolvedMedia> resolve(String url); // throws ResolveException
}
```

`ResolvedMedia` carries title, author, duration, thumbnail URL and a list of
`MediaStream`s (label, size, container, hasAudio/hasVideo, `watermarkFree`).

The app ships with **`MockResolver`** (`lib/core/resolver/mock_resolver.dart`),
which accepts any public-looking link and returns sample metadata plus real,
publicly licensed sample files (Google's `gtv-videos-bucket` clips and the
SoundHelix sample MP3, sizes measured with a real HEAD request). That makes
the whole UI and the download engine work end-to-end — and fully testable —
with zero site-specific code.

### Plugging in a real resolver

1. Implement `LinkResolver` for your source (see the big comment block at the
   top of `mock_resolver.dart`).
2. Return it from `resolverProvider` in `lib/providers/bootstrap.dart`
   (in front of, or instead of, the `MockResolver`).

### ⚖️ Legal note — please read

**You** — the person plugging in a resolver — are responsible for making
sure it respects the source site's terms of service and the rights of the
video owner. ZipClip itself enforces these scope rules:

- Only **public** videos. The app never attempts to access private,
  protected or login-only content, and never bypasses DRM or access
  controls.
- A first-run notice and a permanent line on the Home screen say:
  *"Only save videos you made or have permission to keep."*
- No third-party brand names, logos or colors are used anywhere in the UI
  or the app icon.

## Download engine

`lib/core/engine/download_engine.dart` — the speed feature:

- One shared `dio` instance (HTTP connection reuse).
- If the server supports `Range`, large files split into **4 parallel
  segments** and are merged; otherwise a single stream.
- Queue with configurable parallelism (1–5), automatic retry with
  exponential backoff (3 tries: 2s → 4s → 8s).
- Pause/resume persisted per segment, so it **survives app restarts**.
- Cancel cleans up partial files.
- Downloads run in a native Android **foreground service** (type `dataSync`)
  with a notification showing live progress, speed, and Pause / Cancel
  actions — downloads continue when the app is closed.
- Finished files go to the public gallery via **MediaStore**
  (`Movies/ZipClip`, `Music/ZipClip`, `Pictures/ZipClip`), so they appear in
  the gallery immediately. No broad storage permission needed on Android 10+.
- Duplicate detection by normalized link (tracking params stripped) plus a
  history lookup, with a "Saved already" + Open affordance.
- Every number shown (%, MB/s, elapsed) is measured, never fabricated.

### Audio without ffmpeg

When you pick **Audio MP3**, ZipClip downloads the resolver's audio-only
stream directly — no re-encoding, no extra native libraries. (A "minimal
ffmpeg" re-encode add-on was considered and deliberately left out: it would
add ~20–30 MB per ABI and break the < 20 MB size target.) If your resolver
only offers video streams, plug the re-encode step into
`DownloadEngine._runTask` after the merge — the seam is documented there.

## Permissions

| Permission | When asked | Plain-words reason |
|---|---|---|
| Internet | install | Downloading videos, obviously. |
| Notifications (13+) | before first download, after an explainer | Live progress + "saved" ping. The app works fine without it. |
| Foreground service (`dataSync`) | install | Keeps downloads running when the app is closed. |
| Display over other apps | only if you enable the quick-save bubble | Draws the floating bubble. |
| Storage | only on Android 9 and below | Writing into the public gallery on old Android. |

## GitHub build (the only build)

Everything is built on GitHub Actions — nothing is built locally.

- Push to `main` (or dispatch manually): `flutter pub get` →
  `flutter analyze` (must be warning-free) → `flutter test` →
  `flutter build apk --release --split-per-abi`. APKs are uploaded as
  artifacts.
- Push a version tag (`v1.0.0`): additionally creates a GitHub Release with
  the APKs attached.
- Flutter is pinned to **3.47.7** (`subosito/flutter-action`), Java 17,
  minSdk 24, targetSdk 35. Dependency versions are pinned exactly in
  `pubspec.yaml` (resolved against that Flutter); `pubspec.lock` is
  committed too.

### Release signing (optional)

Without secrets the build falls back to a **debug-signed** APK so it always
succeeds. For a properly signed release:

1. Create a keystore (keep it safe — losing it means you can never update
   the app):
   ```sh
   keytool -genkey -v -keystore zipclip-release.jks -alias zipclip \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
2. In the GitHub repo: *Settings → Secrets and variables → Actions → New
   repository secret*:
   - `KEYSTORE_BASE64` — `base64 -w0 zipclip-release.jks`
   - `KEYSTORE_PASSWORD`
   - `KEY_ALIAS`
   - `KEY_PASSWORD`
3. Push again (or re-run the workflow): `android/app/build.gradle` picks up
   `android/key.properties` automatically when it exists.

### Install the APK

1. Open the workflow run → **Artifacts** → download `zipclip-apks`
   (or grab the APKs from the GitHub Release).
2. Pick the APK matching your phone's ABI (`arm64-v8a` for most modern
   phones), copy it to the phone, tap it, allow "Install unknown apps"
   when asked.

## Project structure

```
lib/
  main.dart                    # runApp immediately; everything loads async
  app.dart                     # MaterialApp + bottom tab shell
  core/
    theme/                     # ZipColors, ZipFonts, ThemeData, Pressable
    models/media.dart           # ResolvedMedia, MediaStream, SaveFormat
    resolver/                  # LinkResolver, MockResolver, LinkNormalizer, cache
    engine/                    # DownloadEngine, SegmentPlanner, RetryPolicy,
                               # FileNameTemplate, DownloadStore (+memory impl)
    storage/                   # sqflite AppDatabase, SharedPreferences settings
    native/zipclip_native.dart  # MethodChannel: gallery, service, bubble…
    utils/                     # format, batch_parser, pool, permissions
    widgets/zip_widgets.dart    # chips, buttons, thumbnails, rows…
  features/
    home/                      # Home screen + controller
    downloads/                 # Downloads screen + providers
    batch/                     # Paste-many screen + controller
    settings/                  # Settings screen
  providers/                   # bootstrap (DB, engine, settings…), task streams
android/                       # full native folder: manifest (share filter,
                               # foreground service), Kotlin plugin/services,
                               # Gradle (minSdk 24, Java 17, shrink+obfuscate)
test/                          # unit + engine integration tests
assets/
  fonts/                       # Sora, DM Sans, IBM Plex Mono (OFL, bundled)
  img/sample_thumb.jpg         # demo artwork for the MockResolver
```

## Tests

```
flutter test
```

Unit tests: link normalization & duplicate detection, batch parsing, file
name templates, segment planning/merging math, retry backoff, resolver
shape & stream picking. Integration tests (`test/download_engine_test.dart`)
run the real engine against a local HTTP server with Range support:
parallel segmented download merged byte-identical, pause/resume from
persisted progress, cancel cleanup, retry-then-succeed, permanent failure,
monotonic progress, max-parallel queueing, Wi-Fi-only gating.

## Performance notes

- Cold start: the first frame renders before the database/settings finish
  loading (all async providers fill in progressively).
- Resolved links are cached for 10 minutes; thumbnails are prefetched.
- Progress updates are throttled (~4 Hz) and per-task streams keep list
  rebuilds scoped.
- Release APKs are split per ABI with shrinking + obfuscation
  (target < 20 MB per ABI).

## Fonts

Bundled under `assets/fonts/` under the SIL Open Font License 1.1:
Sora (headings), DM Sans (UI), IBM Plex Mono (links/sizes/speeds).
No fonts are ever downloaded at runtime.
