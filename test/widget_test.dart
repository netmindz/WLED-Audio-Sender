import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wled_audio_sender/main.dart';
import 'package:wled_audio_sender/models/audio_sync_packet.dart';

void main() {
  testWidgets('App renders with title and mic button', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    // Verify app title is shown
    expect(find.text('WLED Audio Sender'), findsOneWidget);

    // Verify mic button is present (voice icon when not recording)
    expect(find.byIcon(Icons.keyboard_voice), findsOneWidget);

    // Verify bottom navigation tabs exist
    expect(find.text('Analyser'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);

    // Verify settings button is present
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  test('AudioSyncPacket produces exactly 44 bytes', () {
    final packet = AudioSyncPacket(
      pressure: [10, 128],
      sampleRaw: 42.5,
      sampleSmth: 40.0,
      samplePeak: 1,
      frameCounter: 7,
      fftResult: List<int>.filled(16, 100),
      zeroCrossingCount: 50,
      fftMagnitude: 1234.5,
      fftMajorPeak: 440.0,
    );

    final bytes = packet.asBytes();
    expect(bytes.length, 44);

    // Verify header is "00002\0"
    expect(bytes.sublist(0, 6), [0x30, 0x30, 0x30, 0x30, 0x32, 0x00]);

    // Verify pressure bytes
    expect(bytes[6], 10);
    expect(bytes[7], 128);

    // Verify samplePeak at offset 16
    expect(bytes[16], 1);

    // Verify frameCounter at offset 17
    expect(bytes[17], 7);

    // Verify fftResult (16 bytes at offset 18-33)
    for (int i = 18; i < 34; i++) {
      expect(bytes[i], 100);
    }

    // Verify zeroCrossingCount at offset 34-35 (uint16 LE = 50)
    final zcc = ByteData.sublistView(Uint8List.fromList(bytes.sublist(34, 36)));
    expect(zcc.getUint16(0, Endian.little), 50);
  });
}
