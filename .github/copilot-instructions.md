# Copilot Instructions for WLED-Audio-Sender

## Repository Overview

**WLED Audio Sender** is a Flutter/Dart cross-platform application that captures audio from the device microphone, processes it in real-time using FFT analysis, and sends it to WLED devices using the WLED Audio Sync v2 protocol via UDP multicast.

**Project Type**: Flutter mobile/desktop application  
**Primary Language**: Dart  
**Target Platforms**: Android, iOS, macOS  
**Repository Size**: Small (entire app in single ~600-line file)  
**App ID**: net.netmindz.wled.sender

## Key Technologies & Frameworks

- **Flutter SDK**: Version 3.16.0+ (stable channel) - Required for all builds
- **Dart**: Version >=2.19.1 <3.0.0
- **Key Dependencies**:
  - `mic_stream` (0.6.4): Audio capture from microphone (includes permission handling)
  - `fftea` (1.2.0+1): FFT (Fast Fourier Transform) implementation
  - `record` (4.4.4): Audio recording support
  - `cupertino_icons` (1.0.2): iOS-style icons
- **Android**: Gradle 8.1.4, Kotlin 1.9.0, compileSdk 35, minSdk 21, targetSdk 35
- **iOS**: Minimum deployment target iOS 11.0
- **macOS**: Minimum deployment target macOS 10.14

## Build & Validation Commands

### Initial Setup
**ALWAYS run these commands in this exact order before any build:**
```bash
flutter pub get
```

This command:
- Downloads all dependencies from pubspec.yaml
- Generates necessary Flutter configuration files
- Must complete successfully before any other Flutter command
- Takes ~10-30 seconds on first run, faster with cache

### Linting
```bash
flutter analyze
```

- Runs static analysis on all Dart code
- Uses rules from `analysis_options.yaml` (includes `package:flutter_lints/flutter.yaml`)
- **Expected Issues**: The codebase has 1 known linting issue (`library_private_types_in_public_api` in lib/main.dart:119) - this is acceptable
- Takes ~10 seconds
- Exit code 0 = no critical issues, exit code 1 = issues found

### Testing
```bash
flutter test
```

- Runs widget tests in the `test/` directory
- **Known Issue**: The default widget test in `test/widget_test.dart` is boilerplate and WILL FAIL - this is expected and does not indicate a problem with your changes
- Only run tests related to files you modify
- Takes ~10-20 seconds

### Building for Platforms

**Android APK (Debug):**
```bash
flutter build apk --debug
```
Output: `build/app/outputs/flutter-apk/app-debug.apk`

**Android APK (Release):**
```bash
flutter build apk --release
```
- Requires `android/key.properties` file with signing credentials (see Release Builds section)
- Output: `build/app/outputs/flutter-apk/app-release.apk`
- Takes ~60-120 seconds

**Android App Bundle (Release):**
```bash
flutter build appbundle --release
```
- Requires signing configuration
- Output: `build/app/outputs/bundle/release/app-release.aab`
- Takes ~60-120 seconds

**iOS (No Code Sign):**
```bash
flutter build ios --release --no-codesign
```
- Only works on macOS
- Output: `build/ios/iphoneos/Runner.app`
- Takes ~60-90 seconds

**macOS:**
```bash
flutter build macos --release
```
- Only works on macOS
- Output: `build/macos/Build/Products/Release/Runner.app`
- Takes ~60-90 seconds

### Common Build Issues & Workarounds

**Issue**: `Flutter SDK not found`  
**Solution**: Ensure Flutter is in PATH and `flutter doctor` passes

**Issue**: Android builds fail with signing errors  
**Solution**: For release builds, ensure `android/key.properties` exists with valid signing credentials, OR build debug APK instead

**Issue**: Gradle daemon issues  
**Solution**: Run `cd android && ./gradlew --stop && cd ..` to stop all Gradle daemons, then retry

**Issue**: Dependencies out of sync  
**Solution**: Run `flutter clean && flutter pub get` to reset build state

## Project Structure & Architecture

### Root Files
- `pubspec.yaml`: Project configuration, dependencies, and metadata
- `analysis_options.yaml`: Linting rules (uses flutter_lints package)
- `.gitignore`: Standard Flutter gitignore (excludes build/, .dart_tool/, android/local.properties, android/key.properties)
- `README.md`: User-facing documentation with protocol details and build instructions

### Source Code
- `lib/main.dart`: **ENTIRE APPLICATION** - All app logic in single file
  - Main application entry point
  - Audio capture and processing
  - FFT analysis (512-point FFT with Hanning window)
  - UDP multicast transmission (port 11988, address 239.0.0.1)
  - WLED Audio Sync v2 packet format implementation
  - UI with waveform visualization

