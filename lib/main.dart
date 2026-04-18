/// WLED Audio Sender - Flutter Application
/// 
/// This application captures audio from the device microphone, processes it,
/// and sends it as WLED Audio Sync v2 packets via UDP multicast.
/// 
/// Key features:
/// - Real-time audio capture from microphone
/// - FFT analysis with 16 frequency bins
/// - Peak detection and sample smoothing
/// - UDP multicast transmission to WLED devices (port 11988)
/// 
/// WLED Audio Sync v2 Packet Format (44 bytes total, little-endian):
/// - Header: "00002\0" (6 bytes)
/// - Pressure: uint8[2] - sound pressure (fixed-point int.frac)
/// - Sample Raw: float32 (4 bytes) - raw/AGC-adjusted sample
/// - Sample Smooth: float32 (4 bytes) - smoothed sample
/// - Sample Peak: uint8 (1 byte) - peak detection flag
/// - Frame Counter: uint8 (1 byte) - rolling sequence counter
/// - FFT Result: 16 x uint8 (16 bytes) - frequency bins
/// - Zero Crossing Count: uint16 (2 bytes) - zero crossings
/// - FFT Magnitude: float32 (4 bytes) - largest FFT result
/// - FFT Major Peak: float32 (4 bytes) - dominant frequency in Hz
/// 
/// References:
/// - https://mm.kno.wled.ge/soundreactive/sync/#v2-format-wled-version-0140-including-moonmodules-fork
/// - https://github.com/netmindz/WLED-MM/blob/mdev/usermods/audioreactive/audio_reactive.h
/// - https://github.com/netmindz/WLED-sync

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
import 'package:flutter/material.dart';

import 'package:mic_stream/mic_stream.dart';

enum Command {
  start,
  stop,
  change,
}

const audioFormat = AudioFormat.ENCODING_PCM_16BIT;

/// WLED Audio Sync v2 packet structure (44 bytes, packed)
/// 
/// Must match the audioSyncPacket struct in WLED's audio_reactive.h:
///   char    header[6];           // "00002\0"
///   uint8_t pressure[2];         // sound pressure (fixed-point: int.frac)
///   float   sampleRaw;           // raw or AGC-adjusted sample
///   float   sampleSmth;          // smoothed sample
///   uint8_t samplePeak;          // 0=no peak, >=1=peak
///   uint8_t frameCounter;        // rolling sequence counter
///   uint8_t fftResult[16];       // 16 GEQ frequency bins (0-255)
///   uint16_t zeroCrossingCount;  // zero crossings in ~23ms window
///   float   FFT_Magnitude;       // largest single FFT result
///   float   FFT_MajorPeak;       // frequency in Hz of largest FFT result
class AudioSyncPacket {
  static const List<int> header = [0x30, 0x30, 0x30, 0x30, 0x32, 0x00]; // "00002\0"
  List<int> pressure;             // 02 Bytes - sound pressure [int, frac]
  double sampleRaw;               // 04 Bytes - raw sample value
  double sampleSmth;              // 04 Bytes - smoothed sample value
  int samplePeak;                 // 01 Byte  - peak detection (0 or 1)
  int frameCounter;               // 01 Byte  - rolling sequence counter
  List<int> fftResult;            // 16 Bytes - 16 frequency bins (1 byte each)
  int zeroCrossingCount;          // 02 Bytes - zero crossing count (uint16)
  double fftMagnitude;            // 04 Bytes - FFT magnitude
  double fftMajorPeak;            // 04 Bytes - dominant frequency in Hz

  AudioSyncPacket({
    this.pressure = const [0, 0],
    required this.sampleRaw,
    required this.sampleSmth,
    required this.samplePeak,
    this.frameCounter = 0,
    required this.fftResult,
    this.zeroCrossingCount = 0,
    required this.fftMagnitude,
    required this.fftMajorPeak,
  });

