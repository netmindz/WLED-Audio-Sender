# WLED Audio Sender - TODO

## Protocol Fixes (Critical - app packets were being rejected by WLED)
- [x] Fix packet structure to match WLED Audio Sync v2 (44 bytes)
  - [x] Fix header: `"00002"` + null terminator (not `"000002"`)
  - [x] Add `pressure[2]` field (uint8[2], sound pressure fixed-point)
  - [x] Add `frameCounter` field (uint8, rolling sequence counter)
  - [x] Add `zeroCrossingCount` field (uint16)
  - [x] Remove non-existent `reserved1` field
  - [x] Correct field ordering to match struct
- [x] Update README packet format table to match actual v2 spec
- [x] Update code comments to reflect correct 44-byte packet size

## Code Quality
- [x] Remove unused `record` dependency from pubspec.yaml
- [x] Add error handling for UDP socket binding failures
- [x] Add error handling for microphone permission denied / access failures
- [x] Close UDP socket on stop recording
- [x] Fix default widget test (was testing non-existent counter app)
- [x] Add unit test for AudioSyncPacket (44-byte output, correct header/fields)

## Features (Future)
- [ ] Settings UI for multicast address and port
- [ ] AGC (Automatic Gain Control) to match WLED's processing
- [ ] Verify FFT bin boundary calculation matches WLED's frequency mapping
- [ ] Split single-file architecture into separate files (models, services, UI)

## CI/CD & Distribution
- [x] Review GitHub Actions workflow
- [x] Add `flutter test` step to workflow (runs before all builds)
- [x] Update pinned Flutter version (3.16.0 -> 3.27.4)
- [x] Add Google Play Store publishing via `r0adkll/upload-google-play`
  - Publishes AAB to `internal` track on tag push
  - **Setup required**: add `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` repo secret
    1. Create a Google Cloud service account with Play Console API access
    2. Grant the service account "Release manager" permissions in Play Console
    3. Export the JSON key and add as a GitHub Actions secret
  - Package name: `net.netmindz.wled.sender`
- [ ] iOS build is still unsigned (no codesign) - needs Apple Developer setup to distribute
