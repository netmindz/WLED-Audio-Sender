import 'dart:async';
import 'dart:ffi' as types;
import 'dart:io';
import 'dart:math';
import 'dart:core';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import 'package:mic_stream/mic_stream.dart';

enum Command {
  start,
  stop,
  change,
}

const AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT;

class AudioSyncPacket {
  // TODO: actually check these dart types return the right number of bytes!
  String header = "00002";      //  06 Bytes
  types.Float  sampleRaw; //  04 Bytes  - either "sampleRaw" or "rawSampleAgc" depending on soundAgc setting
  types.Float  sampleSmth; //  04 Bytes  - either "sampleAvg" or "sampleAgc" depending on soundAgc setting
  types.Uint8  samplePeak; //  01 Bytes  - 0 no peak; >=1 peak detected. In future, this will also provide peak Magnitude
  types.Uint8 reserved1 = types.Uint8(); //  01 Bytes  - for future extensions - not used yet
  List<Float64List> fftResult = []; //  16 Bytes
  types.Float FFT_Magnitude; //  04 Bytes
  types.Float FFT_MajorPeak; //  04 Bytes

  AudioSyncPacket(this.sampleRaw, this.sampleSmth, this.samplePeak,
      this.fftResult, this.FFT_Magnitude, this.FFT_MajorPeak);

  List<int> asBytes() {
    List<int> bytes = [];
    bytes.addAll(header.codeUnits);
    fftResult.forEach((element) { 
      bytes.addAll(e.toString().codeUnits); // todo really not sure about this
    });
    return bytes;
  }
}


void main() => runApp(WLEDAudioSenderApp());

class WLEDAudioSenderApp extends StatefulWidget {
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
  InternetAddress multicastAddress = new InternetAddress('239.0.0.1');
  int multicastPort = 12345; // TODO: Change to 11988 once we have working system, not break my current setup

  Random rng = new Random();

  // Refreshes the Widget for every possible tick to force a rebuild of the sound wave
  late AnimationController controller;

  Color _iconColor = Colors.white;
  bool isRecording = false;
  bool memRecordingState = false;
  late bool isActive;
  DateTime? startTime;

  int page = 0;
  List state = ["SoundWavePage", "IntensityWavePage", "InformationPage"];

  @override
  void initState() {
    print("Init application");
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    setState(() {
      initPlatformState();
    });
  }

  void _controlPage(int index) => setState(() => page = index);

  // Responsible for switching between recording / idle state
  void _controlMicStream({Command command: Command.change}) async {
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
    print("START LISTENING");
    if (isRecording) return false;
    // if this is the first time invoking the microphone()
    // method to get the stream, we don't yet have access
    // to the sampleRate and bitDepth properties
    print("wait for stream");

    // Default option. Set to false to disable request permission dialogue
    MicStream.shouldRequestPermission(true);

    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
        .then((RawDatagramSocket s) {
      print("UDP Socket ready to send to group "
          "${multicastAddress.address}:${multicastPort}");
      socket = s;
    });

    stream = await MicStream.microphone(
        audioSource: AudioSource.DEFAULT,
        sampleRate: 1000 * (rng.nextInt(50) + 30),
        channelConfig: ChannelConfig.CHANNEL_IN_MONO,
        audioFormat: AUDIO_FORMAT);
    // after invoking the method for the first time, though, these will be available;
    // It is not necessary to setup a listener first, the stream only needs to be returned first
    print(
        "Start Listening to the microphone, sample rate is ${await MicStream.sampleRate}, bit depth is ${await MicStream.bitDepth}, bufferSize: ${await MicStream.bufferSize}");
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
    if (page == 0)
      _calculateWaveSamples(samples);
    else if (page == 1) _calculateIntensitySamples(samples);
    List<double> audio = [];
    List<int> tmp = samples;
    tmp.forEach((element) {
      audio.add(element.toDouble());
    });

    // TODO: actually configure the FFT properly
    final chunkSize = 200;
    final stft = STFT(chunkSize, Window.hanning(chunkSize));

    final spectrogram = <Float64List>[];
    stft.run(audio, (Float64x2List freq) {
      spectrogram.add(freq.discardConjugates().magnitudes());
    });
    print("bin count = ");
    print(spectrogram.length);
    // print("sample count = ");
    // print(audio.length);
    AudioSyncPacket packet = new AudioSyncPacket(
        types.Float(),
        new types.Float(),
        new types.Uint8(),
        spectrogram,
        new types.Float(),
        new types.Float());

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
    print("Stop Listening to the microphone");
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

    Statistics(false);

    controller =
        AnimationController(duration: Duration(seconds: 1), vsync: this)
          ..addListener(() {
            if (isRecording) setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed)
              controller.reverse();
            else if (status == AnimationStatus.dismissed) controller.forward();
          })
          ..forward();
  }

  Color _getBgColor() => (isRecording) ? Colors.red : Colors.cyan;

  Icon _getIcon() =>
      (isRecording) ? Icon(Icons.stop) : Icon(Icons.keyboard_voice);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
          appBar: AppBar(
            title: const Text('WLED Audio Sender'),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _controlMicStream,
            child: _getIcon(),
            foregroundColor: _iconColor,
            backgroundColor: _getBgColor(),
            tooltip: (isRecording) ? "Stop recording" : "Start recording",
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: [
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
      print("Resume app");

      _controlMicStream(
          command: memRecordingState ? Command.start : Command.stop);
    } else if (isActive) {
      memRecordingState = isRecording;
      _controlMicStream(command: Command.stop);

      print("Pause app");
      isActive = false;
    }
  }

  @override
  void dispose() {
    listener.cancel();
    controller.dispose();
    WidgetsBinding.instance!.removeObserver(this);
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

    Paint paint = new Paint()
      ..color = color!
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    if (samples!.length == 0) return;

    points = toPoints(samples);

    Path path = new Path();
    path.addPolygon(points, false);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldPainting) => true;

  // Maps a list of ints and their indices to a list of points on a cartesian grid
  List<Offset> toPoints(List<int>? samples) {
    List<Offset> points = [];
    if (samples == null)
      samples = List<int>.filled(size!.width.toInt(), (0.5).toInt());
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

  Statistics(this.isRecording, {this.startTime});

  @override
  Widget build(BuildContext context) {
    return ListView(children: <Widget>[
      ListTile(
          leading: Icon(Icons.title),
          title: Text("Microphone Streaming Example App")),
      ListTile(
        leading: Icon(Icons.keyboard_voice),
        title: Text((isRecording ? "Recording" : "Not recording")),
      ),
      ListTile(
          leading: Icon(Icons.access_time),
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
