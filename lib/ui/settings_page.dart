import '../core/i18n.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/utils.dart';
import 'about_page.dart';
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
      toast(context, tr('Introdu două adrese IPv4 valide', 'Enter two valid IPv4 addresses'));
      return;
    }
    appSettings.update((s) {
      s.customStart = a;
      s.customEnd = b;
      s.useCustomRange = true;
    });
    toast(context, tr('Interval salvat: $a – $b', 'Range saved: $a – $b'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) => Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar.medium(title: Text(tr('Setări', 'Settings'))),
            SliverToBoxAdapter(
              child: MaxWidth(
                width: 760,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(tr('Limbă', 'Language')),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                              value: 'system',
                              icon: const Icon(Icons.translate),
                              label: Text(tr('Auto', 'Auto'))),
                          const ButtonSegment(value: 'ro', label: Text('Română')),
                          const ButtonSegment(value: 'en', label: Text('English')),
                        ],
                        showSelectedIcon: false,
                        selected: {appSettings.language},
                        onSelectionChanged: (v) =>
                            appSettings.update((x) => x.language = v.first),
                      ),
                    ),
                    SectionHeader(tr('Aspect', 'Appearance')),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(
                              value: ThemeMode.system,
                              tooltip: tr('Ca sistemul', 'System'),
                              label: const Icon(Icons.brightness_auto_outlined)),
                          ButtonSegment(
                              value: ThemeMode.light,
                              tooltip: tr('Luminos', 'Light'),
                              label: const Icon(Icons.light_mode_outlined)),
                          ButtonSegment(
                              value: ThemeMode.dark,
                              tooltip: tr('Întunecat', 'Dark'),
                              label: const Icon(Icons.dark_mode_outlined)),
                        ],
                        showSelectedIcon: false,
                        selected: {appSettings.themeMode},
                        onSelectionChanged: (s) =>
                            appSettings.update((x) => x.themeMode = s.first),
                      ),
                    ),
                    SectionHeader(tr('Scanare', 'Scanning')),
                    SwitchListTile(
                      secondary: const Icon(Icons.network_ping),
                      title: Text(tr('Folosește ping (ICMP)', 'Use ping (ICMP)')),
                      subtitle: Text(
                          tr('Găsește mai multe dispozitive și estimează sistemul de operare', 'Finds more devices and estimates the operating system')),
                      value: appSettings.usePing,
                      onChanged: (v) => appSettings.update((s) => s.usePing = v),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.travel_explore),
                      title: Text(tr('Scanează porturile la fiecare scanare', 'Scan ports on every scan')),
                      subtitle: Text(tr('Verifică ~120 de porturi uzuale pe fiecare dispozitiv (mai lent, mai complet)',
                          'Checks ~120 common ports on every device (slower, more complete)')),
                      value: appSettings.scanPorts,
                      onChanged: (v) => appSettings.update((s) => s.scanPorts = v),
                    ),
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(tr('Timeout conexiune', 'Connection timeout')),
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
                      title: Text(tr('Conexiuni paralele (porturi)', 'Parallel connections (ports)')),
                      subtitle: Slider(
                        value: appSettings.portConcurrency.toDouble(),
                        min: 8,
                        max: 256,
                        divisions: 31,
                        label: '${appSettings.portConcurrency}',
                        onChanged: (v) => appSettings
                            .update((s) => s.portConcurrency = v.round()),
                      ),
                      trailing: Text('${appSettings.portConcurrency}'),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.tune),
                      title: Text(tr('Interval IP personalizat', 'Custom IP range')),
                      subtitle: Text(appSettings.useCustomRange
                          ? '${appSettings.customStart} – ${appSettings.customEnd}'
                          : tr('Automat: subrețeaua curentă', 'Automatic: current subnet')),
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
                                    InputDecoration(labelText: tr('De la', 'From')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _end,
                                decoration:
                                    InputDecoration(labelText: tr('Până la', 'To')),
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
                    SectionHeader(tr('Date', 'Data')),
                    ListTile(
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: Text(tr('Șterge istoricul dispozitivelor', 'Clear device history')),
                      subtitle: Text(
                          tr('Numele personalizate și dispozitivele offline', 'Custom names and offline devices')),
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(tr('Ștergi istoricul?', 'Clear history?')),
                            content: Text(
                                tr('Se pierd numele personalizate și lista dispozitivelor văzute anterior.', 'Custom names and the list of previously seen devices will be lost.')),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(tr('Anulează', 'Cancel'))),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(tr('Șterge', 'Clear'))),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await scanner.clearHistory();
                          if (context.mounted) toast(context, tr('Istoric șters', 'History cleared'));
                        }
                      },
                    ),
                    SectionHeader(tr('Despre', 'About')),
                    ListTile(
                      leading: Icon(Icons.radar, color: cs.primary),
                      title: const Text('NetScan'),
                      subtitle: Text(tr('by norAz · fără reclame', 'by norAz · no ads')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) => const AboutPage())),
                    ),
                    const SizedBox(height: 32),
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
