import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mic_stream/mic_stream.dart';

// import 'package:fftea/fftea.dart';
import 'package:record/record.dart';

import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:math' as math;

Float64List normalizeRmsVolume(List<double> a, double target) {
  final b = Float64List.fromList(a);
  double squareSum = 0;
  for (final x in b) {
    squareSum += x * x;
  }
  double factor = target * math.sqrt(b.length / squareSum);
  for (int i = 0; i < b.length; ++i) {
    b[i] *= factor;
  }
  return b;
}

Uint64List linSpace(int end, int steps) {
  final a = Uint64List(steps);
  for (int i = 1; i < steps; ++i) {
    a[i - 1] = (end * i) ~/ steps;
  }
  a[steps - 1] = end;
  return a;
}

String gradient(double power) {
  const scale = 2;
  const levels = [' ', '░', '▒', '▓', '█'];
  int index = math.log((power * levels.length) * scale).floor();
  if (index < 0) index = 0;
  if (index >= levels.length) index = levels.length - 1;
  return levels[index];
}

void main() {
  InternetAddress multicastAddress = new InternetAddress('239.0.0.1');
  int multicastPort = 11988;
  Random rng = new Random();
  RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
      .then((RawDatagramSocket s) {
    print("UDP Socket ready to send to group "
        "${multicastAddress.address}:${multicastPort}");

    new Timer.periodic(new Duration(seconds: 1), (Timer t) {
      //Send a random number out every second
      String msg = '${rng.nextInt(1000)}';
      stdout.write("Sending $msg  \r");
      s.send('$msg\n'.codeUnits, multicastAddress, multicastPort);
    });
  });

  Stream<Uint8List>? stream = await MicStream.microphone(
    sampleRate: 32000,
    audioFormat: AudioFormat.ENCODING_PCM_8BIT,
  );
  int? bufferSize = await MicStream.bufferSize;
  StreamSubscription<List<int>> listener = stream!.listen((sample) async {
    // handle audio here
  });

  final audio = normalizeRmsVolume(wav.toMono(), 0.3);
  const chunkSize = 2048;
  const buckets = 120;
  final stft = STFT(chunkSize, Window.hanning(chunkSize));
  Uint64List? logItr;
  stft.run(
    audio,
    (Float64x2List chunk) {
      final amp = chunk.discardConjugates().magnitudes();
      logItr ??= linSpace(amp.length, buckets);
      int i0 = 0;
      for (final i1 in logItr!) {
        double power = 0;
        if (i1 != i0) {
          for (int i = i0; i < i1; ++i) {
            power += amp[i];
          }
          power /= i1 - i0;
        }
        stdout.write(gradient(power));
        i0 = i1;
      }
      stdout.write('\n');
    },
    chunkSize ~/ 2,
  );

  runApp(const MyApp());
}

class audioSyncPacket {
// TODO: actually check these dart types return the right number of bytes!
  // char    header[6];      //  06 Bytes
  Float
      sampleRaw; //  04 Bytes  - either "sampleRaw" or "rawSampleAgc" depending on soundAgc setting
  Float
      sampleSmth; //  04 Bytes  - either "sampleAvg" or "sampleAgc" depending on soundAgc setting
  Uint8
      samplePeak; //  01 Bytes  - 0 no peak; >=1 peak detected. In future, this will also provide peak Magnitude
  Uint8 reserved1; //  01 Bytes  - for future extensions - not used yet
  List<Uint8> fftResult = List<Uint8>.filled(16, 0 as Uint8); //  16 Bytes
  Float FFT_Magnitude; //  04 Bytes
  Float FFT_MajorPeak; //  04 Bytes

  audioSyncPacket(this.sampleRaw, this.sampleSmth, this.samplePeak,
      this.reserved1, this.fftResult, this.FFT_Magnitude, this.FFT_MajorPeak);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'WLED Audio Sender'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
        ),
      ),
    );
  }
}
