/// WLED Audio Sender - Flutter Application
///
/// Captures audio from the device microphone, processes it in real-time,
/// and sends WLED Audio Sync v2 packets via UDP multicast.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:fftea/fftea.dart';
import 'package:flutter/material.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/audio_sync_packet.dart';
import 'models/agc.dart';
import 'painters/vu_meter_painter.dart';
import 'painters/spectrum_painter.dart';
import 'pages/details_page.dart';

enum Command { start, stop, change }

const audioFormat = AudioFormat.ENCODING_PCM_16BIT;

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
  StreamSubscription? listener;
  
  // Settings (persisted)
  String multicastAddressStr = '239.0.0.1';
  int multicastPort = 11988;
  bool agcEnabled = true;
  int agcPresetIndex = 0; // 0=normal, 1=vivid, 2=lazy
  InternetAddress get multicastAddress => InternetAddress(multicastAddressStr);

  // AGC
  final AutomaticGainControl _agc = AutomaticGainControl();

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

  // Peak hold for VU meter
  double peakHold = 0.0;

  static const int fftBinCount = 16;

  AnimationController? controller;

  final Color _iconColor = Colors.white;
  bool isRecording = false;
  bool memRecordingState = false;
  bool isActive = false;
  DateTime? startTime;

  int page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    setState(() {
      initPlatformState();
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      multicastAddressStr = prefs.getString('multicastAddress') ?? '239.0.0.1';
      multicastPort = prefs.getInt('multicastPort') ?? 11988;
      agcEnabled = prefs.getBool('agcEnabled') ?? true;
      agcPresetIndex = prefs.getInt('agcPreset') ?? 0;
      _agc.enabled = agcEnabled;
      _agc.preset = AgcPreset.values[agcPresetIndex.clamp(0, 2)];
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('multicastAddress', multicastAddressStr);
    await prefs.setInt('multicastPort', multicastPort);
    await prefs.setBool('agcEnabled', agcEnabled);
    await prefs.setInt('agcPreset', agcPresetIndex);
  }

  void _controlPage(int index) => setState(() => page = index);

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
          sampleRate: 44100,
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

    samplesPerSecond = (await MicStream.sampleRate)!.toInt();

    setState(() {
      isRecording = true;
      startTime = DateTime.now();
    });
    listener = stream!.listen(_calculateSamples);
    return true;
  }

  void _calculateSamples(samples) {
    List<double> audio = [];
    List<int> tmp = samples;

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
    double rawLevel = rms * 255.0; // Scale to 0-255 range

    // Apply AGC if enabled
    sampleRaw = _agc.process(rawLevel);

    // Apply exponential smoothing filter
    sampleSmoothed = sampleSmoothed * smoothingFactor +
        sampleRaw * (1.0 - smoothingFactor);

    if (sampleRaw > peakHold) {
      peakHold = sampleRaw;
    } else {
      peakHold = peakHold * 0.95;
    }

    double threshold = sampleSmoothed * 1.5;
    peakDetected = (sampleRaw > threshold) ? 1 : 0;

    const int fftSize = 512;
    if (audio.length < fftSize) {
      audio.addAll(List<double>.filled(fftSize - audio.length, 0.0));
    } else if (audio.length > fftSize) {
      audio = audio.sublist(0, fftSize);
    }

    final window = Window.hanning(fftSize);
    for (int i = 0; i < fftSize; i++) {
      audio[i] *= window[i];
    }

    final fft = FFT(fftSize);
    final freq = fft.realFft(audio);
    final magnitudes = freq.discardConjugates().magnitudes();

    int usableBins = magnitudes.length;

    // WLED GEQ bin mapping - ported from audio_reactive.h (512 samples, 22050Hz)
    // At 44100Hz with 512-point FFT, bin indices are doubled vs WLED's 22050Hz.
    // WLED bin N at 22050Hz = our bin N*2 at 44100Hz (same frequency).
    // Using WLED's 512-sample mapping (lines 876-921 of audio_reactive.h):
    //   Channel:  WLED bins (22050Hz)  -> our bins (44100Hz)  -> frequency range
    //   0:  1-1    ->  2-2      43-86 Hz    sub-bass
    //   1:  2-2    ->  4-4      86-129 Hz   bass
    //   2:  3-4    ->  6-8      129-216 Hz  bass
    //   3:  5-6    ->  10-12    216-301 Hz  bass+mid
    //   4:  7-9    ->  14-18    301-430 Hz  midrange
    //   5:  10-12  ->  20-24    430-560 Hz  midrange
    //   6:  13-18  ->  26-36    560-818 Hz  midrange
    //   7:  19-25  ->  38-50    818-1120 Hz midrange
    //   8:  26-32  ->  52-64    1120-1421 Hz midrange
    //   9:  33-43  ->  66-86    1421-1895 Hz midrange
    //  10:  44-55  ->  88-110   1895-2412 Hz mid+high
    //  11:  56-69  ->  112-138  2412-3015 Hz high mid
    //  12:  70-85  ->  140-170  3015-3704 Hz high mid
    //  13:  86-103 ->  172-206  3704-4479 Hz high mid
    //  14: 104-164 ->  208-328  4479-7106 Hz high (damped 0.88)
    //  15: 165-215 ->  330-430  7106-9259 Hz high (damped 0.70)
    const List<List<int>> wledBinMap = [
      [2, 2], [4, 4], [6, 8], [10, 12],
      [14, 18], [20, 24], [26, 36], [38, 50],
      [52, 64], [66, 86], [88, 110], [112, 138],
      [140, 170], [172, 206], [208, 328], [330, 430],
    ];
    // Damping factors for upper bins (matching WLED)
    const List<double> binDamping = [
      1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
      1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.88, 0.70,
    ];

    fftBins = [];
    for (int ch = 0; ch < fftBinCount; ch++) {
      int startBin = wledBinMap[ch][0];
      int endBin = wledBinMap[ch][1];
      double sum = 0;
      int count = 0;
      for (int j = startBin; j <= endBin && j < usableBins; j++) {
        sum += magnitudes[j];
        count++;
      }
      double avgMag = count > 0 ? sum / count : 0;
      avgMag *= binDamping[ch];
      // Apply AGC gain to FFT bins (matching WLED behaviour)
      double scaledMag = avgMag * 1000 * (_agc.enabled ? _agc.multAgc : 1.0);
      fftBins.add(scaledMag.toInt().clamp(0, 255));
    }

    double totalMagnitude = 0;
    if (magnitudes.isNotEmpty) {
      totalMagnitude = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    }
    fftMagnitude = totalMagnitude * 100 * (_agc.enabled ? _agc.multAgc : 1.0);

    int maxIndex = 0;
    double maxValue = 0;
    for (int i = 1; i < usableBins; i++) {
      if (magnitudes[i] > maxValue) {
        maxValue = magnitudes[i];
        maxIndex = i;
      }
    }
    fftMajorPeak = maxIndex * samplesPerSecond / fftSize;

    zeroCrossingCount = 0;
    for (int i = 1; i < audio.length; i++) {
      if ((audio[i] >= 0 && audio[i - 1] < 0) ||
          (audio[i] < 0 && audio[i - 1] >= 0)) {
        zeroCrossingCount++;
      }
    }

    int pressureInt = sampleRaw.toInt().clamp(0, 255);
    int pressureFrac = ((sampleRaw - pressureInt) * 256).toInt().clamp(0, 255);

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
    listener?.cancel();
    socket?.close();
    socket = null;

    setState(() {
      isRecording = false;
      startTime = null;
      sampleRaw = 0.0;
      sampleSmoothed = 0.0;
      peakDetected = 0;
      peakHold = 0.0;
      fftBins = List<int>.filled(16, 0);
      fftMagnitude = 0.0;
      fftMajorPeak = 0.0;
      zeroCrossingCount = 0;
    });
    _agc.reset();
    return true;
  }

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
              controller?.reverse();
            } else if (status == AnimationStatus.dismissed) {
              controller?.forward();
            }
          })
          ..forward();
  }

  Color _getBgColor() => (isRecording) ? Colors.red : Colors.cyan;

  Icon _getIcon() =>
      (isRecording) ? const Icon(Icons.stop) : const Icon(Icons.keyboard_voice);

  void _openSettings() {
    final addressController = TextEditingController(text: multicastAddressStr);
    final portController = TextEditingController(text: multicastPort.toString());
    bool dialogAgcEnabled = agcEnabled;
    int dialogAgcPreset = agcPresetIndex;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Multicast Address',
                    hintText: '239.0.0.1',
                  ),
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: portController,
                  decoration: const InputDecoration(
                    labelText: 'UDP Port',
                    hintText: '11988',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                SwitchListTile(
                  title: const Text('AGC'),
                  subtitle: const Text('Automatic Gain Control'),
                  value: dialogAgcEnabled,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setDialogState(() => dialogAgcEnabled = val),
                ),
                if (dialogAgcEnabled) ...[
                  const Text('AGC Mode', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Normal')),
                      ButtonSegment(value: 1, label: Text('Vivid')),
                      ButtonSegment(value: 2, label: Text('Lazy')),
                    ],
                    selected: {dialogAgcPreset},
                    onSelectionChanged: (val) => setDialogState(() => dialogAgcPreset = val.first),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final newAddress = addressController.text.trim();
                final newPort = int.tryParse(portController.text.trim());
                if (newAddress.isNotEmpty && newPort != null && newPort > 0 && newPort <= 65535) {
                  try {
                    InternetAddress(newAddress);
                    setState(() {
                      multicastAddressStr = newAddress;
                      multicastPort = newPort;
                      agcEnabled = dialogAgcEnabled;
                      agcPresetIndex = dialogAgcPreset;
                      _agc.enabled = agcEnabled;
                      _agc.preset = AgcPreset.values[agcPresetIndex];
                    });
                    _saveSettings();
                    Navigator.pop(context);
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid IP address')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid port number')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (page) {
      case 0:
        return Column(
          children: [
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
        return DetailsPage(
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
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: _openSettings,
              ),
            ],
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
    listener?.cancel();
    controller?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
