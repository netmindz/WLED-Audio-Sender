# WLED Audio Sender

A mobile app that captures audio from the device microphone (or internal/loopback audio on Android), processes it in real-time, and sends WLED Audio Sync v2 UDP multicast packets to drive LED effects on [WLED](https://kno.wled.ge/) devices.

Available on [Google Play (internal testing)](https://play.google.com/store/apps/details?id=net.netmindz.wled.sender).

## Features

- **Microphone capture** — PCM 16-bit mono at 22050 Hz (matches WLED's native sample rate)
- **Internal audio capture (Android)** — Captures audio from other apps (music players, games) via Android's MediaProjection API. Requires approving a one-time "screen recording" permission dialog (Android limitation — there's no way to capture internal audio without it)
- **FFT analysis** — 512-point FFT with Hanning window, 16 frequency bins using WLED's exact logarithmic bin boundaries
- **AGC (Automatic Gain Control)** — Full port of WLED's PI controller with three presets: Normal, Vivid, Lazy
- **WLED Audio Sync v2** — Sends 44-byte UDP multicast packets to port 11988 (address 239.0.0.1 by default), compatible with WLED AudioReactive usermod
- **Visualization** — Real-time VU meter and spectrum analyser
- **Configurable settings** — Multicast address, port, AGC on/off, AGC mode, audio source (mic/internal), all persisted

## Usage

1. Install from Google Play or build from source (see below)
2. Tap the microphone button to start capturing audio
3. To use internal audio: go to Settings (gear icon), select "Internal" as the audio source, then tap the mic button and approve the dialog
4. Audio sync packets are sent automatically to WLED devices on your local network
5. On your WLED device, enable Audio Sync in the AudioReactive usermod and set it to "Receive"

## WLED Audio Sync v2 Packet Format

44-byte packets matching the `audioSyncPacket` struct from WLED's `audio_reactive.h`:

| Field | Size | Type | Description |
|-------|------|------|-------------|
| Header | 6 bytes | char[6] | `"00002\0"` — protocol version identifier |
| Pressure | 2 bytes | uint8[2] | Sound pressure (fixed-point: integer.fraction) |
| Sample Raw | 4 bytes | float32 | Raw/AGC-adjusted audio sample |
| Sample Smooth | 4 bytes | float32 | Smoothed audio sample |
| Sample Peak | 1 byte | uint8 | Peak detection flag (0=no peak, >=1=peak) |
| Frame Counter | 1 byte | uint8 | Rolling sequence counter |
| FFT Result | 16 bytes | uint8[16] | 16 GEQ frequency bins (0-255 each) |
| Zero Crossing Count | 2 bytes | uint16 | Zero crossings in sample window |
| FFT Magnitude | 4 bytes | float32 | Largest single FFT result |
| FFT Major Peak | 4 bytes | float32 | Dominant frequency in Hz |

## Known Issues

- **Internal audio capture stops when switching back to the app** — Android invalidates the MediaProjection token when the activity is recreated. See [todo.md](todo.md) for details and investigation notes.
- **iOS build is unsigned** — Needs Apple Developer Program enrollment to distribute.

## Privacy Policy

Audio is processed locally and only sent to WLED devices on your local network. No data is collected, stored, or transmitted to the internet. No analytics or third-party services are used.

Full policy: [Privacy Policy](https://netmindz.github.io/WLED-Audio-Sender/privacy-policy)

---

# Development

## Prerequisites

- Flutter SDK 3.27.4+ (CI uses 3.27.4)
- Android SDK with compileSdk 35
- Java 17

## Project Structure

```
lib/
  main.dart                    # App entry point, audio capture, FFT, UDP sending, settings UI
  models/
    audio_sync_packet.dart     # WLED v2 packet struct (44 bytes)
    agc.dart                   # AGC controller (ported from WLED)
  painters/
    vu_meter_painter.dart      # VU meter visualisation
    spectrum_painter.dart      # Spectrum analyser visualisation
  pages/
    details_page.dart          # Details/statistics page

android/app/src/main/kotlin/net/netmindz/wled/sender/
  MainActivity.kt             # Platform channels for internal audio capture
  AudioCaptureForegroundService.kt  # MediaProjection foreground service

test/
  widget_test.dart             # Widget + packet unit tests
```

## Key Dependencies

- `mic_stream` (0.7.2) — Microphone audio capture. Note: uses deprecated Flutter v1 Registrar API; compiles on Flutter 3.27.4 but fails on 3.41.6+
- `fftea` — FFT implementation
- `shared_preferences` — Persisted settings
- `permission_handler` — Runtime permissions

## Running Tests

The development machine is aarch64 with 16K page size, so Flutter cannot run natively. Tests run via Docker:

```bash
docker run --rm --platform linux/amd64 \
  -v /home/will/netmindz/WLED-Audio-Sender:/app -w /app \
  ghcr.io/cirruslabs/flutter:stable \
  bash -c 'flutter pub get && flutter test'
```

Tests take ~7 seconds. **Always run tests before pushing.**

## Building

APK builds under x86 Docker emulation are extremely slow (15-20+ min). Rely on CI for full builds. For on-device testing, install APKs from CI artifacts or use:

```bash
# Install from CI artifact
adb install app-release.apk

# If signature mismatch (different signing key), uninstall first
adb uninstall net.netmindz.wled.sender
adb install app-release.apk
```

## Android Build Configuration

- **Package name**: `net.netmindz.wled.sender`
- **AGP**: 8.7.3, **Kotlin**: 2.1.0, **Gradle**: 8.9
- **compileSdk**: 35, **minSdk**: 29 (Android 10, required for AudioPlaybackCapture)
- Declarative plugin DSL (migrated from legacy apply-based config)

## CI/CD

### Workflows

- **`ci.yml`** — Runs on every push. Calls `test.yml` then `build-android.yml`. On `main` branch, publishes AAB to Play Store internal track (`status: draft`).
- **`release.yml`** — Triggered by `v*` tags. Builds Android + iOS + macOS, creates GitHub Release with artifacts.
- **`test.yml`** — Reusable workflow: `flutter test`
- **`build-android.yml`** — Reusable workflow: keystore setup, git-hash versioning, APK + AAB build

### Versioning

CI generates versions like `0.0.5-829e1c4+1745012345` where:
- `0.0.5` — base version from `pubspec.yaml`
- `829e1c4` — short git hash for build identification
- `1745012345` — epoch seconds (used as Android `versionCode`)

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded release keystore |
| `ANDROID_KEY_ALIAS` | Key alias (e.g. `upload`) |
| `ANDROID_KEY_PASSWORD` | Key password |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Play Console API service account JSON |

### Signing

For local release builds, create `android/key.properties`:

```properties
storeFile=release-keystore.jks
storePassword=<your_store_password>
keyAlias=<your_key_alias>
keyPassword=<your_key_password>
```

Never commit `key.properties` or keystore files. The `base` file in the repo root is a keystore and is in `.gitignore`.

## Internal Audio Capture Architecture

Internal audio uses Android's `MediaProjection` + `AudioPlaybackCapture` APIs:

1. **Flutter** calls `startCapture` via `MethodChannel`
2. **`MainActivity`** requests `MediaProjection` permission (shows system dialog)
3. On approval, starts `AudioCaptureForegroundService` with the result intent
4. **`AudioCaptureForegroundService`** calls `startForeground()` first (required on Android 14+), then creates `MediaProjection` and `AudioRecord` with playback capture config
5. Audio data flows back to Flutter via `EventChannel` → processed alongside mic data in `main.dart`

The foreground service captures `USAGE_MEDIA`, `USAGE_GAME`, and `USAGE_UNKNOWN` audio sources.

**Known issue**: MediaProjection is invalidated when the activity is recreated (e.g. switching apps). See [todo.md](todo.md).

## References

- [WLED Audio Sync v2 Format](https://mm.kno.wled.ge/soundreactive/sync/#v2-format-wled-version-0140-including-moonmodules-fork)
- [WLED-MM AudioReactive source](https://github.com/netmindz/WLED-MM/blob/mdev/usermods/audioreactive/audio_reactive.h) — Reference implementation for packet format, FFT bins, and AGC
- [WLED-sync](https://github.com/netmindz/WLED-sync) — Related project
- [SR-WLED-audio-server-win](https://github.com/Victoare/SR-WLED-audio-server-win) — Windows audio server reference

## License

This project follows the same license as the WLED project.
