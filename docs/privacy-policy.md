---
layout: default
title: Privacy Policy
---

# Privacy Policy

**WLED Audio Sender**

*Last updated: April 18, 2026*

## Overview

WLED Audio Sender is an open-source application that captures audio from your device's microphone and sends it over your local network to WLED-compatible LED controllers for real-time audio-reactive lighting effects.

## Data Collection

**We do not collect, store, or transmit any personal data.**

### Microphone Access

The app requires microphone access solely to:

- Capture audio in real-time for frequency analysis (FFT)
- Calculate volume levels and spectral data
- Transmit this data as UDP packets to WLED devices on your local network

Audio data is processed entirely on your device and is **never recorded, stored, or sent to any external server**. Audio samples exist only momentarily in memory during real-time processing.

### Network Activity

The app sends UDP multicast packets exclusively to your local network (default address `239.0.0.1:11988`). These packets contain only audio analysis data (volume levels, frequency bins) — **no raw audio is transmitted**.

No data is sent to the internet.

### Analytics and Tracking

The app does **not** include any analytics, telemetry, crash reporting, or tracking of any kind.

## Third-Party Services

The app does not use any third-party services that collect user data.

## Data Storage

The app stores only your preferences (multicast address, port, and gain control settings) locally on your device using the standard platform preferences API. No data is stored externally.

## Children's Privacy

The app does not collect any data from anyone, including children.

## Changes to This Policy

Any changes to this privacy policy will be posted on this page with an updated date.

## Contact

If you have questions about this privacy policy, please open an issue on the [GitHub repository](https://github.com/netmindz/WLED-Audio-Sender).

## Open Source

This app is open source. You can review the complete source code at [github.com/netmindz/WLED-Audio-Sender](https://github.com/netmindz/WLED-Audio-Sender).
