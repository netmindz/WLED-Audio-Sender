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

// WLED Audio Sync v2 packet structure
// Total size: 52 bytes
class AudioSyncPacket {
  String header = "00002";      // 06 Bytes - header identifier
  double sampleRaw;             // 04 Bytes - raw sample value
  double sampleSmth;            // 04 Bytes - smoothed sample value
  int samplePeak;               // 01 Byte  - peak detection (0 or 1)
  int reserved1 = 0;            // 01 Byte  - reserved for future use
  List<int> fftResult;          // 16 Bytes - 16 frequency bins (1 byte each)
  double fftMagnitude;          // 04 Bytes - FFT magnitude
  double fftMajorPeak;          // 04 Bytes - dominant frequency in Hz

  AudioSyncPacket({
    required this.sampleRaw,
    required this.sampleSmth,
    required this.samplePeak,
    required this.fftResult,
    required this.fftMagnitude,
    required this.fftMajorPeak,
  });

  // Convert packet to bytes for UDP transmission
  List<int> asBytes() {
    final bytes = BytesBuilder();
    
    // Header (6 bytes)
    bytes.add(header.codeUnits);
    
    // sampleRaw (4 bytes, float32)
    final rawBytes = ByteData(4);
    rawBytes.setFloat32(0, sampleRaw, Endian.little);
    bytes.add(rawBytes.buffer.asUint8List());
    
    // sampleSmth (4 bytes, float32)
    final smthBytes = ByteData(4);
    smthBytes.setFloat32(0, sampleSmth, Endian.little);
    bytes.add(smthBytes.buffer.asUint8List());
    
    // samplePeak (1 byte)
    bytes.addByte(samplePeak);
    
    // reserved1 (1 byte)
    bytes.addByte(reserved1);
    
    // fftResult (16 bytes - 16 frequency bins)
    for (int i = 0; i < 16; i++) {
      bytes.addByte(i < fftResult.length ? fftResult[i] : 0);
    }
    
    // fftMagnitude (4 bytes, float32)
    final magBytes = ByteData(4);
    magBytes.setFloat32(0, fftMagnitude, Endian.little);
    bytes.add(magBytes.buffer.asUint8List());
    
    // fftMajorPeak (4 bytes, float32)
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

    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
        .then((RawDatagramSocket s) {
      socket = s;
    });

    stream = await MicStream.microphone(
        audioSource: AudioSource.DEFAULT,
        sampleRate: 44100, // Standard audio sample rate
        channelConfig: ChannelConfig.CHANNEL_IN_MONO,
        audioFormat: audioFormat);
    
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
    
    // Apply smoothing
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
    
    // Extract 16 frequency bins by grouping FFT results
    // WLED typically uses logarithmic spacing for better musical representation
    List<int> fftBins = [];
    int binCount = 16;
    int usableBins = magnitudes.length ~/ 2; // Only use first half (positive frequencies)
    
    for (int i = 0; i < binCount; i++) {
      // Use logarithmic spacing for better frequency distribution
      int startBin = (pow(2, i * usableBins / binCount / 8) - 1).toInt();
      int endBin = (pow(2, (i + 1) * usableBins / binCount / 8) - 1).toInt();
      startBin = startBin.clamp(0, usableBins - 1);
      endBin = endBin.clamp(startBin, usableBins - 1);
      
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
    double totalMagnitude = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    
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
    // Assuming sample rate from mic_stream
    double majorPeakFreq = maxIndex * samplesPerSecond / fftSize;
    
    // Create and send WLED packet
    AudioSyncPacket packet = AudioSyncPacket(
      sampleRaw: sampleRaw,
      sampleSmth: sampleSmoothed,
      samplePeak: peakDetected,
      fftResult: fftBins,
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

    setState(() {
      isRecording = false;
      currentSamples = null;
      startTime = null;
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
