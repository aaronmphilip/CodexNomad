import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  final _scanner = MobileScannerController();
  AgentKind _agent = AgentKind.codex;
  bool _handled = false;

  String get _command {
    return _agent == AgentKind.claude
        ? 'codexnomad pair claude'
        : 'codexnomad pair';
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair Local'),
        actions: [
          IconButton(
            tooltip: 'Paste command',
            onPressed: _copyCommand,
            icon: const Icon(PhosphorIconsRegular.copy),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _handleDetect,
          ),
          const _ScannerShade(),
          const Center(child: _ScanFrame()),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: scheme.surface.withValues(alpha: 0.96),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          PhosphorIconsRegular.laptop,
                          color: scheme.secondary,
                          size: 21,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Run this on your computer. It prints the QR this camera needs, while keys and local tools stay on that computer.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<AgentKind>(
                      segments: const [
                        ButtonSegment(
                          value: AgentKind.codex,
                          icon: Icon(PhosphorIconsRegular.terminalWindow),
                          label: Text('Codex'),
                        ),
                        ButtonSegment(
                          value: AgentKind.claude,
                          icon: Icon(PhosphorIconsRegular.sparkle),
                          label: Text('Claude'),
                        ),
                      ],
                      selected: {_agent},
                      onSelectionChanged: (value) {
                        setState(() => _agent = value.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    _CommandStrip(
                      command: _command,
                      onCopy: _copyCommand,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCommand() async {
    await Clipboard.setData(ClipboardData(text: _command));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $_command')),
    );
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final value =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    HapticFeedback.mediumImpact();
    try {
      await ref.read(sessionControllerProvider).connectFromQr(value);
      if (mounted) context.go('/live');
    } catch (error) {
      _handled = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }
}

class _ScannerShade extends StatelessWidget {
  const _ScannerShade();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.72),
              Colors.black.withValues(alpha: 0.18),
              Colors.black.withValues(alpha: 0.18),
              Colors.black.withValues(alpha: 0.82),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      widthFactor: 0.72,
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _FramePainter(
            color: scheme.primary,
            outline: scheme.onSurface.withValues(alpha: 0.28),
          ),
        ),
      ),
    );
  }
}

class _CommandStrip extends StatelessWidget {
  const _CommandStrip({
    required this.command,
    required this.onCopy,
  });

  final String command;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsRegular.terminal,
            color: scheme.secondary,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Copy command',
            onPressed: onCopy,
            icon: const Icon(PhosphorIconsRegular.copy),
          ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({
    required this.color,
    required this.outline,
  });

  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final cornerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, outlinePaint);

    final leg = size.shortestSide * 0.18;
    final path = Path()
      ..moveTo(0, leg)
      ..lineTo(0, 0)
      ..lineTo(leg, 0)
      ..moveTo(size.width - leg, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, leg)
      ..moveTo(size.width, size.height - leg)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - leg, size.height)
      ..moveTo(leg, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, size.height - leg);
    canvas.drawPath(path, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.outline != outline;
  }
}
