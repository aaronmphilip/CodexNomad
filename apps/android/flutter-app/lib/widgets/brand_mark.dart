import 'package:flutter/material.dart';

class CodexNomadMark extends StatelessWidget {
  const CodexNomadMark({
    super.key,
    this.size = 44,
    this.showFrame = true,
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

    final bgPaint = Paint()..color = background;
    canvas.drawRRect(rrect, bgPaint);

    if (drawFrame) {
      final framePaint = Paint()
        ..color = frame
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.04;
      canvas.drawRRect(rrect.deflate(s * 0.02), framePaint);
    }

    final left = Path()
      ..moveTo(s * 0.44, s * 0.28)
      ..lineTo(s * 0.22, s * 0.50)
      ..lineTo(s * 0.44, s * 0.72)
      ..lineTo(s * 0.53, s * 0.62)
      ..lineTo(s * 0.39, s * 0.50)
      ..lineTo(s * 0.53, s * 0.38)
      ..close();
    canvas.drawPath(left, Paint()..color = purple);

    final slashPath = Path()
      ..moveTo(s * 0.67, s * 0.25)
      ..lineTo(s * 0.78, s * 0.25)
      ..lineTo(s * 0.56, s * 0.76)
      ..lineTo(s * 0.45, s * 0.76)
      ..close();
    canvas.drawPath(slashPath, Paint()..color = slash);

    final accentPaint = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.72, s * 0.24, s * 0.08, s * 0.08),
        Radius.circular(s * 0.018),
      ),
      accentPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.80, s * 0.64, s * 0.06, s * 0.06),
        Radius.circular(s * 0.015),
      ),
      accentPaint,
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
