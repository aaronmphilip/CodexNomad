import 'package:codex_nomad/core/theme/app_theme.dart';
import 'package:codex_nomad/features/home/home_screen.dart';
import 'package:codex_nomad/features/live/live_session_screen.dart';
import 'package:codex_nomad/features/qr/qr_scanner_screen.dart';
import 'package:codex_nomad/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CodexNomadApp extends StatelessWidget {
  const CodexNomadApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/scan', builder: (_, __) => const QrScannerScreen()),
        GoRoute(path: '/live', builder: (_, __) => const LiveSessionScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Codex Nomad',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
