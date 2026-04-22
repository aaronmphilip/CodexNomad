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
    final leftPaint = Paint()
      ..color = purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.bevel;
    final slashPaint = Paint()
      ..color = slash
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.92
      ..strokeCap = StrokeCap.square;

    final left = Path()
      ..moveTo(s * 0.46, s * 0.28)
      ..lineTo(s * 0.23, s * 0.50)
      ..lineTo(s * 0.46, s * 0.72);
    canvas.drawPath(left, leftPaint);

    canvas.drawLine(
      Offset(s * 0.73, s * 0.24),
      Offset(s * 0.53, s * 0.78),
      slashPaint,
    );

    final glintPaint = Paint()..color = accent;
    canvas.drawCircle(Offset(s * 0.81, s * 0.26), s * 0.035, glintPaint);
    canvas.drawCircle(Offset(s * 0.77, s * 0.73), s * 0.024, glintPaint);
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
