import 'dart:math';

import 'package:flutter/material.dart';

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
    final double barHeight = size.height - 40;
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

    // Level bar with green->yellow->red gradient
    double rawFraction = (sampleRaw / maxVal).clamp(0.0, 1.0);
    double barWidth = size.width * rawFraction;

    if (barWidth > 0) {
      final gradient = LinearGradient(
        colors: [Colors.green, Colors.green, Colors.yellow, Colors.red],
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

    // Smoothed level line
    double smthX = (sampleSmth / maxVal).clamp(0.0, 1.0) * size.width;
    final smthPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(smthX, barTop), Offset(smthX, barTop + barHeight), smthPaint);

    // Peak hold marker
    double peakX = (peakHold / maxVal).clamp(0.0, 1.0) * size.width;
    final peakPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    canvas.drawLine(Offset(peakX, barTop), Offset(peakX, barTop + barHeight), peakPaint);

    // Peak detected indicator
    if (peakDetected) {
      final dotPaint = Paint()..color = Colors.red;
      canvas.drawCircle(Offset(size.width - 12, barTop + 12), 8, dotPaint);
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
