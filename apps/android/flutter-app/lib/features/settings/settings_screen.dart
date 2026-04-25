import 'package:codex_nomad/core/config/app_config.dart';
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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Local'),
              Tab(text: 'Cloud'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _localSettings(context, scheme),
            _cloudSettings(context, auth, scheme),
          ],
        ),
      ),
    );
  }

  Widget _localSettings(BuildContext context, ColorScheme scheme) {
    return ListView(
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
            secondary:
                Icon(Icons.notifications_active_rounded, color: scheme.primary),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.route_rounded, color: scheme.primary),
            title: const Text('Setup guide'),
            subtitle: const Text(
              'Replay local pairing and copy the current commands.',
            ),
            trailing: const Icon(Icons.arrow_forward_rounded),
            onTap: () => context.push('/onboarding'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.key_rounded, color: scheme.primary),
            title: const Text('Local secrets'),
            subtitle: const Text(
              'OpenAI, Anthropic, GitHub, and shell credentials stay on the computer. The phone sends encrypted actions only.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _cloudSettings(
    BuildContext context,
    AuthController auth,
    ColorScheme scheme,
  ) {
    final config = ref.watch(appConfigProvider);
    final cloudProvisioningEnabled = config.enableCloudProvisioning;
    final cloudReady = config.appSharedToken.trim().isNotEmpty || auth.signedIn;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Cloud Account', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.cloud_queue_rounded, color: scheme.primary),
            title: const Text('Cloud runner control'),
            subtitle: Text(
              !cloudProvisioningEnabled
                  ? 'Preview only in this build. Provisioning is disabled.'
                  : cloudReady
                      ? 'Start and monitor cloud sessions from phone.'
                      : 'Set app token or sign in first.',
            ),
            trailing: const Icon(Icons.arrow_forward_rounded),
            onTap: () => context.push('/cloud'),
          ),
        ),
        const SizedBox(height: 10),
        if (!auth.configured)
          Card(
            child: ListTile(
              leading: Icon(Icons.cloud_off_rounded, color: scheme.primary),
              title: const Text('Cloud backend not connected'),
              subtitle: const Text(
                'Local mode does not need it. Cloud mode will use the hosted account backend for sign-in, billing, and runner ownership.',
              ),
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
                    label: const Text('Send magic link'),
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
    );
  }
}
