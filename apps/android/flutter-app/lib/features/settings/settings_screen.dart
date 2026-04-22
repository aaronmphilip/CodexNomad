import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AgentKind _agent = AgentKind.codex;
  bool _notifications = true;
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Agent', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<AgentKind>(
            segments: const [
              ButtonSegment(
                value: AgentKind.codex,
                icon: Icon(Icons.terminal_rounded),
                label: Text('Codex'),
              ),
              ButtonSegment(
                value: AgentKind.claude,
                icon: Icon(Icons.auto_awesome_rounded),
                label: Text('Claude'),
              ),
            ],
            selected: {_agent},
            onSelectionChanged: (value) => setState(() => _agent = value.first),
          ),
          const SizedBox(height: 18),
          Card(
            child: SwitchListTile(
              value: _notifications,
              onChanged: (value) => setState(() => _notifications = value),
              title: const Text('Notifications'),
              subtitle: const Text('Approval and session update alerts'),
              secondary: Icon(Icons.notifications_active_rounded,
                  color: scheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.route_rounded, color: scheme.primary),
              title: const Text('Setup Guide'),
              subtitle: const Text(
                'Replay the local pairing walkthrough and copy commands.',
              ),
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: () => context.push('/onboarding'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.key_rounded, color: scheme.primary),
              title: const Text('API Key Management'),
              subtitle: const Text(
                  'Keys stay on the daemon. Mobile only sends encrypted commands.'),
            ),
          ),
          const SizedBox(height: 20),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (!auth.configured)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY at build time.'),
              ),
            )
          else if (auth.signedIn)
            Card(
              child: ListTile(
                leading: const Icon(Icons.verified_user_rounded),
                title: Text(auth.email ?? 'Signed in'),
                trailing: TextButton(
                  onPressed: auth.logout,
                  child: const Text('Logout'),
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: auth.busy
                          ? null
                          : () => auth.sendMagicLink(_email.text.trim()),
                      icon: const Icon(Icons.mail_rounded),
                      label: const Text('Send Magic Link'),
                    ),
                    if (auth.message != null) ...[
                      const SizedBox(height: 10),
                      Text(auth.message!),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
