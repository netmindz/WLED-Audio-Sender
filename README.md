# WLED Audio Sender

A Flutter/Dart application that captures audio from the device microphone, processes it in real-time, and sends it to WLED devices using the WLED Audio Sync v2 protocol.

## Features

- **Real-time Audio Capture**: Captures audio from the device microphone using PCM 16-bit format at 44.1kHz
- **Audio Processing**:
  - RMS (Root Mean Square) calculation for audio levels
  - Exponential smoothing filter for stable readings
  - Peak detection for beat tracking
- **FFT Analysis**: 
  - 512-point FFT with Hanning window
  - 16 frequency bins using logarithmic spacing for musical representation
  - Dominant frequency detection
- **WLED Integration**:
  - Sends Audio Sync v2 packets (52 bytes) via UDP multicast
  - Standard WLED port 11988
  - Multicast address: 239.0.0.1
- **Visualization**:
  - Real-time waveform display
  - Intensity wave visualization
  - Recording statistics

## WLED Audio Sync v2 Packet Format

The app sends 52-byte packets with the following structure:

| Field | Size | Type | Description |
|-------|------|------|-------------|
| Header | 6 bytes | String | "00002" - Protocol version identifier |
| Sample Raw | 4 bytes | float32 | Current audio level (0-255) |
| Sample Smooth | 4 bytes | float32 | Smoothed audio level |
| Sample Peak | 1 byte | uint8 | Peak detection flag (0 or 1) |
| Reserved | 1 byte | uint8 | Reserved for future use |
| FFT Result | 16 bytes | 16x uint8 | Frequency bins (0-255 each) |
| FFT Magnitude | 4 bytes | float32 | Overall FFT magnitude |
| FFT Major Peak | 4 bytes | float32 | Dominant frequency in Hz |

## Usage

### Mobile & Desktop

1. Install Flutter SDK (version 3.16.0 or higher)
2. Clone this repository
3. Run `flutter pub get` to install dependencies
4. Connect your Android/iOS device or start an emulator
5. Run `flutter run` to start the app
6. Tap the microphone button to start/stop audio capture
7. Audio will be sent to WLED devices on your network

### Web Browser

**Building for Web:**
```bash
flutter build web --release
```

The built web app will be in `build/web/` directory. You can serve this directory using any web server.

**Quick Test with Flutter:**
```bash
flutter run -d chrome
```

**Web Platform Limitations:**
- ⚠️ Web browsers cannot send UDP multicast packets directly due to security restrictions
- Audio capture and visualization work normally
- UDP packets are not sent by default in web browsers
- For actual UDP transmission from web, you would need to set up a WebSocket relay server

**Note:** When running in a web browser, make sure to grant microphone permissions when prompted.

## Dependencies

- `mic_stream`: Audio capture from microphone
- `fftea`: FFT (Fast Fourier Transform) implementation
- `flutter`: UI framework

## References

- [WLED Audio Sync Documentation](https://mm.kno.wled.ge/soundreactive/sync/#v2-format-wled-version-0140-including-moonmodules-fork)
- [WLED-MM Audio Reactive](https://github.com/netmindz/WLED-MM/blob/mdev/usermods/audioreactive/audio_reactive.h)
- [WLED-sync](https://github.com/netmindz/WLED-sync)
- [SR-WLED-audio-server-win](https://github.com/Victoare/SR-WLED-audio-server-win)

## Platform Support

Currently tested on:
- Android
- iOS
- macOS
- Web (Chrome, Firefox, Safari, Edge)

## License

This project follows the same license as the WLED project.
