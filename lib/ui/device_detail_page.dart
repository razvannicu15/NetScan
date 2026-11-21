import '../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/ports.dart';
import '../models/device.dart';
import '../services/protocols.dart';
import 'port_scan_page.dart';
import 'tools_page.dart';
import 'traceroute_page.dart';
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
        title: Text(tr('Redenumește dispozitivul', 'Rename device')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: d.autoName,
            labelText: tr('Nume personalizat', 'Custom name'),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(tr('Resetează', 'Reset'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Salvează', 'Save'))),
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
      toast(context, ok ? tr('Pachet Wake-on-LAN trimis', 'Wake-on-LAN packet sent') : tr('Nu s-a putut trimite', 'Could not send'));
    }
  }

  Future<void> _openWeb(int port) async {
    final https = kHttpsPorts.contains(port);
    final uri = Uri.parse(
        '${https ? 'https' : 'http'}://${d.ip}${(port == 80 || port == 443) ? '' : ':$port'}/');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, tr('Nu pot deschide $uri', 'Cannot open $uri'));
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
            tooltip: tr('Redenumește', 'Rename'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _rename,
          ),
          if (!d.online)
            IconButton(
              tooltip: tr('Uită dispozitivul', 'Forget device'),
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
                          if (d.isSelf) TagChip(tr('ACEST DISPOZITIV', 'THIS DEVICE')),
                          if (d.isGateway)
                            TagChip('GATEWAY',
                                color: cs.tertiaryContainer,
                                onColor: cs.onTertiaryContainer),
                          if (d.isNew)
                            TagChip(tr('NOU', 'NEW'),
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
                    label: Text(tr('Scanează porturi', 'Scan ports')),
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
                  if (!d.isSelf)
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => TraceroutePage(initialHost: d.ip),
                        ),
                      ),
                      icon: const Icon(Icons.route_outlined),
                      label: const Text('Traceroute'),
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
                SectionHeader(tr('Identificare', 'Identification')),
                InfoRow(Icons.lan_outlined, tr('Adresă IP', 'IP address'), d.ip),
                InfoRow(
                    Icons.fingerprint,
                    tr('Adresă MAC', 'MAC address'),
                    d.mac ??
                        (d.isSelf
                            ? null
                            : tr('Indisponibilă (Android 10+ blochează tabela ARP)', 'Unavailable (Android 10+ blocks the ARP table)'))),
                InfoRow(Icons.factory_outlined, tr('Producător', 'Vendor'), d.vendor),
                InfoRow(Icons.dns_outlined, 'Hostname (DNS)', d.hostname),
                InfoRow(Icons.badge_outlined, tr('Nume NetBIOS', 'NetBIOS name'), d.netbiosName),
                InfoRow(Icons.groups_outlined, tr('Grup de lucru', 'Workgroup'), d.workgroup),
                InfoRow(Icons.cell_tower, tr('Nume mDNS / Bonjour', 'mDNS / Bonjour name'), d.mdnsName),
                InfoRow(Icons.cast_outlined, tr('Nume UPnP', 'UPnP name'), d.upnpName),
                InfoRow(
                    Icons.precision_manufacturing_outlined,
                    tr('Model UPnP', 'UPnP model'),
                    [d.upnpManufacturer, d.upnpModel]
                        .whereType<String>()
                        .join(' ')
                        .trim()),
                InfoRow(Icons.memory, 'Server', d.serverHeader),
                InfoRow(Icons.computer, tr('Sistem (după TTL)', 'OS (from TTL)'),
                    d.osGuess == null ? null : '${d.osGuess} · TTL ${d.ttl}',
                    copy: false),
                InfoRow(
                    Icons.speed,
                    tr('Latență', 'Latency'),
                    d.latencyMs == null
                        ? null
                        : '${d.latencyMs!.toStringAsFixed(1)} ms',
                    copy: false),
                InfoRow(Icons.history, tr('Văzut prima dată', 'First seen'),
                    timeAgo(d.firstSeen),
                    copy: false),
                if (!d.online)
                  InfoRow(Icons.schedule, tr('Văzut ultima dată', 'Last seen'),
                      timeAgo(d.lastSeen),
                      copy: false),
                SectionHeader(tr('Porturi deschise · ${ports.length}', 'Open ports · ${ports.length}')),
                if (ports.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      tr('Niciun port cunoscut încă. Rulează o scanare de porturi pentru detalii complete.',
                          'No known ports yet. Run a port scan for full details.'),
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
              tooltip: tr('Deschide în browser', 'Open in browser'),
              icon: const Icon(Icons.open_in_new),
              onPressed: onOpen,
            ),
    );
  }
}
