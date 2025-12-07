Very early stages of a Flutter / Dart app to capture Audio and send as WLED Audio Sync data

## Building

This Flutter application can be built for multiple platforms:

### Prerequisites
- Flutter SDK (3.16.0 or later)
- For Android: Java 17+
- For iOS/macOS: Xcode (macOS only)

### Build Commands

**Android:**
```bash
flutter build apk --release        # Build APK
flutter build appbundle --release  # Build App Bundle (for Play Store)
```

**iOS:**
```bash
flutter build ios --release --no-codesign
```

**macOS:**
```bash
flutter build macos --release
```

## Releases

Release artifacts are automatically built and published when a new version tag is pushed:

```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

The GitHub Actions workflow will automatically:
1. Build APK and App Bundle for Android
2. Build IPA for iOS
3. Build app bundle for macOS
4. Create a GitHub release with all artifacts

You can also manually trigger the build workflow from the Actions tab in GitHub.
