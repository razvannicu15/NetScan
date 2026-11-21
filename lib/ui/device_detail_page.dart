import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/ports.dart';
import '../models/device.dart';
import '../services/protocols.dart';
import 'port_scan_page.dart';
import 'tools_page.dart';
import 'widgets.dart';

class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({super.key, required this.device});
  final Device device;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  Device get d => widget.device;

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: d.customName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redenumește dispozitivul'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: d.autoName,
            labelText: 'Nume personalizat',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Resetează')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Salvează')),
        ],
      ),
    );
    if (name == null) return;
    await scanner.rename(d, name);
    if (mounted) setState(() {});
  }

  Future<void> _wake() async {
    final ok = await WakeOnLan.send(d.mac!, broadcast: scanner.network?.broadcast);
    if (mounted) {
      toast(context, ok ? 'Pachet Wake-on-LAN trimis' : 'Nu s-a putut trimite');
    }
  }

  Future<void> _openWeb(int port) async {
    final https = kHttpsPorts.contains(port);
    final uri = Uri.parse(
        '${https ? 'https' : 'http'}://${d.ip}${(port == 80 || port == 443) ? '' : ':$port'}/');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, 'Nu pot deschide $uri');
  }

  Future<void> _forget() async {
    await scanner.forget(d);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ports = d.allKnownPorts.toList()..sort();
    final webPorts =
        ports.where((p) => kHttpPorts.contains(p) || kHttpsPorts.contains(p));

    return Scaffold(
      appBar: AppBar(
        title: Text(d.displayName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Redenumește',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _rename,
          ),
          if (!d.online)
            IconButton(
              tooltip: 'Uită dispozitivul',
              icon: const Icon(Icons.delete_outline),
              onPressed: _forget,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          MaxWidth(
            width: 760,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  DeviceAvatar(device: d, size: 72),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.displayName,
                            style: tt.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(d.type.label,
                            style: tt.bodyLarge
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          TagChip(d.online ? 'ONLINE' : 'OFFLINE',
                              color: d.online
                                  ? cs.secondaryContainer
                                  : cs.surfaceContainerHighest,
                              onColor: d.online
                                  ? cs.onSecondaryContainer
                                  : cs.onSurfaceVariant),
                          if (d.isSelf) const TagChip('ACEST DISPOZITIV'),
                          if (d.isGateway)
                            TagChip('GATEWAY',
                                color: cs.tertiaryContainer,
                                onColor: cs.onTertiaryContainer),
                          if (d.isNew)
                            TagChip('NOU',
                                color: cs.errorContainer,
                                onColor: cs.onErrorContainer),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          MaxWidth(
            width: 760,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PortScanPage(host: d.ip, device: d),
                      ),
                    ).then((_) => setState(() {})),
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Scanează porturi'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PingPage(initialHost: d.ip),
                      ),
                    ),
                    icon: const Icon(Icons.network_ping),
                    label: const Text('Ping'),
                  ),
                  if (d.mac != null && !d.isSelf)
                    FilledButton.tonalIcon(
                      onPressed: _wake,
                      icon: const Icon(Icons.power_settings_new),
                      label: const Text('Wake-on-LAN'),
                    ),
                  for (final p in webPorts.take(3))
                    OutlinedButton.icon(
                      onPressed: () => _openWeb(p),
                      icon: const Icon(Icons.open_in_browser),
                      label: Text('Web :$p'),
                    ),
                ],
              ),
            ),
          ),
          MaxWidth(
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader('Identificare'),
                InfoRow(Icons.lan_outlined, 'Adresă IP', d.ip),
                InfoRow(
                    Icons.fingerprint,
                    'Adresă MAC',
                    d.mac ??
                        (d.isSelf
                            ? null
                            : 'Indisponibilă (Android 10+ blochează tabela ARP)')),
                InfoRow(Icons.factory_outlined, 'Producător', d.vendor),
                InfoRow(Icons.dns_outlined, 'Hostname (DNS)', d.hostname),
                InfoRow(Icons.badge_outlined, 'Nume NetBIOS', d.netbiosName),
                InfoRow(Icons.groups_outlined, 'Grup de lucru', d.workgroup),
                InfoRow(Icons.cell_tower, 'Nume mDNS / Bonjour', d.mdnsName),
                InfoRow(Icons.cast_outlined, 'Nume UPnP', d.upnpName),
                InfoRow(
                    Icons.precision_manufacturing_outlined,
                    'Model UPnP',
                    [d.upnpManufacturer, d.upnpModel]
                        .whereType<String>()
                        .join(' ')
                        .trim()),
                InfoRow(Icons.memory, 'Server', d.serverHeader),
                InfoRow(Icons.computer, 'Sistem (după TTL)',
                    d.osGuess == null ? null : '${d.osGuess} · TTL ${d.ttl}',
                    copy: false),
                InfoRow(
                    Icons.speed,
                    'Latență',
                    d.latencyMs == null
                        ? null
                        : '${d.latencyMs!.toStringAsFixed(1)} ms',
                    copy: false),
                InfoRow(Icons.history, 'Văzut prima dată',
                    timeAgo(d.firstSeen),
                    copy: false),
                if (!d.online)
                  InfoRow(Icons.schedule, 'Văzut ultima dată',
                      timeAgo(d.lastSeen),
                      copy: false),
                SectionHeader('Porturi deschise · ${ports.length}'),
                if (ports.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Niciun port cunoscut încă. Rulează o scanare de porturi '
                      'pentru detalii complete.',
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                for (final p in ports)
                  PortTile(
                    port: p,
                    banner: d.openPorts
                        .where((o) => o.port == p)
                        .map((o) => o.banner)
                        .firstOrNull,
                    onOpen: (kHttpPorts.contains(p) || kHttpsPorts.contains(p))
                        ? () => _openWeb(p)
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PortTile extends StatelessWidget {
  const PortTile({super.key, required this.port, this.banner, this.onOpen});
  final int port;
  final String? banner;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text('$port',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSecondaryContainer,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
      title: Text(serviceName(port)),
      subtitle: banner == null || banner!.isEmpty
          ? null
          : Text(banner!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: onOpen == null
          ? null
          : IconButton(
              tooltip: 'Deschide în browser',
              icon: const Icon(Icons.open_in_new),
              onPressed: onOpen,
            ),
    );
  }
}
