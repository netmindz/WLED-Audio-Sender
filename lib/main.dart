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
import 'dart:core';
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
  List<int>? currentSamples = [];
  List<int> visibleSamples = [];
  int? localMax;
  int? localMin;
  InternetAddress multicastAddress = InternetAddress('239.0.0.1');
  int multicastPort = 11988; // WLED Audio Sync standard port

  Random rng = Random();
  
  // Audio processing state
  double sampleAverage = 0.0;
  double sampleSmoothed = 0.0;
  int peakDetected = 0;
  double smoothingFactor = 0.5;
  int frameCounter = 0;
  
  // Pre-calculated FFT bin boundaries for performance
  List<List<int>>? fftBinBoundaries;
  static const int fftBinCount = 16;

  // Refreshes the Widget for every possible tick to force a rebuild of the sound wave
  late AnimationController controller;

  final Color _iconColor = Colors.white;
  bool isRecording = false;
  bool memRecordingState = false;
  late bool isActive;
  DateTime? startTime;

  int page = 0;
  List state = ["SoundWavePage", "IntensityWavePage", "InformationPage"];

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

  late int bytesPerSample;
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
    bytesPerSample = (await MicStream.bitDepth)! ~/ 8;
    samplesPerSecond = (await MicStream.sampleRate)!.toInt();
    localMax = null;
    localMin = null;

    setState(() {
      isRecording = true;
      startTime = DateTime.now();
    });
    visibleSamples = [];
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
    if (page == 0) {
      _calculateWaveSamples(samples);
    } else if (page == 1) {
      _calculateIntensitySamples(samples);
    }
    
    // Convert samples to audio values for FFT processing
    List<double> audio = [];
    List<int> tmp = samples;
    
    // Convert int16 samples to normalized doubles (-1.0 to 1.0)
    for (int i = 0; i < tmp.length - 1; i += 2) {
      // Combine two bytes into int16
      int sample16 = tmp[i] | (tmp[i + 1] << 8);
      // Convert to signed int16
      if (sample16 > 32767) sample16 -= 65536;
      // Normalize to -1.0 to 1.0
      audio.add(sample16 / 32768.0);
    }
    
    if (audio.isEmpty) return;
    
    // Calculate raw sample (RMS of current buffer)
    double sumSquares = 0;
    for (var sample in audio) {
      sumSquares += sample * sample;
    }
    double rms = sqrt(sumSquares / audio.length);
    double sampleRaw = rms * 255.0; // Scale to 0-255 range
    
    // Apply exponential smoothing filter
    sampleSmoothed = sampleSmoothed * smoothingFactor + 
                     sampleRaw * (1.0 - smoothingFactor);
    
    // Simple peak detection - detect if current sample is significantly above average
    double threshold = sampleSmoothed * 1.5;
    peakDetected = (sampleRaw > threshold) ? 1 : 0;
    
    // Perform FFT - use power of 2 chunk size
    const int fftSize = 512;
    if (audio.length < fftSize) {
      // Pad with zeros if needed
      audio.addAll(List<double>.filled(fftSize - audio.length, 0.0));
    } else if (audio.length > fftSize) {
      // Truncate if too long
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
    
    int usableBins = magnitudes.length ~/ 2; // Only use first half (positive frequencies)
    
    // Calculate FFT bin boundaries once if not already done
    if (fftBinBoundaries == null || fftBinBoundaries!.isEmpty) {
      fftBinBoundaries = [];
      for (int i = 0; i < fftBinCount; i++) {
        // Use logarithmic spacing for better frequency distribution
        int startBin = (pow(2, i * usableBins / fftBinCount / 8) - 1).toInt();
        int endBin = (pow(2, (i + 1) * usableBins / fftBinCount / 8) - 1).toInt();
        startBin = startBin.clamp(0, usableBins - 1);
        endBin = endBin.clamp(startBin, usableBins - 1);
        fftBinBoundaries!.add([startBin, endBin]);
      }
    }
    
    // Extract 16 frequency bins using pre-calculated boundaries
    List<int> fftBins = [];
    for (var bounds in fftBinBoundaries!) {
      int startBin = bounds[0];
      int endBin = bounds[1];
      
      // Average magnitude in this bin range
      double sum = 0;
      int count = 0;
      for (int j = startBin; j <= endBin && j < magnitudes.length; j++) {
        sum += magnitudes[j];
        count++;
      }
      double avgMag = count > 0 ? sum / count : 0;
      
      // Scale to 0-255 range and clamp
      int binValue = (avgMag * 1000).toInt().clamp(0, 255);
      fftBins.add(binValue);
    }
    
    // Calculate overall FFT magnitude (average of all bins)
    double totalMagnitude = 0;
    if (magnitudes.isNotEmpty) {
      totalMagnitude = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    }
    
    // Find dominant frequency (major peak)
    int maxIndex = 0;
    double maxValue = 0;
    for (int i = 1; i < usableBins; i++) {
      if (magnitudes[i] > maxValue) {
        maxValue = magnitudes[i];
        maxIndex = i;
      }
    }
    
    // Convert bin index to frequency
    double majorPeakFreq = maxIndex * samplesPerSecond / fftSize;
    
    // Calculate zero-crossing count
    int zeroCrossings = 0;
    for (int i = 1; i < audio.length; i++) {
      if ((audio[i] >= 0 && audio[i - 1] < 0) || 
          (audio[i] < 0 && audio[i - 1] >= 0)) {
        zeroCrossings++;
      }
    }
    
    // Calculate sound pressure (fixed-point: integer.fraction)
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
      zeroCrossingCount: zeroCrossings,
      fftMagnitude: totalMagnitude * 100, // Scale appropriately
      fftMajorPeak: majorPeakFreq,
    );
    
    socket?.send(packet.asBytes(), multicastAddress, multicastPort);
  }

  void _calculateWaveSamples(samples) {
    bool first = true;
    visibleSamples = [];
    int tmp = 0;
    for (int sample in samples) {
      if (sample > 128) sample -= 255;
      if (first) {
        tmp = sample * 128;
      } else {
        tmp += sample;
        visibleSamples.add(tmp);

        localMax ??= visibleSamples.last;
        localMin ??= visibleSamples.last;
        localMax = max(localMax!, visibleSamples.last);
        localMin = min(localMin!, visibleSamples.last);

        tmp = 0;
      }
      first = !first;
    }
    // print(visibleSamples);
  }

  void _calculateIntensitySamples(samples) {
    currentSamples ??= [];
    int currentSample = 0;
    eachWithIndex(samples, (i, int sample) {
      currentSample += sample;
      if ((i % bytesPerSample) == bytesPerSample - 1) {
        currentSamples!.add(currentSample);
        currentSample = 0;
      }
    });

    if (currentSamples!.length >= samplesPerSecond / 10) {
      visibleSamples
          .add(currentSamples!.map((i) => i).toList().reduce((a, b) => a + b));
      localMax ??= visibleSamples.last;
      localMin ??= visibleSamples.last;
      localMax = max(localMax!, visibleSamples.last);
      localMin = min(localMin!, visibleSamples.last);
      currentSamples = [];
      setState(() {});
    }
  }

  bool _stopListening() {
    if (!isRecording) return false;
    listener.cancel();
    socket?.close();
    socket = null;

    setState(() {
      isRecording = false;
      currentSamples = null;
      startTime = null;
      fftBinBoundaries = null; // Reset for next session
    });
    return true;
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    if (!mounted) return;
    isActive = true;

    const Statistics(false);

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
                icon: Icon(Icons.broken_image),
                label: "Sound Wave",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.broken_image),
                label: "Intensity Wave",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.view_list),
                label: "Statistics",
              )
            ],
            backgroundColor: Colors.black26,
            elevation: 20,
            currentIndex: page,
            onTap: _controlPage,
          ),
          body: (page == 0 || page == 1)
              ? CustomPaint(
                  painter: WavePainter(
                    samples: visibleSamples,
                    color: _getBgColor(),
                    localMax: localMax,
                    localMin: localMin,
                    context: context,
                  ),
                )
              : Statistics(
                  isRecording,
                  startTime: startTime,
                )),
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

