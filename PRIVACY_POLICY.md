# Privacy Policy for WLED Audio Sender

**Last Updated: December 7, 2024**

## Introduction

WLED Audio Sender ("we", "our", or "the app") is committed to protecting your privacy. This Privacy Policy explains how we handle information when you use our application.

## Information We Collect

### Microphone Audio Data

WLED Audio Sender requires access to your device's microphone to capture audio for the sole purpose of processing and transmitting audio synchronization data to WLED devices on your local network.

**Important:** 
- Audio data is processed **locally on your device only**
- Audio is **never recorded, stored, or saved** to disk
- Audio is **never transmitted over the internet**
- Audio is **never shared with third parties**
- Audio data is only sent to WLED devices on your local network via UDP multicast (port 11988, address 239.0.0.1)

### What We Don't Collect

We do **NOT** collect, store, or transmit:
- Personal information
- User accounts or credentials
- Location data
- Device identifiers
- Analytics or usage statistics
- Crash reports
- Any form of tracking data

## How Audio Data Is Used

The microphone permission is used exclusively to:

1. **Capture audio in real-time** from your device microphone
2. **Process audio locally** using FFT (Fast Fourier Transform) analysis to extract:
   - Audio levels (RMS values)
   - Frequency data for visualization
   - Beat/peak detection
3. **Transmit processed data** to WLED devices on your local network using the WLED Audio Sync v2 protocol

The app sends only numerical audio analysis data (52-byte UDP packets containing frequency bins, audio levels, and peak information) to WLED devices. **Raw audio is never transmitted.**

## Data Storage

WLED Audio Sender does **NOT** store any data:
- No audio recordings are saved
- No configuration data is stored
- No user preferences are saved
- No logs or analytics are collected

All audio processing happens in memory and is immediately discarded after transmission to WLED devices.

## Third-Party Services

This app does **NOT** use any third-party services, including:
- Analytics services
- Advertising networks
- Cloud storage
- Social media integration
- Crash reporting services

## Network Communication

The app communicates only with WLED devices on your **local network** via:
- **Protocol**: UDP multicast
- **Port**: 11988
- **Address**: 239.0.0.1
- **Data**: Numerical audio analysis data only (frequency bins, levels, peaks)

**No internet connection is required or used** for the app's core functionality.

## Permissions

### Required Permissions

- **Microphone (RECORD_AUDIO)**: Required to capture audio for processing and sending to WLED devices

### Why We Need This Permission

The microphone permission is essential for the app's core functionality: capturing live audio to synchronize WLED light effects with music or sound. Without this permission, the app cannot function.

## Children's Privacy

WLED Audio Sender does not knowingly collect any information from children under the age of 13. The app does not collect personal information from anyone.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Any changes will be reflected by updating the "Last Updated" date at the top of this policy. We encourage you to review this Privacy Policy periodically.

## Data Security

Since no data is collected, stored, or transmitted to external servers, there is no risk of data breaches related to personal information. Audio data is processed locally and discarded immediately after use.

## Your Rights

Since we do not collect or store any personal data, there is no data to access, modify, or delete. You maintain complete control over the app by:
- Denying microphone permission (the app will not function without it)
- Uninstalling the app (which removes all app data from your device)

## Open Source

WLED Audio Sender is open source software. You can review the source code to verify our privacy practices at:
https://github.com/netmindz/WLED-Audio-Sender

## Contact Information

If you have questions or concerns about this Privacy Policy, please contact us through the GitHub repository:
https://github.com/netmindz/WLED-Audio-Sender/issues

## Compliance

This app complies with:
- Google Play Store policies for apps using sensitive permissions
- General Data Protection Regulation (GDPR) principles
- California Consumer Privacy Act (CCPA) principles

By using WLED Audio Sender, you agree to this Privacy Policy.
