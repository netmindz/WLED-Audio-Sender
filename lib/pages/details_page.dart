import 'package:flutter/material.dart';

/// Statistics / Details page showing all packet field values
class DetailsPage extends StatelessWidget {
  final bool isRecording;
  final DateTime? startTime;
  final double sampleRaw;
  final double sampleSmth;
  final int peakDetected;
  final int frameCounter;
  final double fftMagnitude;
  final double fftMajorPeak;
  final int zeroCrossingCount;

  const DetailsPage(
    this.isRecording, {
    super.key,
    this.startTime,
    this.sampleRaw = 0,
    this.sampleSmth = 0,
    this.peakDetected = 0,
    this.frameCounter = 0,
    this.fftMagnitude = 0,
    this.fftMajorPeak = 0,
    this.zeroCrossingCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(children: <Widget>[
      ListTile(
        leading: const Icon(Icons.keyboard_voice),
        title: Text(isRecording ? "Recording" : "Not recording"),
        subtitle: isRecording && startTime != null
            ? Text('Duration: ${DateTime.now().difference(startTime!).toString().split('.').first}')
            : null,
      ),
      const Divider(),
      const ListTile(
        title: Text('Audio Sync Packet Data',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      _tile(Icons.volume_up, 'Sample Raw', sampleRaw.toStringAsFixed(2)),
      _tile(Icons.trending_flat, 'Sample Smooth', sampleSmth.toStringAsFixed(2)),
      _tile(Icons.flash_on, 'Peak Detected', peakDetected == 1 ? 'Yes' : 'No'),
      _tile(Icons.countertops, 'Frame Counter', '$frameCounter'),
      _tile(Icons.show_chart, 'FFT Magnitude', fftMagnitude.toStringAsFixed(2)),
      _tile(Icons.music_note, 'Major Peak', '${fftMajorPeak.toStringAsFixed(1)} Hz'),
      _tile(Icons.swap_horiz, 'Zero Crossings', '$zeroCrossingCount'),
    ]);
  }

  Widget _tile(IconData icon, String title, String value) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title),
      trailing: Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
      dense: true,
    );
  }
}