  /// Convert packet to 44 bytes for UDP transmission (little-endian)
  List<int> asBytes() {
    final bytes = BytesBuilder();
    
    // Header (6 bytes): "00002\0"
    bytes.add(header);
    
    // pressure (2 bytes)
    bytes.addByte(pressure[0].clamp(0, 255));
    bytes.addByte(pressure[1].clamp(0, 255));
    
    // sampleRaw (4 bytes, float32 LE)
    final rawBytes = ByteData(4);
    rawBytes.setFloat32(0, sampleRaw, Endian.little);
    bytes.add(rawBytes.buffer.asUint8List());
    
    // sampleSmth (4 bytes, float32 LE)
    final smthBytes = ByteData(4);
    smthBytes.setFloat32(0, sampleSmth, Endian.little);
    bytes.add(smthBytes.buffer.asUint8List());
    
    // samplePeak (1 byte)
    bytes.addByte(samplePeak.clamp(0, 255));
    
    // frameCounter (1 byte)
    bytes.addByte(frameCounter & 0xFF);
    
    // fftResult (16 bytes)
    for (int i = 0; i < 16; i++) {
      bytes.addByte(i < fftResult.length ? fftResult[i].clamp(0, 255) : 0);
    }
    
    // zeroCrossingCount (2 bytes, uint16 LE)
    final zccBytes = ByteData(2);
    zccBytes.setUint16(0, zeroCrossingCount.clamp(0, 65535), Endian.little);
    bytes.add(zccBytes.buffer.asUint8List());
    
    // FFT_Magnitude (4 bytes, float32 LE)
    final magBytes = ByteData(4);
    magBytes.setFloat32(0, fftMagnitude, Endian.little);
    bytes.add(magBytes.buffer.asUint8List());
    
    // FFT_MajorPeak (4 bytes, float32 LE)
    final peakBytes = ByteData(4);
    peakBytes.setFloat32(0, fftMajorPeak, Endian.little);
    bytes.add(peakBytes.buffer.asUint8List());
    
    return bytes.toBytes();
  }
}


void main() => runApp(const WLEDAudioSenderApp());

class WLEDAudioSenderApp extends StatefulWidget {
  const WLEDAudioSenderApp({super.key});
  
  @override
  _WLEDAudioSenderAppState createState() => _WLEDAudioSenderAppState();
}

