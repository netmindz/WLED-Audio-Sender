# WLED Audio Sender - TODO

## Outstanding: Internal Audio (Loopback) Capture Stops on App Switch

### Problem

When capturing internal audio via MediaProjection, switching away from the app and then switching back causes the capture to stop. Logcat shows:

```
MediaProjection: Dispatch stop to 0 callbacks.
MediaProjection: Content Recording: stopping projection
```

This happens even though:
- The foreground service (`AudioCaptureForegroundService`) is still running
- `onDestroy` no longer calls `stopCapture()`
- The `isRunning` flag and event sink re-attachment logic are in place

### Root Cause (Under Investigation)

When the user navigates back to the app, FlutterActivity is recreated (new `onCreate`). This activity lifecycle change appears to cause Android to stop the MediaProjection, even though the foreground service itself remains alive. The MediaProjection token may be tied to the activity that requested it, so when that activity is destroyed/recreated, the projection is invalidated by the system.

### Possible Fixes to Investigate

1. **Use `singleTask` or `singleInstance` launch mode** — Prevent activity recreation entirely when switching back. Currently using `singleTop`, which still allows recreation in some cases.

2. **Register a MediaProjection callback** — Use `MediaProjection.registerCallback()` to detect when the projection is stopped, and handle it gracefully (e.g. notify the user or attempt to re-request).

3. **Store MediaProjection in the Service, not tied to Activity** — The projection is already created inside the service's `onStartCommand`, but the `resultCode` and `data` Intent used to create it originate from the activity's `onActivityResult`. Once the activity is destroyed, Android may invalidate the token. Investigate whether caching the projection token or creating it differently can decouple it from the activity lifecycle.

4. **Prevent activity destruction** — Add `android:configChanges` to the manifest to prevent the activity from being destroyed on common configuration changes. Or investigate why navigating back triggers a full destroy/recreate rather than just `onPause`/`onResume`.

5. **Move to a fully service-based architecture** — Have the service own the entire audio pipeline (capture + FFT + UDP send) so it doesn't depend on the Flutter UI at all. The Flutter side would only control start/stop and display visualizations. This is a larger refactor but would be the most robust solution.

### How to Reproduce

1. Open the app, go to Settings, select "Internal" audio source
2. Tap the mic button, approve the screen recording dialog
3. Audio capture starts (VU meter responds to music playing on the phone)
4. Switch to another app (e.g. open a music player)
5. Switch back to WLED Audio Sender
6. Capture has stopped — VU meter no longer responds

### Relevant Files

- `android/app/src/main/kotlin/net/netmindz/wled/sender/MainActivity.kt`
- `android/app/src/main/kotlin/net/netmindz/wled/sender/AudioCaptureForegroundService.kt`
- `android/app/src/main/AndroidManifest.xml`

---

## Other

- [ ] iOS build is still unsigned — needs Apple Developer setup to distribute