class WavePainter extends CustomPainter {
  int? localMax;
  int? localMin;
  List<int>? samples;
  late List<Offset> points;
  Color? color;
  BuildContext? context;
  Size? size;

  // Set max val possible in stream, depending on the config
  // int absMax = 255*4; //(AUDIO_FORMAT == AudioFormat.ENCODING_PCM_8BIT) ? 127 : 32767;
  // int absMin; //(AUDIO_FORMAT == AudioFormat.ENCODING_PCM_8BIT) ? 127 : 32767;

  WavePainter(
      {this.samples, this.color, this.context, this.localMax, this.localMin});

  @override
  void paint(Canvas canvas, Size? size) {
    this.size = context!.size;
    size = this.size;

    Paint paint = Paint()
      ..color = color!
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    if (samples!.isEmpty) return;

    points = toPoints(samples);

    Path path = Path();
    path.addPolygon(points, false);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldPainting) => true;

  // Maps a list of ints and their indices to a list of points on a cartesian grid
  List<Offset> toPoints(List<int>? samples) {
    List<Offset> points = [];
    samples ??= List<int>.filled(size!.width.toInt(), (0.5).toInt());
    double pixelsPerSample = size!.width / samples.length;
    for (int i = 0; i < samples.length; i++) {
      var point = Offset(
          i * pixelsPerSample,
          0.5 *
              size!.height *
              pow((samples[i] - localMin!) / (localMax! - localMin!), 5));
      points.add(point);
    }
    return points;
  }

  double project(int val, int max, double height) {
    double waveHeight =
        (max == 0) ? val.toDouble() : (val / max) * 0.5 * height;
    return waveHeight + 0.5 * height;
  }
}

class Statistics extends StatelessWidget {
  final bool isRecording;
  final DateTime? startTime;

  final String url = "https://github.com/anarchuser/mic_stream";

  const Statistics(this.isRecording, {super.key, this.startTime});

  @override
  Widget build(BuildContext context) {
    return ListView(children: <Widget>[
      const ListTile(
          leading: Icon(Icons.title),
          title: Text("Microphone Streaming Example App")),
      ListTile(
        leading: const Icon(Icons.keyboard_voice),
        title: Text((isRecording ? "Recording" : "Not recording")),
      ),
      ListTile(
          leading: const Icon(Icons.access_time),
          title: Text((isRecording
              ? DateTime.now().difference(startTime!).toString()
              : "Not recording"))),
    ]);
  }
}

Iterable<T> eachWithIndex<E, T>(
    Iterable<T> items, E Function(int index, T item) f) {
  var index = 0;

  for (final item in items) {
    f(index, item);
    index = index + 1;
  }

  return items;
}
