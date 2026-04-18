import 'package:flutter/material.dart';

/// Spectrum Analyser - 16 frequency bins as bars with major peak label
class SpectrumPainter extends CustomPainter {
  final List<int> fftBins;
  final double majorPeak;

  // Frequency labels matching WLED's 16 GEQ channels
  static const List<String> binLabels = [
    '65', '108', '172', '258', '366', '495', '689', '969',
    '1.3k', '1.7k', '2.2k', '2.7k', '3.4k', '4.1k', '5.8k', '8.2k',
  ];

  SpectrumPainter({required this.fftBins, required this.majorPeak});

  @override
  void paint(Canvas canvas, Size size) {
    if (fftBins.isEmpty) return;

    final int binCount = fftBins.length;
    final double spacing = 3;
    final double labelHeight = 36;
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

    // Grid lines at 25%, 50%, 75%
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

      // Frequency label
      if (i < binLabels.length) {
        final labelStyle = TextStyle(color: Colors.grey.shade500, fontSize: 8);
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
    peakTp.paint(canvas, Offset((size.width - peakTp.width) / 2, barAreaHeight + 18));
  }

  @override
  bool shouldRepaint(SpectrumPainter old) => true;
}
