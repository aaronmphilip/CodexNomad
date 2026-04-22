import 'package:flutter/material.dart';

class CodexNomadMark extends StatelessWidget {
  const CodexNomadMark({
    super.key,
    this.size = 44,
    this.showFrame = false,
  });

  final double size;
  final bool showFrame;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _CodexNomadMarkPainter(
          background: scheme.surfaceContainerHighest.withValues(alpha: 0.96),
          frame: scheme.outline.withValues(alpha: 0.94),
          purple: scheme.primary,
          slash: scheme.onSurface,
          accent: scheme.secondary,
          drawFrame: showFrame,
        ),
      ),
    );
  }
}

class _CodexNomadMarkPainter extends CustomPainter {
  const _CodexNomadMarkPainter({
    required this.background,
    required this.frame,
    required this.purple,
    required this.slash,
    required this.accent,
    required this.drawFrame,
  });

  final Color background;
  final Color frame;
  final Color purple;
  final Color slash;
  final Color accent;
  final bool drawFrame;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & Size.square(s);
    final radius = Radius.circular(s * 0.18);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    if (drawFrame) {
      final bgPaint = Paint()..color = background;
      canvas.drawRRect(rrect, bgPaint);

      final framePaint = Paint()
        ..color = frame
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.04;
      canvas.drawRRect(rrect.deflate(s * 0.02), framePaint);
    }

    final stroke = s * 0.105;
    final glowPaint = Paint()
      ..color = purple.withValues(alpha: 0.36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 1.38
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.045);
    final leftPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [purple, accent, slash.withValues(alpha: 0.88)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final slashPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [purple, accent, slash.withValues(alpha: 0.92)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.92
      ..strokeCap = StrokeCap.round;

    final left = Path()
      ..moveTo(s * 0.46, s * 0.28)
      ..lineTo(s * 0.23, s * 0.50)
      ..lineTo(s * 0.46, s * 0.72);
    canvas.drawPath(left, glowPaint);
    canvas.drawPath(left, leftPaint);

    canvas.drawLine(
      Offset(s * 0.73, s * 0.24),
      Offset(s * 0.53, s * 0.78),
      glowPaint,
    );
    canvas.drawLine(
      Offset(s * 0.73, s * 0.24),
      Offset(s * 0.53, s * 0.78),
      slashPaint,
    );

    final edgePaint = Paint()
      ..color = slash.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.01
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(left, edgePaint);
    canvas.drawLine(
      Offset(s * 0.73, s * 0.24),
      Offset(s * 0.53, s * 0.78),
      edgePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CodexNomadMarkPainter oldDelegate) {
    return oldDelegate.background != background ||
        oldDelegate.frame != frame ||
        oldDelegate.purple != purple ||
        oldDelegate.slash != slash ||
        oldDelegate.accent != accent ||
        oldDelegate.drawFrame != drawFrame;
  }
}
