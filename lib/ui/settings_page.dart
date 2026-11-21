import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/utils.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _start = TextEditingController(text: appSettings.customStart);
  late final _end = TextEditingController(text: appSettings.customEnd);

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _saveRange() {
    final a = _start.text.trim(), b = _end.text.trim();
    if (!isValidIp(a) || !isValidIp(b)) {
      toast(context, 'Introdu două adrese IPv4 valide');
      return;
    }
    appSettings.update((s) {
      s.customStart = a;
      s.customEnd = b;
      s.useCustomRange = true;
    });
    toast(context, 'Interval salvat: $a – $b');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) => Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverAppBar.medium(title: Text('Setări')),
            SliverToBoxAdapter(
              child: MaxWidth(
                width: 760,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader('Aspect'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined),
                              label: Text('Sistem')),
                          ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Luminos')),
                          ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Întunecat')),
                        ],
                        selected: {appSettings.themeMode},
                        onSelectionChanged: (s) =>
                            appSettings.update((x) => x.themeMode = s.first),
                      ),
                    ),
                    const SectionHeader('Scanare'),
                    SwitchListTile(
                      secondary: const Icon(Icons.network_ping),
                      title: const Text('Folosește ping (ICMP)'),
                      subtitle: const Text(
                          'Găsește mai multe dispozitive și estimează sistemul de operare'),
                      value: appSettings.usePing,
                      onChanged: (v) => appSettings.update((s) => s.usePing = v),
                    ),
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('Timeout conexiune'),
                      subtitle: Slider(
                        value: appSettings.probeTimeoutMs.toDouble(),
                        min: 200,
                        max: 3000,
                        divisions: 28,
                        label: '${appSettings.probeTimeoutMs} ms',
                        onChanged: (v) => appSettings
                            .update((s) => s.probeTimeoutMs = v.round()),
                      ),
                      trailing: Text('${appSettings.probeTimeoutMs} ms'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.bolt_outlined),
                      title: const Text('Conexiuni paralele (porturi)'),
                      subtitle: Slider(
                        value: appSettings.portConcurrency.toDouble(),
                        min: 16,
                        max: 512,
                        divisions: 31,
                        label: '${appSettings.portConcurrency}',
                        onChanged: (v) => appSettings
                            .update((s) => s.portConcurrency = v.round()),
                      ),
                      trailing: Text('${appSettings.portConcurrency}'),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.tune),
                      title: const Text('Interval IP personalizat'),
                      subtitle: Text(appSettings.useCustomRange
                          ? '${appSettings.customStart} – ${appSettings.customEnd}'
                          : 'Automat: subrețeaua curentă'),
                      value: appSettings.useCustomRange,
                      onChanged: (v) {
                        if (v &&
                            (!isValidIp(appSettings.customStart) ||
                                !isValidIp(appSettings.customEnd))) {
                          final net = scanner.network;
                          if (net != null && net.hosts.isNotEmpty) {
                            _start.text = net.hosts.first;
                            _end.text = net.hosts.last;
                          }
                          _saveRange();
                          return;
                        }
                        appSettings.update((s) => s.useCustomRange = v);
                      },
                    ),
                    if (appSettings.useCustomRange)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _start,
                                decoration:
                                    const InputDecoration(labelText: 'De la'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _end,
                                decoration:
                                    const InputDecoration(labelText: 'Până la'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: _saveRange,
                              icon: const Icon(Icons.check),
                            ),
                          ],
                        ),
                      ),
                    const SectionHeader('Date'),
                    ListTile(
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: const Text('Șterge istoricul dispozitivelor'),
                      subtitle: const Text(
                          'Numele personalizate și dispozitivele offline'),
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Ștergi istoricul?'),
                            content: const Text(
                                'Se pierd numele personalizate și lista dispozitivelor văzute anterior.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Anulează')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Șterge')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await scanner.clearHistory();
                          if (context.mounted) toast(context, 'Istoric șters');
                        }
                      },
                    ),
                    const SectionHeader('Despre'),
                    ListTile(
                      leading: Icon(Icons.radar, color: cs.primary),
                      title: const Text('NetScan 1.0'),
                      subtitle: const Text(
                          'Scanner de rețea: dispozitive, IP, MAC, producător, porturi.'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                      child: Text(
                        'Notă Android: începând cu Android 10, aplicațiile nu mai pot citi '
                        'tabela ARP, deci adresa MAC apare doar pentru dispozitivele care o '
                        'anunță prin NetBIOS (ex. PC-uri Windows). Pe Windows, MAC-ul apare '
                        'pentru toate dispozitivele din rețeaua locală.\n\n'
                        'Folosește NetScan doar în rețele pe care le administrezi sau ai '
                        'permisiunea să le scanezi.',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
