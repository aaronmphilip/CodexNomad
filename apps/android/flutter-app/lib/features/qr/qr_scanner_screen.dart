import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) async {
              if (_handled) return;
              final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
              if (value == null) return;
              _handled = true;
              try {
                await ref.read(sessionControllerProvider).connectFromQr(value);
                if (context.mounted) context.go('/live');
              } catch (error) {
                _handled = false;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$error')),
                  );
                }
              }
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
              ),
              child: const Row(
                children: [
                  Icon(Icons.qr_code_scanner_rounded),
                  SizedBox(width: 12),
                  Expanded(child: Text('Scan the QR from your terminal')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
