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

import 'dart:typed_data';

class AudioSyncPacket {
  static const List<int> header = [0x30, 0x30, 0x30, 0x30, 0x32, 0x00]; // "00002\0"
  List<int> pressure;
  double sampleRaw;
  double sampleSmth;
  int samplePeak;
  int frameCounter;
  List<int> fftResult;
  int zeroCrossingCount;
  double fftMagnitude;
  double fftMajorPeak;

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