### Android Configuration
- `android/app/build.gradle`: App-level build configuration
  - Package name: `net.netmindz.wled.sender`
  - Signing configuration reads from `android/key.properties` (if exists)
  - Gradle Plugin version: 8.1.4
- `android/build.gradle`: Project-level build configuration
- `android/gradle.properties`: Gradle performance settings
  - JVM heap: 2GB (can increase to 4GB if builds fail with OOM)
  - Caching enabled: `org.gradle.caching=true`
  - Parallel builds enabled: `org.gradle.parallel=true`
- `android/gradlew`: Gradle wrapper script (use `./gradlew` for direct Gradle commands)
- `android/local.properties`: Auto-generated, contains Flutter SDK path (gitignored)
- `android/key.properties`: Signing credentials for release builds (gitignored, required for release)

### iOS Configuration
- `ios/Podfile`: CocoaPods dependency management
  - Minimum iOS version: 11.0
  - ALWAYS references only `Runner` target (not `RunnerTests`)
- `ios/Runner/Info.plist`: App metadata and permissions
- CocoaPods: Run `cd ios && pod install` if Podfile changes (rare)

### macOS Configuration
- `macos/Podfile`: CocoaPods dependency management
  - Minimum macOS version: 10.14
  - ALWAYS references only `Runner` target
- `macos/Runner/Info.plist`: App metadata and permissions

### Tests
- `test/widget_test.dart`: Boilerplate test that doesn't match actual app (WILL FAIL - this is OK)

## CI/CD Pipeline

### GitHub Actions Workflow: `.github/workflows/release.yml`

**Triggers:**
- Git tags matching `v*` (e.g., v1.0.0)
- Manual workflow dispatch

**Jobs:**

1. **build-android** (Ubuntu runner, ~5-10 minutes)
   - Java 17 (Zulu distribution)
   - Flutter 3.16.0
   - Requires secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
   - Decodes keystore from base64 secret to `android/app/release.keystore`
   - Generates `android/key.properties` from secrets
   - Runs `flutter pub get`
   - Builds APK and App Bundle
   - Uploads artifacts: `android-apk/app-release.apk`, `android-appbundle/app-release.aab`

2. **build-ios** (macOS runner, ~8-12 minutes)
   - Flutter 3.16.0
   - Builds unsigned IPA with `--no-codesign`
   - Creates IPA by zipping Runner.app into Payload directory
   - Uploads artifact: `ios-ipa/app-release.ipa`

3. **build-macos** (macOS runner, ~8-12 minutes)
   - Flutter 3.16.0
   - Builds macOS app bundle
   - Zips Runner.app to `WLED-Audio-Sender-macos.zip`
   - Uploads artifact: `macos-app/WLED-Audio-Sender-macos.zip`

4. **create-release** (Ubuntu runner, conditional on tag push)
   - Downloads all artifacts
   - Creates GitHub release with all platform builds

**Gradle Caching**: Workflow caches `~/.gradle/caches`, `~/.gradle/wrapper`, `~/.android/build-cache` using hash of `**/*.gradle*` files

**Permissions**: 
- Build jobs: `contents: read`
- Release job: `contents: write`

### Replicating CI Locally

To reproduce CI builds locally:
1. Set up environment matching CI (Flutter 3.16.0, Java 17 for Android)
2. For Android: Create `android/key.properties` with your signing credentials
3. Run: `flutter pub get && flutter build apk --release && flutter build appbundle --release`
4. For iOS/macOS: Must be on macOS with Xcode installed

## Release Build Requirements

### Android Signing Configuration

Release builds require a Java keystore and `android/key.properties` file.

