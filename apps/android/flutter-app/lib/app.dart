import 'package:codex_nomad/core/theme/app_theme.dart';
import 'package:codex_nomad/features/home/home_screen.dart';
import 'package:codex_nomad/features/live/live_session_screen.dart';
import 'package:codex_nomad/features/machines/machines_screen.dart';
import 'package:codex_nomad/features/onboarding/onboarding_screen.dart';
import 'package:codex_nomad/features/qr/qr_scanner_screen.dart';
import 'package:codex_nomad/features/settings/settings_screen.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:codex_nomad/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CodexNomadApp extends StatelessWidget {
  const CodexNomadApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const _StartupGate()),
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingScreen(),
        ),
        GoRoute(path: '/scan', builder: (_, __) => const QrScannerScreen()),
        GoRoute(path: '/live', builder: (_, __) => const LiveSessionScreen()),
        GoRoute(path: '/machines', builder: (_, __) => const MachinesScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Codex Nomad',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}

class _StartupGate extends ConsumerWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingControllerProvider);
    if (!onboarding.loaded) {
      return const _LaunchScreen();
    }
    if (!onboarding.completed) {
      return const OnboardingScreen();
    }
    return const HomeScreen();
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.94, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: Transform.scale(scale: value, child: child),
                  );
                },
                child: const CodexNomadMark(size: 64),
              ),
              const SizedBox(height: 18),
              Text(
                'Codex Nomad',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