class _WLEDAudioSenderAppState extends State<WLEDAudioSenderApp>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Stream? stream;
  RawDatagramSocket? socket;
  late StreamSubscription listener;
  InternetAddress multicastAddress = InternetAddress('239.0.0.1');
  int multicastPort = 11988; // WLED Audio Sync standard port

  // Audio processing state
  double sampleRaw = 0.0;
  double sampleSmoothed = 0.0;
  int peakDetected = 0;
  double smoothingFactor = 0.5;
  int frameCounter = 0;
  List<int> fftBins = List<int>.filled(16, 0);
  double fftMagnitude = 0.0;
  double fftMajorPeak = 0.0;
  int zeroCrossingCount = 0;
  
  // Peak hold for VU meter (decays over time)
  double peakHold = 0.0;
  
  // Pre-calculated FFT bin boundaries for performance
  List<List<int>>? fftBinBoundaries;
  static const int fftBinCount = 16;

  // Refreshes the Widget for every possible tick to force a rebuild
  late AnimationController controller;

  final Color _iconColor = Colors.white;
  bool isRecording = false;
  bool memRecordingState = false;
  late bool isActive;
  DateTime? startTime;

  int page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setState(() {
      initPlatformState();
    });
  }

  void _controlPage(int index) => setState(() => page = index);

  // Responsible for switching between recording / idle state
  void _controlMicStream({Command command = Command.change}) async {
    switch (command) {
      case Command.change:
        _changeListening();
        break;
      case Command.start:
        _startListening();
        break;
      case Command.stop:
        _stopListening();
        break;
    }
  }

  Future<bool> _changeListening() async =>
      !isRecording ? await _startListening() : _stopListening();

  late int samplesPerSecond;

  Future<bool> _startListening() async {
    if (isRecording) return false;
    
    // Default option. Set to false to disable request permission dialogue
    MicStream.shouldRequestPermission(true);

    try {
      RawDatagramSocket s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket = s;
    } catch (e) {
      debugPrint('Failed to bind UDP socket: $e');
      return false;
    }

    try {
      stream = await MicStream.microphone(
          audioSource: AudioSource.DEFAULT,
          sampleRate: 44100, // Standard audio sample rate
          channelConfig: ChannelConfig.CHANNEL_IN_MONO,
          audioFormat: audioFormat);
    } catch (e) {
      debugPrint('Failed to access microphone: $e');
      socket?.close();
      socket = null;
      return false;
    }
    
    if (stream == null) {
      debugPrint('Microphone stream is null - permission may have been denied');
      socket?.close();
      socket = null;
      return false;
    }
    
    // Get actual sample rate and bit depth
    samplesPerSecond = (await MicStream.sampleRate)!.toInt();

    setState(() {
      isRecording = true;
      startTime = DateTime.now();
    });
    listener = stream!.listen(_calculateSamples);
    return true;
  }

  /// Process audio samples and send WLED packets
  /// 
  /// This method:
  /// 1. Converts raw PCM samples to normalized audio data
  /// 2. Calculates RMS (Root Mean Square) for audio level
  /// 3. Applies smoothing filter
  /// 4. Detects audio peaks
  /// 5. Performs FFT analysis with 512-point window
  /// 6. Extracts 16 frequency bins using logarithmic spacing
  /// 7. Finds dominant frequency (major peak)
  /// 8. Sends WLED Audio Sync v2 packet via UDP multicast
  void _calculateSamples(samples) {
    // Convert samples to audio values for FFT processing
    List<double> audio = [];
    List<int> tmp = samples;
    
    // Convert int16 samples to normalized doubles (-1.0 to 1.0)
    for (int i = 0; i < tmp.length - 1; i += 2) {
      int sample16 = tmp[i] | (tmp[i + 1] << 8);
      if (sample16 > 32767) sample16 -= 65536;
      audio.add(sample16 / 32768.0);
    }
    
    if (audio.isEmpty) return;
    
    // Calculate raw sample (RMS of current buffer)
    double sumSquares = 0;
    for (var sample in audio) {
      sumSquares += sample * sample;
    }
    double rms = sqrt(sumSquares / audio.length);
    sampleRaw = rms * 255.0; // Scale to 0-255 range
    
    // Apply exponential smoothing filter
    sampleSmoothed = sampleSmoothed * smoothingFactor + 
                     sampleRaw * (1.0 - smoothingFactor);
    
    // Update peak hold (decay towards smoothed value)
    if (sampleRaw > peakHold) {
      peakHold = sampleRaw;
    } else {
      peakHold = peakHold * 0.95; // Slow decay
    }
    
    // Simple peak detection
    double threshold = sampleSmoothed * 1.5;
    peakDetected = (sampleRaw > threshold) ? 1 : 0;
    
    // Perform FFT - use power of 2 chunk size
    const int fftSize = 512;
    if (audio.length < fftSize) {
      audio.addAll(List<double>.filled(fftSize - audio.length, 0.0));
    } else if (audio.length > fftSize) {
      audio = audio.sublist(0, fftSize);
    }
    
    // Apply Hanning window
    final window = Window.hanning(fftSize);
    for (int i = 0; i < fftSize; i++) {
      audio[i] *= window[i];
    }
    
    // Perform FFT
    final fft = FFT(fftSize);
    final freq = fft.realFft(audio);
    final magnitudes = freq.discardConjugates().magnitudes();
    
    int usableBins = magnitudes.length ~/ 2;
    
    // Calculate FFT bin boundaries once
    if (fftBinBoundaries == null || fftBinBoundaries!.isEmpty) {
      fftBinBoundaries = [];
      for (int i = 0; i < fftBinCount; i++) {
        int startBin = (pow(2, i * usableBins / fftBinCount / 8) - 1).toInt();
        int endBin = (pow(2, (i + 1) * usableBins / fftBinCount / 8) - 1).toInt();
        startBin = startBin.clamp(0, usableBins - 1);
        endBin = endBin.clamp(startBin, usableBins - 1);
        fftBinBoundaries!.add([startBin, endBin]);
      }
    }
    
    // Extract 16 frequency bins
    fftBins = [];
    for (var bounds in fftBinBoundaries!) {
      int startBin = bounds[0];
      int endBin = bounds[1];
      double sum = 0;
      int count = 0;
      for (int j = startBin; j <= endBin && j < magnitudes.length; j++) {
        sum += magnitudes[j];
        count++;
      }
      double avgMag = count > 0 ? sum / count : 0;
      fftBins.add((avgMag * 1000).toInt().clamp(0, 255));
    }
    
    // Calculate overall FFT magnitude
    double totalMagnitude = 0;
    if (magnitudes.isNotEmpty) {
      totalMagnitude = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    }
    fftMagnitude = totalMagnitude * 100;
    
    // Find dominant frequency
    int maxIndex = 0;
    double maxValue = 0;
    for (int i = 1; i < usableBins; i++) {
      if (magnitudes[i] > maxValue) {
        maxValue = magnitudes[i];
        maxIndex = i;
      }
    }
    fftMajorPeak = maxIndex * samplesPerSecond / fftSize;
    
    // Calculate zero-crossing count
    zeroCrossingCount = 0;
    for (int i = 1; i < audio.length; i++) {
      if ((audio[i] >= 0 && audio[i - 1] < 0) || 
          (audio[i] < 0 && audio[i - 1] >= 0)) {
        zeroCrossingCount++;
      }
    }
    
    // Calculate sound pressure (fixed-point)
    int pressureInt = sampleRaw.toInt().clamp(0, 255);
    int pressureFrac = ((sampleRaw - pressureInt) * 256).toInt().clamp(0, 255);
    
    // Create and send WLED packet
    frameCounter = (frameCounter + 1) & 0xFF;
    
    AudioSyncPacket packet = AudioSyncPacket(
      pressure: [pressureInt, pressureFrac],
      sampleRaw: sampleRaw,
      sampleSmth: sampleSmoothed,
      samplePeak: peakDetected,
      frameCounter: frameCounter,
      fftResult: fftBins,
      zeroCrossingCount: zeroCrossingCount,
      fftMagnitude: fftMagnitude,
      fftMajorPeak: fftMajorPeak,
    );
    
    socket?.send(packet.asBytes(), multicastAddress, multicastPort);
  }

  bool _stopListening() {
    if (!isRecording) return false;
    listener.cancel();
    socket?.close();
    socket = null;

    setState(() {
      isRecording = false;
      startTime = null;
      fftBinBoundaries = null;
      sampleRaw = 0.0;
      sampleSmoothed = 0.0;
      peakDetected = 0;
      peakHold = 0.0;
      fftBins = List<int>.filled(16, 0);
      fftMagnitude = 0.0;
      fftMajorPeak = 0.0;
      zeroCrossingCount = 0;
    });
    return true;
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    if (!mounted) return;
    isActive = true;

    controller =
        AnimationController(duration: const Duration(seconds: 1), vsync: this)
          ..addListener(() {
            if (isRecording) setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              controller.reverse();
            } else if (status == AnimationStatus.dismissed) {
              controller.forward();
            }
          })
          ..forward();
  }

  Color _getBgColor() => (isRecording) ? Colors.red : Colors.cyan;

  Icon _getIcon() =>
      (isRecording) ? const Icon(Icons.stop) : const Icon(Icons.keyboard_voice);

  Widget _buildBody() {
    switch (page) {
      case 0:
        return Column(
          children: [
            // VU Meter
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: VUMeterPainter(
                    sampleRaw: sampleRaw,
                    sampleSmth: sampleSmoothed,
                    peakHold: peakHold,
                    peakDetected: peakDetected == 1,
                  ),
                ),
              ),
            ),
            // Spectrum Analyser
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: SpectrumPainter(
                    fftBins: fftBins,
                    majorPeak: fftMajorPeak,
                  ),
                ),
              ),
            ),
          ],
        );
      case 1:
      default:
        return Statistics(
          isRecording,
          startTime: startTime,
          sampleRaw: sampleRaw,
          sampleSmth: sampleSmoothed,
          peakDetected: peakDetected,
          frameCounter: frameCounter,
          fftMagnitude: fftMagnitude,
          fftMajorPeak: fftMajorPeak,
          zeroCrossingCount: zeroCrossingCount,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
          appBar: AppBar(
            title: const Text('WLED Audio Sender'),
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: _getBgColor(),
            foregroundColor: _iconColor,
            tooltip: (isRecording) ? "Stop recording" : "Start recording",
            onPressed: _controlMicStream,
            child: _getIcon(),
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.equalizer),
                label: "Analyser",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.info_outline),
                label: "Details",
              ),
            ],
            backgroundColor: Colors.black26,
            elevation: 20,
            currentIndex: page,
            onTap: _controlPage,
          ),
          body: _buildBody()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      isActive = true;

      _controlMicStream(
          command: memRecordingState ? Command.start : Command.stop);
    } else if (isActive) {
      memRecordingState = isRecording;
      _controlMicStream(command: Command.stop);

      isActive = false;
    }
  }

  @override
  void dispose() {
    listener.cancel();
    controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// VU Meter - shows sampleRaw as bar, sampleSmth as line, peakHold as marker
class VUMeterPainter extends CustomPainter {
  final double sampleRaw;
  final double sampleSmth;
  final double peakHold;
  final bool peakDetected;

  VUMeterPainter({
    required this.sampleRaw,
    required this.sampleSmth,
    required this.peakHold,
    required this.peakDetected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double maxVal = 255.0;
    final double barHeight = size.height - 40; // Leave room for labels
    final double barTop = 10;
    
    // Background
    final bgPaint = Paint()..color = Colors.grey.shade900;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, barTop, size.width, barHeight),
        const Radius.circular(4),
      ),
      bgPaint,
    );
    
    // Gradient colour segments for the VU bar
    double rawFraction = (sampleRaw / maxVal).clamp(0.0, 1.0);
    double barWidth = size.width * rawFraction;
    
    // Draw the level bar with green->yellow->red gradient
    if (barWidth > 0) {
      final gradient = LinearGradient(
        colors: [
          Colors.green,
          Colors.green,
          Colors.yellow,
          Colors.red,
        ],
        stops: const [0.0, 0.5, 0.75, 1.0],
      );
      final barRect = Rect.fromLTWH(0, barTop, barWidth, barHeight);
      final gradientPaint = Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(0, barTop, size.width, barHeight),
        );
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(4)),
        gradientPaint,
      );
    }
    
    // Smoothed level line (white vertical line)
    double smthX = (sampleSmth / maxVal).clamp(0.0, 1.0) * size.width;
    final smthPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(smthX, barTop),
      Offset(smthX, barTop + barHeight),
      smthPaint,
    );
    
    // Peak hold marker (thin bright line)
    double peakX = (peakHold / maxVal).clamp(0.0, 1.0) * size.width;
    final peakPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(peakX, barTop),
      Offset(peakX, barTop + barHeight),
      peakPaint,
    );
    
    // Peak detected indicator
    if (peakDetected) {
      final dotPaint = Paint()..color = Colors.red;
      canvas.drawCircle(
        Offset(size.width - 12, barTop + 12),
        8,
        dotPaint,
      );
    }
    
    // Labels
    final textStyle = TextStyle(color: Colors.grey.shade400, fontSize: 11);
    _drawText(canvas, 'Raw: ${sampleRaw.toStringAsFixed(1)}', 
              Offset(4, barTop + barHeight + 4), textStyle);
    _drawText(canvas, 'Smooth: ${sampleSmth.toStringAsFixed(1)}',
              Offset(size.width * 0.35, barTop + barHeight + 4), textStyle);
    _drawText(canvas, 'Peak: ${peakHold.toStringAsFixed(1)}',
              Offset(size.width * 0.7, barTop + barHeight + 4), textStyle);
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(VUMeterPainter old) => true;
}