**Create keystore** (one-time):
```bash
keytool -genkey -v -keystore release-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**Create `android/key.properties`** (gitignored):
```properties
storeFile=release-keystore.jks
storePassword=<your_store_password>
keyAlias=<your_key_alias>
keyPassword=<your_key_password>
```

**CRITICAL**: Never commit keystore files or `key.properties` to version control - they are gitignored by default.

### GitHub Actions Secrets

For automated releases, configure these repository secrets:
- `ANDROID_KEYSTORE_BASE64`: Base64-encoded keystore file
  ```bash
  base64 -w 0 release-keystore.jks  # Linux
  base64 -i release-keystore.jks    # macOS
  ```
- `ANDROID_KEYSTORE_PASSWORD`: Password for the keystore
- `ANDROID_KEY_ALIAS`: Key alias (e.g., "upload")
- `ANDROID_KEY_PASSWORD`: Password for the key

## WLED Audio Sync v2 Protocol Details

The app implements the WLED Audio Sync v2 protocol, sending 52-byte UDP packets:

**Packet Structure:**
- Header: "000002" (6 bytes) - Protocol version identifier
- Sample Raw: float32 (4 bytes) - Current audio level (0-255)
- Sample Smooth: float32 (4 bytes) - Smoothed audio level using exponential filter
- Sample Peak: uint8 (1 byte) - Peak detection flag (0 or 1)
- Reserved: uint8 (1 byte) - Reserved for future use
- FFT Result: 16x uint8 (16 bytes) - 16 frequency bins, logarithmically spaced
- FFT Magnitude: float32 (4 bytes) - Overall FFT magnitude
- FFT Major Peak: float32 (4 bytes) - Dominant frequency in Hz

**Network Details:**
- Protocol: UDP Multicast
- Port: 11988
- Multicast Address: 239.0.0.1
- Endianness: Little-endian for float32 values

**Audio Processing:**
- Sample Rate: 44.1 kHz
- Format: PCM 16-bit
- FFT: 512-point with Hanning window
- Frequency Bins: 16 bins using logarithmic spacing for musical representation

## Code Conventions & Best Practices

### Linting
- Follow `package:flutter_lints/flutter.yaml` rules
- Run `flutter analyze` before committing
- One known acceptable issue: `library_private_types_in_public_api` in main.dart:119

### Testing
- Widget tests in `test/` directory
- The existing test is boilerplate and doesn't match the app - ignore failures
- Add tests for new features or bugfixes when appropriate

### Dependencies
- Pin specific versions in `pubspec.yaml` to avoid breaking changes
- Run `flutter pub get` after any pubspec.yaml changes
- Run `flutter pub upgrade` cautiously - test thoroughly after upgrades

### Platform-Specific Code
- Android permissions must be declared in `android/app/src/main/AndroidManifest.xml`
- iOS permissions in `ios/Runner/Info.plist` 
- macOS permissions in `macos/Runner/Info.plist`
- Microphone permission already configured for all platforms

## Troubleshooting Common Issues

### Build Failures

**Symptom**: `Gradle build failed` or timeout  
**Fix**: Increase `org.gradle.jvmargs` heap size in `android/gradle.properties` to `-Xmx4096M`

**Symptom**: `Flutter SDK not found`  
**Fix**: Run `flutter doctor` to diagnose setup issues

**Symptom**: `Execution failed for task ':app:lintVitalRelease'`  
**Fix**: Skip lint for faster release builds: `flutter build apk --release --no-shrink` OR add `lintOptions { checkReleaseBuilds false }` to android/app/build.gradle

**Symptom**: Test failures in `widget_test.dart`  
**Expected**: The default widget test is boilerplate and will fail - this is not a problem

### Runtime Issues

**Symptom**: No audio data being sent  
**Check**: Microphone permissions granted on device

**Symptom**: WLED devices not receiving data  
**Check**: Device on same network, firewall allows UDP multicast on port 11988

## Important Notes for AI Coding Agents

1. **ALWAYS run `flutter pub get` first** before any build, test, or analyze command
2. **Build artifacts are in `build/` directory** - this is gitignored
3. **The entire app is in `lib/main.dart`** - no other source files exist
4. **Test failure in widget_test.dart is expected** - it's boilerplate that doesn't match the app
5. **Android release builds require signing** - use debug builds for testing or set up key.properties
6. **Flutter analyze will show 1 info-level issue** - this is acceptable
7. **Gradle builds can take 60-120 seconds** - use appropriate timeouts for async commands
8. **Never commit `android/key.properties` or keystore files** - they're gitignored for security
9. **The app uses UDP multicast** - testing requires physical devices or special emulator setup
10. **Trust these instructions** - only search for information if these instructions are incomplete or incorrect

## Validation Steps

Before finalizing changes:
1. Run `flutter analyze` - should pass (1 info-level issue OK)
2. Run `flutter pub get` - should complete without errors
3. For UI changes: Build and run on at least one platform
4. For protocol changes: Verify packet format matches WLED Audio Sync v2 spec
5. Check that no sensitive files (key.properties, keystores) are staged for commit
6. Review that only intended files are modified - use `git diff` to verify

## References

- WLED Audio Sync Documentation: https://mm.kno.wled.ge/soundreactive/sync/#v2-format-wled-version-0140-including-moonmodules-fork
- WLED-MM Audio Reactive: https://github.com/netmindz/WLED-MM/blob/mdev/usermods/audioreactive/audio_reactive.h
- Flutter Documentation: https://docs.flutter.dev/