/// Spectrum Analyser - 16 frequency bins as bars with major peak label
class SpectrumPainter extends CustomPainter {
  final List<int> fftBins;
  final double majorPeak;

  // Approximate frequency labels for the 16 bins
  static const List<String> binLabels = [
    '63', '88', '125', '175', '250', '350', '500', '700',
    '1k', '1.4k', '2k', '2.8k', '4k', '5.6k', '8k', '11k',
  ];

  SpectrumPainter({required this.fftBins, required this.majorPeak});

  @override
  void paint(Canvas canvas, Size size) {
    if (fftBins.isEmpty) return;
    
    final int binCount = fftBins.length;
    final double spacing = 3;
    final double labelHeight = 36; // Room for freq labels + peak text
    final double barAreaHeight = size.height - labelHeight;
    final double barWidth = (size.width - (binCount - 1) * spacing) / binCount;
    
    // Background
    final bgPaint = Paint()..color = Colors.grey.shade900;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, barAreaHeight),
        const Radius.circular(4),
      ),
      bgPaint,
    );
    
    // Draw grid lines at 25%, 50%, 75%
    final gridPaint = Paint()
      ..color = Colors.grey.shade800
      ..strokeWidth = 0.5;
    for (double frac in [0.25, 0.5, 0.75]) {
      double y = barAreaHeight * (1.0 - frac);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    
    // Colour gradient for bars (low freq = warm, high freq = cool)
    final List<Color> barColors = List.generate(binCount, (i) {
      double t = i / (binCount - 1);
      return HSLColor.fromAHSL(1.0, 120 + t * 180, 0.8, 0.5).toColor();
    });
    
    for (int i = 0; i < binCount; i++) {
      double fraction = fftBins[i] / 255.0;
      double barHeight = fraction * barAreaHeight;
      double x = i * (barWidth + spacing);
      double y = barAreaHeight - barHeight;
      
      final barPaint = Paint()..color = barColors[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        barPaint,
      );
      
      // Frequency label below each bar
      if (i < binLabels.length) {
        final labelStyle = TextStyle(
          color: Colors.grey.shade500, 
          fontSize: 8,
        );
        final tp = TextPainter(
          text: TextSpan(text: binLabels[i], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + (barWidth - tp.width) / 2, barAreaHeight + 2));
      }
    }
    
    // Major peak frequency text
    final peakStyle = TextStyle(color: Colors.cyan.shade300, fontSize: 12);
    final peakTp = TextPainter(
      text: TextSpan(
        text: 'Peak: ${majorPeak.toStringAsFixed(0)} Hz',
        style: peakStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    peakTp.paint(canvas, Offset(
      (size.width - peakTp.width) / 2,
      barAreaHeight + 18,
    ));
  }

  @override
  bool shouldRepaint(SpectrumPainter old) => true;
}

/// Statistics / Details page showing all packet field values
class Statistics extends StatelessWidget {
  final bool isRecording;
  final DateTime? startTime;
  final double sampleRaw;
  final double sampleSmth;
  final int peakDetected;
  final int frameCounter;
  final double fftMagnitude;
  final double fftMajorPeak;
  final int zeroCrossingCount;

  const Statistics(
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
